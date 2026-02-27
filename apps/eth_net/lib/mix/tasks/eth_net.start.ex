defmodule Mix.Tasks.EthNet.Start do
  @moduledoc """
  Starts the Ethereum P2P networking node.

  ## Usage

      mix eth_net.start [--port PORT] [--datadir DIR]

  ## Options

  - `--port` - UDP/TCP port (default: 30303)
  - `--datadir` - Data directory for node key (default: ./data)
  """

  use Mix.Task

  @shortdoc "Starts the Ethereum P2P node"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [port: :integer, datadir: :string],
        aliases: [p: :port, d: :datadir]
      )

    port = Keyword.get(opts, :port, 30303)
    datadir = Keyword.get(opts, :datadir, "./data")

    # Set application env before starting
    Application.put_env(:eth_net, :port, port)
    Application.put_env(:eth_net, :datadir, datadir)

    # Start all dependencies
    Mix.Task.run("app.start")

    IO.puts("\n=== ex_ethclient P2P Node ===")
    IO.puts("Port: #{port}")
    IO.puts("Data dir: #{datadir}")

    enode = EthNet.NodeKey.enode_url("0.0.0.0", port)
    IO.puts("Node ID: #{enode}")
    IO.puts("\nListening for peers... (Ctrl+C to stop)\n")

    # Keep the process alive
    unless iex_running?() do
      Process.sleep(:infinity)
    end
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end
end
