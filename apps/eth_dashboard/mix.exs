defmodule EthDashboard.MixProject do
  use Mix.Project

  def project do
    [
      app: :eth_dashboard,
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

  def application do
    [
      extra_applications: [:logger],
      mod: {EthDashboard.Application, []}
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.6"},
      {:plug, "~> 1.16"},
      {:jason, "~> 1.4"},
      {:eth_net, in_umbrella: true},
      {:eth_storage, in_umbrella: true},
      {:eth_chain, in_umbrella: true}
    ]
  end
end
