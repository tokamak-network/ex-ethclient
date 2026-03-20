defmodule Mix.Tasks.EthChain.Start do
  @moduledoc """
  Starts the Ethereum execution client node.

  ## Usage

      mix eth_chain.start [--port PORT] [--rpc-port RPC_PORT] [--datadir DIR]

  ## Options

  - `--port` - P2P port (default: 30303)
  - `--rpc-port` - JSON-RPC HTTP port (default: 8545)
  - `--datadir` - Data directory (default: ./data)
  """

  use Mix.Task

  @shortdoc "Start the execution client"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [port: :integer, rpc_port: :integer, datadir: :string],
        aliases: [p: :port, r: :rpc_port, d: :datadir]
      )

    port = Keyword.get(opts, :port, 30303)
    rpc_port = Keyword.get(opts, :rpc_port, 8545)
    datadir = Keyword.get(opts, :datadir, "./data")

    Application.put_env(:eth_net, :port, port)
    Application.put_env(:eth_rpc, :port, rpc_port)

    Mix.Task.run("app.start")

    store = EthStorage.Store

    case EthChain.Node.initialize(store) do
      {:ok, head} ->
        IO.puts("\n=== ex_ethclient Execution Client ===")
        IO.puts("P2P port: #{port}")
        IO.puts("RPC port: #{rpc_port}")
        IO.puts("Data dir: #{datadir}")
        IO.puts("Head block: ##{head.head_number}")
        IO.puts("Head hash: 0x#{Base.encode16(head.head_hash, case: :lower)}")
        IO.puts("\nNode running... (Ctrl+C to stop)\n")

      {:error, reason} ->
        IO.puts("\nFailed to initialize node: #{inspect(reason)}")
    end

    unless iex_running?() do
      Process.sleep(:infinity)
    end
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end
end
