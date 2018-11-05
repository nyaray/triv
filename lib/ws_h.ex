defmodule TrivWsHandler do
  require Logger

  # cowboy

  def init(req, opts) do
    {:cowboy_websocket, req, nil, opts}
  end

  # cowboy_websocket

  def websocket_init(state) do
    {:ok, _} = Registry.register(TrivPubSub, "trivia", nil)
    {:ok, join_state} = TrivServer.join()
    {:reply, first_frames(join_state), state}
  end

  def websocket_handle({:text, "ping"}, state) do
    {:reply, {:text, Poison.encode!(%{type: :pong})}, state}
  end

  def websocket_handle(data, state) do
    Logger.info("Ignoring frame: #{inspect(data)}")
    {:ok, state}
  end

  def websocket_info({:broadcast, {:buzz, team_token}}, state) do
    team_token
    |> frame_buzz()
    |> reply(state)
  end

  def websocket_info({:broadcast, {:duds, duds}}, state) do
    frame_duds(duds)
    |> reply(state)
  end

  def websocket_info({:broadcast, {:question, q}}, state) do
    q
    |> frame_question()
    |> reply(state)
  end

  def websocket_info({:broadcast, :clear}, state) do
    frame_clear()
    |> reply(state)
  end

  def websocket_info(info, state) do
    Logger.info("Ignoring #{inspect(info)}")
    {:ok, state}
  end

  # internals

  defp reply(response, state) do
    {:reply, response, state}
  end

  defp first_frames({question, current_team, duds}) do
    question_frame = if question == nil, do: [], else: [frame_question(question)]
    buzz_frame = if current_team == nil, do: [], else: [frame_buzz(current_team)]
    duds_frame = if duds == [], do: [], else: [frame_duds(duds)]
    question_frame ++ buzz_frame ++ duds_frame
  end

  defp frame_question(q) do
    {:text, Poison.encode!(%{type: :question, question: q})}
  end

  defp frame_buzz(team_token) do
    {:text, Poison.encode!(%{type: :buzz, team: team_token})}
  end

  defp frame_duds(duds) do
    {:text, Poison.encode!(%{type: :duds, duds: duds})}
  end

  defp frame_clear(), do: {:text, Poison.encode!(%{type: :clear})}
end
