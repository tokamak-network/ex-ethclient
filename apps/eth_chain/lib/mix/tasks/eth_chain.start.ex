defmodule Mix.Tasks.EthChain.Start do
  @moduledoc """
  Starts the Ethereum execution client node.

  ## Usage

      mix eth_chain.start [--network NETWORK] [--port PORT] [--rpc-port RPC_PORT]
                          [--datadir DIR] [--rpc BOOL] [--bootnodes ENODES]
                          [--dashboard] [--dashboard-port PORT]
                          [--beacon-api URL]

  ## Options

  - `--network` - Network name: "mainnet" or "sepolia" (default: mainnet)
  - `--port` - P2P port (default: 30303)
  - `--rpc-port` - JSON-RPC HTTP port (default: 8545)
  - `--datadir` - Data directory (default: ./data)
  - `--rpc` - Enable JSON-RPC server (default: true)
  - `--bootnodes` - Comma-separated enode URLs
  - `--dashboard` - Enable web dashboard (default: false)
  - `--dashboard-port` - Dashboard HTTP port (default: 4000)
  - `--beacon-api` - Public Beacon API endpoint URL (enables BeaconFetcher)
  """

  use Mix.Task

  @shortdoc "Start the execution client"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          network: :string,
          port: :integer,
          rpc_port: :integer,
          engine_port: :integer,
          datadir: :string,
          rpc: :boolean,
          bootnodes: :string,
          dashboard: :boolean,
          dashboard_port: :integer,
          beacon_api: :string
        ],
        aliases: [p: :port, r: :rpc_port, d: :datadir, n: :network]
      )

    network =
      case Keyword.get(opts, :network, "mainnet") do
        "sepolia" -> :sepolia
        _ -> :mainnet
      end

    opts = Keyword.put(opts, :network, network)

    config = EthChain.Config.from_env(opts)

    # Generate JWT secret file before app.start (plain file operations)
    jwt_path = Path.join(config.datadir, "jwt.hex")
    File.mkdir_p!(config.datadir)

    unless File.exists?(jwt_path) do
      secret = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      File.write!(jwt_path, secret)
    end

    # Read the secret and configure for Engine API auth
    jwt_secret = jwt_path |> File.read!() |> String.trim()

    Application.put_env(:eth_net, :port, config.p2p_port)
    Application.put_env(:eth_net, :network, config.network)
    Application.put_env(:eth_rpc, :port, config.rpc_port)
    Application.put_env(:eth_rpc, :engine_port, config.engine_port)
    Application.put_env(:eth_rpc, :jwt_secret, Base.decode16!(jwt_secret, case: :mixed))
    # Enable RPC servers (disabled by default in config.exs)
    Application.put_env(:eth_rpc, :start_server, true)

    # Enable dashboard if --dashboard flag is passed
    if Keyword.get(opts, :dashboard, false) do
      dashboard_port = Keyword.get(opts, :dashboard_port, 4000)
      Application.put_env(:eth_dashboard, :start_server, true)
      Application.put_env(:eth_dashboard, :port, dashboard_port)
    end

    # Enable BeaconFetcher if --beacon-api flag is passed
    if beacon_url = Keyword.get(opts, :beacon_api) do
      Application.put_env(:eth_chain, :beacon_api_endpoint, beacon_url)
      Application.put_env(:eth_chain, :network, network)
    end

    Mix.Task.run("app.start")

    {:ok, _pid} = EthChain.NodeSupervisor.start_link(config)

    head = fetch_head()

    dashboard_info =
      if Keyword.get(opts, :dashboard, false) do
        " Dashboard: http://localhost:#{Application.get_env(:eth_dashboard, :port, 4000)}\n"
      else
        ""
      end

    beacon_info =
      if beacon_url = Keyword.get(opts, :beacon_api) do
        " Beacon:    #{beacon_url}\n"
      else
        ""
      end

    Mix.shell().info("""

    ====================================
     ex_ethclient v0.1.0
    ====================================
     Network:   #{config.network}
     Chain ID:  #{config.chain_id}
     Data dir:  #{config.datadir}
     P2P port:  #{config.p2p_port}
     RPC port:  #{config.rpc_port}
     Engine:    #{config.engine_port}
     JWT:       #{jwt_path}
     Head:      ##{inspect(head)}
    #{dashboard_info}#{beacon_info}====================================
    """)

    unless iex_running?() do
      Process.sleep(:infinity)
    end
  end

  @spec fetch_head() :: map() | nil
  defp fetch_head do
    case EthChain.Node.chain_head(EthStorage.Store) do
      {:ok, head} -> head
      _ -> nil
    end
  end

  @spec iex_running?() :: boolean()
  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end
end
