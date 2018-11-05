defmodule TrivServer do
  require Logger

  use GenServer

  # api

  def update_question(q), do: GenServer.call(__MODULE__, {:question, q})
  def buzz(team_token), do: GenServer.call(__MODULE__, {:buzz, team_token})
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
      duds: new_duds(),
      question: nil
    }}
  end

  def handle_call(c = {:question, _question}, _from, state) do
    handle_question(c, state)
  end

  def handle_call(c = {:buzz, _team_token}, _from, state), do: handle_buzz(c, state)
  def handle_call(:clear, _from, state), do: handle_clear(state)
  def handle_call(:join, {from, _ref}, state), do: handle_join(from, state)
  def handle_call(_, _from, state), do: {:reply, {:error, :bad_call}, state}

  # internals

  defp handle_question(call = {:question, q}, _state) do
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

    {:reply, :ok, %{current_team: :nil, duds: new_duds(), question: q}}
  end

  defp handle_buzz(c = {:buzz, team_token}, state = %{current_team: nil}) do
    Logger.info("Accepting: #{inspect(team_token)}")
    dispatch(c)
    {:reply, :accepted, %{state | current_team: team_token}}
  end

  defp handle_buzz({:buzz, team_token}, state) do
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

  defp handle_clear(state) do
    Logger.info("Clearing buzzer, was: #{inspect(state.current_team)}")
    dispatch(:clear)
    {:reply, :ok, %{state | current_team: nil, duds: new_duds()}}
  end

  defp handle_join(from, state) do
    Logger.info("Join from #{inspect(from)}")
    duds = share_duds(state.duds)
    {:reply, {:ok, {state.question, state.current_team, duds}}, state}
  end

  defp new_duds() do
    :queue.new()
  end

  defp add_dud(duds, dud) do
    :queue.in(dud, duds)
  end

  defp share_duds(duds) do
    :queue.to_list(duds)
  end

  defp dispatch(call) do
    Registry.dispatch(TrivPubSub, "trivia", fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, call})
    end)
  end
end
