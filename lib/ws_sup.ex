defmodule TrivWsSup do
  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    procs = []
    Supervisor.init(procs, strategy: :one_for_one)
  end
end
