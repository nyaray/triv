defmodule TrivApp do
  use Application

  @static_root Application.get_env(:triv, :static_root)

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
         {"/api", TrivRestHandler, []},
         {"/echo", TrivEchoHandler, []},
         {"/ws", TrivWsHandler, %{idle_timeout: 10000}},
         {"/", :cowboy_static, {:priv_file, :triv, @static_root <> "index.html"}},
         {"/[...]", :cowboy_static, {:priv_dir, :triv, @static_root}}
       ]}
    ])
  end
end
