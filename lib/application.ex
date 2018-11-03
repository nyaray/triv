defmodule TrivApp do
  use Application

  def start(_type, _args) do
    cowboy_opts = [
      :http,
      [{:port, 8080}],
      %{env: %{dispatch: dispatch()}}
    ]

    children = [
      %{id: TrivCowboy, start: {:cowboy, :start_clear, cowboy_opts}, type: :worker},
      %{id: TrivServer, start: {TrivServer, :start_link, []}, type: :worker},
      Registry.child_spec(
        name: TrivPubSub,
        keys: :duplicate
      )
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: Triv.Supervisor
    )
  end

  defp dispatch() do
    :cowboy_router.compile([
      {:_,
       [
         {"/", :cowboy_static, {:priv_file, :triv, "app/resources/public/index.html"}},
         {"/api", TrivRestHandler, []},
         {"/echo", TrivEchoHandler, []},
         {"/ws", TrivWsHandler, %{idle_timeout: 10000}},
         {"/[...]", :cowboy_static, {:priv_dir, :triv, "app/resources/public"}}
       ]}
    ])
  end
end
