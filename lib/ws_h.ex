defmodule TrivWsHandler do
  require Logger

  # cowboy

  def init(req, opts) do
    {:cowboy_websocket, req, nil, opts}
  end

  # cowboy_websocket

  def websocket_init(state) do
    {:ok, _} = Registry.register(TrivPubSub, "trivia", nil)
    {:ok, {question, current_team}} = TrivServer.join()
    buzz_frame = if current_team == nil, do: [], else: [frame_buzz(current_team)]
    {:reply, [frame_question(question) | buzz_frame], state}
  end

  def websocket_handle({:text, "ping"}, state) do
    payload = %{type: :pong}
    {:reply, {:text, Poison.encode!(payload)}, state}
  end

  def websocket_handle(data, state) do
    Logger.info("Ignoring frame: #{inspect(data)}")
    {:ok, state}
  end

  def websocket_info({:broadcast, {:buzz, team_token}}, state) do
    {:reply, frame_buzz(team_token), state}
  end

  def websocket_info({:broadcast, {:question, q}}, state) do
    {:reply,
     [
       frame_clear(),
       frame_question(q)
     ], state}
  end

  def websocket_info({:broadcast, :clear}, state) do
    {:reply, frame_clear(), state}
  end

  def websocket_info(info, state) do
    Logger.info("Ignoring #{inspect(info)}")
    {:ok, state}
  end

  # internals

  defp frame_question(q) do
    q_payload = %{type: :question, question: q}
    {:text, Poison.encode!(q_payload)}
  end

  defp frame_buzz(team_token) do
    payload = %{type: :buzz, team: team_token}
    {:text, Poison.encode!(payload)}
  end

  defp frame_clear(), do: {:text, Poison.encode!(%{type: :clear})}
end
