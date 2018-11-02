defmodule TrivEchoHandler do
  require Logger

  def init(req, state) do
    {:ok, req_body, req} = :cowboy_req.read_body(req)
    Logger.info("REST echoed: #{req_body}")
    req = :cowboy_req.reply(200, %{"content-type" => "text/plain"}, req_body, req)
    {:ok, req, state}
  end
end
