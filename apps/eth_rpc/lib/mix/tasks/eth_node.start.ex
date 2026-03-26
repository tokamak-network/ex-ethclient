defmodule Mix.Tasks.EthNode.Start do
  @moduledoc """
  Starts the full Ethereum execution client node.

  This task configures and launches all components: P2P networking,
  storage, chain validation, mempool, and JSON-RPC server.

  ## Usage

      mix eth_node.start [OPTIONS]

  ## Options

  - `--network` - Network name: mainnet, sepolia, holesky (default: mainnet)
  - `--port` - P2P listen port (default: 30303)
  - `--rpc-port` - JSON-RPC HTTP port (default: 8545)
  - `--datadir` - Data directory for node key and storage (default: ./data)
  """

  use Mix.Task

  @shortdoc "Starts the full Ethereum execution client node"

  @impl Mix.Task
  @spec run([String.t()]) :: no_return()
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          network: :string,
          port: :integer,
          rpc_port: :integer,
          datadir: :string
        ],
        aliases: [n: :network, p: :port, r: :rpc_port, d: :datadir]
      )

    network = Keyword.get(opts, :network, "mainnet")
    port = Keyword.get(opts, :port, 30303)
    rpc_port = Keyword.get(opts, :rpc_port, 8545)
    datadir = Keyword.get(opts, :datadir, "./data")

    # Configure eth_net
    Application.put_env(:eth_net, :port, port)
    Application.put_env(:eth_net, :datadir, datadir)
    Application.put_env(:eth_net, :chain, network)

    # Configure eth_rpc
    Application.put_env(:eth_rpc, :port, rpc_port)

    # Start all dependencies and the umbrella application
    Mix.Task.run("app.start")

    IO.puts("\n=== ex_ethclient Node ===")
    IO.puts("Network:  #{network}")
    IO.puts("P2P port: #{port}")
    IO.puts("RPC port: #{rpc_port}")
    IO.puts("Data dir: #{datadir}")
    IO.puts("Health:   http://localhost:#{rpc_port}/health")
    IO.puts("\nNode running... (Ctrl+C to stop)\n")

    # Keep the process alive unless running inside IEx
    unless iex_running?() do
      Process.sleep(:infinity)
    end
  end

  @spec iex_running?() :: boolean()
  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end
end
