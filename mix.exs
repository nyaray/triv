defmodule Triv.MixProject do
  use Mix.Project

  def project do
    [
      app: :triv,
      version: "0.1.0",
      elixir: "~> 1.7",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {TrivApp, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:cowboy, "~> 2.5"},
      {:poison, "~> 4.0"}
    ]
  end
end
