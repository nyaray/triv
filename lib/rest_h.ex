defmodule TrivRestHandler do
  require Logger

  def init(req, state) do
    {body, req} = parse_body(req)
    # Logger.info "REST decoded #{inspect(body)}"
    handle_body(body)
    req = :cowboy_req.reply(200, %{"content-type" => "text/plain"}, "pong", req)
    {:ok, req, state}
  end

  # internals

  defp parse_body(req) do
    {:ok, req_body, req} = :cowboy_req.read_body(req)
    # Logger.info "REST read #{inspect(req_body)}"
    {Poison.decode!(req_body), req}
  end

  defp handle_body(body) do
    # TODO: break out clear and question into an admin handler
    case body do
      "clear" ->
        TrivServer.clear_buzz()

      %{"team_token" => team_token} ->
        TrivServer.buzz(team_token)

      q = %{"question" => _} ->
        TrivServer.update_question(q)

      _ ->
        :ignore
    end
  end
end
