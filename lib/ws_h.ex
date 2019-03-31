defmodule TrivWsHandler do
  require Logger

  # cowboy

  def init(req, opts) do
    # Logger.debug(fn -> "Initialising websocket ..." end)
    {:cowboy_websocket, req, nil, opts}
  end

  # cowboy_websocket

  def websocket_init(state) do
    # Logger.debug(fn -> "Registering for trivia events..." end)
    {:ok, join_state} = TrivServer.join()
    # Logger.debug(fn -> "Sending first frames" end)
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

  def websocket_info({:broadcast, :gating_started}, state) do
    frame_gating_started()
    |> reply(state)
  end

  def websocket_info({:broadcast, :gating_stopped}, state) do
    frame_gating_stopped()
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

  defp first_frames(frames, acc \\ [])

  defp first_frames([], acc), do: Enum.reverse(acc)

  defp first_frames([f | fs], acc) do
    frame =
      case f do
        {_, nil} -> :skip
        {_, []} -> :skip
        {:question, question} -> frame_question(question)
        {:gating, true} -> frame_gating_started()
        {:gating, false} -> frame_gating_stopped()
        {:current_team, current_team} -> frame_buzz(current_team)
        {:duds, duds} -> frame_duds(duds)
      end

    case frame do
      :skip -> first_frames(fs, acc)
      f -> first_frames(fs, [f | acc])
    end
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

  defp frame_gating_started(), do: {:text, Poison.encode!(%{type: :gating_started})}
  defp frame_gating_stopped(), do: {:text, Poison.encode!(%{type: :gating_stopped})}
end
