defmodule ExEthclient.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      name: "ex_ethclient",
      source_url: "https://github.com/tokamak-network/ex_ethclient",
      docs: docs()
    ]
  end

  defp releases do
    [
      ex_ethclient: [
        applications: [
          eth_core: :permanent,
          eth_crypto: :permanent,
          eth_net: :permanent,
          eth_storage: :permanent,
          eth_vm: :permanent,
          eth_chain: :permanent,
          eth_rpc: :permanent,
          eth_dashboard: :permanent
        ],
        cookie: :ex_ethclient_cookie
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      groups_for_modules: [
        "Core Types": ~r/EthCore\..*/,
        "Cryptography": ~r/EthCrypto\..*/,
        "Networking": ~r/EthNet\..*/,
        "Storage": ~r/EthStorage\..*/,
        "EVM": ~r/EthVm\..*/,
        "Chain": ~r/EthChain\..*/,
        "JSON-RPC": ~r/EthRpc\..*/
      ]
    ]
  end

  # Dependencies listed here are available only for this
  # project and cannot be accessed from applications inside
  # the apps folder.
  #
  # Run "mix help deps" for examples and options.
  defp deps do
    [
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
