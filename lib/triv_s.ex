defmodule TrivServer do
  @gate_time_secs 5

  require Logger

  use GenServer

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
    {:ok, %{
      current_team: nil,
      current_peers: MapSet.new(),
      duds: new_duds(),
      gating: false,
      gating_timer: nil,
      question: nil
    }}
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

  # internals

  defp handle_question(call = {:question, q}, %{gating_timer: gating_timer}) do
    cancel_gating_timer(gating_timer)
    gating_timer = :timer.send_after(@gate_time_secs*1000, :gate_timer)

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

    state = %{
      current_team: :nil,
      current_peers: MapSet.new(),
      duds: new_duds(),
      gating: true,
      gating_timer: gating_timer,
      question: q
    }
    {:reply, :ok, state}
  end

  # BUZZING

  defp handle_buzz(_peer, _c, state = %{gating: true}) do
    {:reply, :rejected, state}
  end

  defp handle_buzz(peer, c, state = %{current_peers: current_peers}) do
    case check_buzz_peer(peer, state) do
      :cont ->
        new_state = %{state | current_peers: MapSet.put(current_peers, peer)}
        do_handle_buzz(c, new_state)
      :halt ->
        Logger.info("Peer rejected for re-buzzing: #{inspect {peer, c}}")
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

    state =
      if :queue.member(team_token, state.duds) or team_token == state.current_team do
        state
      else
        duds = add_dud(state.duds, team_token)
        dispatch({:duds, duds |> share_duds()})
        %{state | duds: duds}
      end

    {:reply, :rejected, state}
  end

  # CLEARING

  defp handle_clear(state = %{gating_timer: gating_timer}) do
    Logger.info("Clearing buzzers, winner was: #{inspect(state.current_team)}")

    cancel_gating_timer(gating_timer)
    dispatch(:clear)

    state = %{state |
      current_team: nil,
      current_peers: MapSet.new(),
      duds: new_duds(),
      gating: false,
      gating_timer: nil
    }
    {:reply, :ok, state}
  end

  # JOINING

  defp handle_join(from, state) do
    Logger.info("Join from #{inspect(from)}")
    duds = share_duds(state.duds)
    {:reply, {:ok, {state.question, state.current_team, duds}}, state}
  end

  # MISC INTERNALS

  defp cancel_gating_timer(gating_timer) do
    if gating_timer !== nil do
      {:ok, :cancel} = :timer.cancel(gating_timer)
    end
  end

  defp new_duds(), do: :queue.new()

  defp add_dud(duds, dud), do: :queue.in(dud, duds)

  defp share_duds(duds), do: :queue.to_list(duds)

  defp dispatch(call) do
    Registry.dispatch(TrivPubSub, "trivia", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, call})
    end)
  end
end
