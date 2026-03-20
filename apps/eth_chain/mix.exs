defmodule EthChain.MixProject do
  use Mix.Project

  def project do
    [
      app: :eth_chain,
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
      mod: {EthChain.Application, []}
    ]
  end

  defp deps do
    [
      {:eth_core, in_umbrella: true},
      {:eth_crypto, in_umbrella: true},
      {:eth_vm, in_umbrella: true},
      {:eth_storage, in_umbrella: true}
    ]
  end
end
