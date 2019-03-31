defmodule TrivServer do
  @gate_time_secs 5

  require Logger
  use GenServer

  alias TrivServer.State

  # STATE
  defmodule State do
    defstruct current_team: nil,
              current_peers: MapSet.new(),
              duds: :queue.new(),
              gating: false,
              gating_timer: nil,
              gating_timer_ref: nil,
              question: nil

    def new(), do: %State{}

    def new_duds(), do: :queue.new()

    def new_round(question, gating_timer, gating_timer_ref) do
      %State{
        question: question,
        gating_timer: gating_timer,
        gating: true,
        gating_timer_ref: gating_timer_ref
      }
    end

    def stop_gating(state = %State{}),
      do: %State{
        state
        | gating: false,
          gating_timer: nil,
          gating_timer_ref: nil
      }

    def current_team(state = %State{}, team_token) do
      %State{state | current_team: team_token}
    end

    def add_dud(state = %State{current_team: current_team}, current_team),
      do: {false, state}

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

  # api

  def update_question(q), do: GenServer.call(__MODULE__, {:question, q})

  def buzz(peer, team_token),
    do: GenServer.call(__MODULE__, {:buzz, {peer, team_token}})

  def clear_buzz(), do: GenServer.call(__MODULE__, :clear)
  def join(), do: GenServer.call(__MODULE__, :join)

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # callbacks

  def init(_args) do
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

  def handle_info(:gating_timeout, state = %State{gating: true}) do
    Logger.debug(fn -> "Gate timed out, accepting buzzes" end)
    dispatch(:gating_stopped)
    {:noreply, State.stop_gating(state)}
  end

  def handle_info(msg, state) do
    Logger.debug(fn -> "Got unexpected info #{inspect(msg)}" end)
    {:noreply, state}
  end

  # internals

  defp handle_question(call = {:question, q}, state) do
    cancel_gating_timer(state)

    timeout_ref = make_ref()

    {:ok, gating_timer} =
      :timer.send_after(@gate_time_secs * 1000, {:gating_timeout, timeout_ref})

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

    state = State.new_round(q, gating_timer, timeout_ref)

    {:reply, :ok, state}
  end

  # BUZZING

  defp handle_buzz(_peer, _c, state = %State{gating: true}) do
    # TODO: figure out cooldown'ing of peers who buzz during gating
    # TODO: unify cooldown checker and check_buzz_peer
    {:reply, :rejected, state}
  end

  defp handle_buzz(peer, c, state = %State{current_peers: current_peers}) do
    case check_buzz_peer(peer, state) do
      :cont ->
        new_state = %State{
          state
          | current_peers: MapSet.put(current_peers, peer)
        }

        do_handle_buzz(c, new_state)

      :halt ->
        Logger.info("Peer rejected for re-buzzing: #{inspect({peer, c})}")
        {:reply, :rejected, state}
    end
  end

  defp check_buzz_peer(peer, %State{current_peers: current_peers}) do
    is_local = peer === {127, 0, 0, 1}
    is_fresh = peer not in current_peers
    if is_local or is_fresh, do: :cont, else: :halt
  end

  defp do_handle_buzz(
         c = {:buzz, team_token},
         state = %State{current_team: nil}
       ) do
    Logger.info("Accepting: #{inspect(team_token)}")
    dispatch(c)
    {:reply, :accepted, State.current_team(state, team_token)}
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

  defp handle_clear(state = %State{gating_timer: gating_timer}) do
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

  defp cancel_gating_timer(%State{gating_timer: nil}), do: :ok

  defp cancel_gating_timer(%State{gating_timer: gating_timer}) do
    result = :timer.cancel(gating_timer)

    Logger.debug(fn ->
      [
        "Attempted to cancel timer ",
        inspect(gating_timer),
        " got: ",
        inspect(result)
      ]
    end)

    result
  end

  defp dispatch(call) do
    Registry.dispatch(TrivPubSub, "trivia", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, call})
    end)
  end
end
