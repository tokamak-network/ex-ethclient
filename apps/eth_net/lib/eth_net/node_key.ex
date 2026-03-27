defmodule EthNet.NodeKey do
  @moduledoc """
  Manages the node's secp256k1 identity keypair.

  Persists the 32-byte raw private key to `{datadir}/nodekey`.
  The node ID is the 64-byte uncompressed public key (without 0x04 prefix).
  """

  use GenServer

  require Logger

  @doc "Starts the NodeKey GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns the 32-byte private key."
  @spec private_key() :: <<_::256>>
  def private_key, do: GenServer.call(__MODULE__, :private_key)

  @doc "Returns the 64-byte uncompressed public key."
  @spec public_key() :: <<_::512>>
  def public_key, do: GenServer.call(__MODULE__, :public_key)

  @doc "Returns the 64-byte node ID (same as public key)."
  @spec node_id() :: <<_::512>>
  def node_id, do: GenServer.call(__MODULE__, :node_id)

  @doc "Returns the enode URL string."
  @spec enode_url(String.t(), non_neg_integer()) :: String.t()
  def enode_url(ip \\ "0.0.0.0", port \\ 30303) do
    id = node_id()
    "enode://#{Base.encode16(id, case: :lower)}@#{ip}:#{port}"
  end

  # Server callbacks

  @impl true
  def init(opts) do
    datadir = Keyword.get(opts, :datadir, "./data")
    File.mkdir_p!(datadir)

    keyfile = Path.join(datadir, "nodekey")

    private_key =
      case File.read(keyfile) do
        {:ok, <<key::binary-size(32)>>} ->
          Logger.info("NodeKey: Loaded existing key from #{keyfile}")
          key

        _ ->
          key = :crypto.strong_rand_bytes(32)
          File.write!(keyfile, key)
          Logger.info("NodeKey: Generated new key, saved to #{keyfile}")
          key
      end

    {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)

    Logger.info(
      "NodeKey: Node ID #{Base.encode16(public_key, case: :lower) |> String.slice(0, 16)}..."
    )

    {:ok, %{private_key: private_key, public_key: public_key}}
  end

  @impl true
  def handle_call(:private_key, _from, state), do: {:reply, state.private_key, state}
  def handle_call(:public_key, _from, state), do: {:reply, state.public_key, state}
  def handle_call(:node_id, _from, state), do: {:reply, state.public_key, state}
end
