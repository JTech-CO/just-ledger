defmodule Realtime.MixProject do
  use Mix.Project

  def project do
    [
      app: :realtime,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Realtime.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Phoenix 는 채널·소켓만 쓴다. Ecto/LiveView/템플릿은 도입하지 않는다 —
  # 원장 조회는 web(Fastify)이 담당하고, 이 서비스는 LISTEN 브리지와 채널만 맡는다.
  defp deps do
    [
      {:phoenix, "~> 1.7.14"},
      {:phoenix_pubsub, "~> 2.1"},
      {:plug_cowboy, "~> 2.7"},
      {:postgrex, "~> 0.19"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
