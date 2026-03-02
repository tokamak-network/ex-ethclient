defmodule EthCrypto.MixProject do
  use Mix.Project

  def project do
    [
      app: :eth_crypto,
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
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:ex_keccak, "~> 0.7.8"},
      {:ex_secp256k1, "~> 0.8.0"}
    ]
  end
end
