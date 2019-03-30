defmodule TrivServer do
  @gate_time_secs 5

  require Logger
  use GenServer

  alias TrivServer.State

  # api

  def update_question(q), do: GenServer.call(__MODULE__, {:question, q})
  def buzz(peer, team_token), do: GenServer.call(__MODULE__, {:buzz, {peer, team_token}})
  def clear_buzz(), do: GenServer.call(__MODULE__, :clear)
  def join(), do: GenServer.call(__MODULE__, :join)

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # callbacks

  def init(_args) do
    # TODO: introduce a (serializable!) struct for the game state
    {:ok, State.new()}
  end

  def handle_call(c = {:question, _question}, _from, state) do
    handle_question(c, state)
  end

  def handle_call({:buzz, {peer, team_token}}, _from, state) do
    handle_buzz(peer, {:buzz, team_token}, state)
  end

  def handle_call(:clear, _from, state), do: handle_clear(state)
  def handle_call(:join, {from, _ref}, state), do: handle_join(from, state)
  def handle_call(_, _from, state), do: {:reply, {:error, :bad_call}, state}

  def handle_info(:gating_timeout, state = %{gating: true}) do
    Logger.debug(fn -> "Gate timed out, accepting buzzes" end)

    dispatch(:gating_stopped)
    {:noreply, %{state | gating: false, gating_timer: nil}}
  end

  def handle_info(msg, state) do
    Logger.debug(fn -> "Got unexpected info #{inspect(msg)}" end)
    {:noreply, state}
  end

  # internals

  defp handle_question(call = {:question, q}, %{gating_timer: gating_timer}) do
    cancel_gating_timer(gating_timer)
    {:ok, gating_timer} = :timer.send_after(@gate_time_secs * 1000, :gating_timeout)

    %{
      "question" => question,
      "correct_answer" => correct_answer,
      "incorrect_answers" => incorrect_answers
    } = q

    Logger.info([
      "Updating question\n",
      "  QUESTION: #{inspect(question)}\n",
      "  INCORRECT ANSWERS: #{inspect(incorrect_answers)}\n",
      "  CORRECT ANSWER: #{inspect(correct_answer)}\n"
    ])

    dispatch(call)
    dispatch(:clear)
    dispatch(:gating_started)

    state = State.new_question(q, gating_timer)

    {:reply, :ok, state}
  end

  # BUZZING

  defp handle_buzz(_peer, _c, state = %{gating: true}) do
    # TODO: figure out cooldown'ing of peers who buzz during gating
    # TODO: unify cooldown checker and check_buzz_peer
    {:reply, :rejected, state}
  end

  defp handle_buzz(peer, c, state = %{current_peers: current_peers}) do
    case check_buzz_peer(peer, state) do
      :cont ->
        new_state = %{state | current_peers: MapSet.put(current_peers, peer)}
        do_handle_buzz(c, new_state)

      :halt ->
        Logger.info("Peer rejected for re-buzzing: #{inspect({peer, c})}")
        {:reply, :rejected, state}
    end
  end

  defp check_buzz_peer(peer, %{current_peers: current_peers}) do
    is_local = peer === {127, 0, 0, 1}
    is_fresh = peer not in current_peers
    if is_local or is_fresh, do: :cont, else: :halt
  end

  defp do_handle_buzz(c = {:buzz, team_token}, state = %{current_team: nil}) do
    Logger.info("Accepting: #{inspect(team_token)}")
    dispatch(c)
    {:reply, :accepted, %{state | current_team: team_token}}
  end

  defp do_handle_buzz({:buzz, team_token}, state) do
    Logger.info([
      "Rejecting: #{inspect(team_token)}, ",
      "buzzer is: #{inspect(state.current_team)}"
    ])

    {is_new_dud, state} = State.add_dud(state, team_token)
    if is_new_dud, do: dispatch({:duds, State.share_duds(state)})

    {:reply, :rejected, state}
  end

  # CLEARING

  defp handle_clear(state = %{gating_timer: gating_timer}) do
    Logger.info("Clearing buzzers, winner was: #{inspect(state.current_team)}")

    cancel_gating_timer(gating_timer)
    dispatch(:clear)

    {:reply, :ok, State.new()}
  end

  # JOINING

  defp handle_join(from, state) do
    Logger.info("Join from #{inspect(from)}")

    init_frames = [
      gating: state.gating,
      current_team: state.current_team,
      duds: State.share_duds(state),
      question: state.question
    ]

    {:reply, {:ok, init_frames}, state}
  end

  # MISC INTERNALS

  defp cancel_gating_timer(gating_timer) do
    if gating_timer !== nil do
      Logger.debug(fn -> ["Attempting to cancel: ", inspect(gating_timer)] end)
      {:ok, :cancel} = :timer.cancel(gating_timer)
    end
  end

  defp dispatch(call) do
    Registry.dispatch(TrivPubSub, "trivia", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, call})
    end)
  end

  # STATE
  defmodule State do
    defstruct current_team: nil,
              current_peers: MapSet.new(),
              duds: :queue.new(),
              gating: false,
              gating_timer: nil,
              question: nil

    def new(), do: %State{}

    def new_duds(), do: :queue.new()

    def new_question(question, gating_timer) do
      %State{question: question, gating_timer: gating_timer, gating: true}
    end

    def add_dud(state = %State{current_team: current_team}, current_team), do: {false, state}

    def add_dud(state = %State{duds: duds}, dud) do
      if :queue.member(dud, duds) do
        {false, state}
      else
        duds = :queue.in(dud, duds)
        {true, %State{state | duds: duds}}
      end
    end

    def share_duds(%State{duds: duds}), do: :queue.to_list(duds)
  end
end
