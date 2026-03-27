defmodule EthNet.MixProject do
  use Mix.Project

  def project do
    [
      app: :eth_net,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {EthNet.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:eth_core, in_umbrella: true},
      {:eth_crypto, in_umbrella: true},
      {:eth_storage, in_umbrella: true},
      {:snappyer, "~> 1.2"},
      {:telemetry, "~> 1.0"}
    ]
  end
end
