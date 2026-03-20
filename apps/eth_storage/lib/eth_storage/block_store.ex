defmodule EthStorage.BlockStore do
  @moduledoc "High-level API for storing and retrieving complete blocks."

  alias EthCore.Types.{Block, BlockHeader}
  alias EthStorage.{Encoding, Store}

  @doc """
  Stores a complete block (header + body + canonical hash).

  Returns the computed block hash on success.
  """
  @spec store_block(Block.t(), GenServer.server()) ::
          {:ok, <<_::256>>} | {:error, term()}
  def store_block(%Block{} = block, store \\ Store) do
    block_hash = Encoding.block_hash(block.header)
    encoded_header = Encoding.encode_header(block.header)

    encoded_body =
      Encoding.encode_body(
        block.transactions,
        block.ommers,
        block.withdrawals
      )

    with :ok <- Store.put_block_header(store, block_hash, encoded_header),
         :ok <- Store.put_block_body(store, block_hash, encoded_body),
         :ok <- Store.set_canonical_hash(store, block.header.number, block_hash) do
      {:ok, block_hash}
    end
  end

  @doc "Retrieves a block header by hash."
  @spec get_header(<<_::256>>, GenServer.server()) ::
          {:ok, BlockHeader.t() | nil} | {:error, term()}
  def get_header(hash, store \\ Store) do
    with {:ok, encoded} <- Store.get_block_header(store, hash) do
      if is_nil(encoded) do
        {:ok, nil}
      else
        Encoding.decode_header(encoded)
      end
    end
  end

  @doc "Retrieves a full block by number."
  @spec get_block_by_number(non_neg_integer(), GenServer.server()) ::
          {:ok, Block.t() | nil} | {:error, term()}
  def get_block_by_number(number, store \\ Store) do
    with {:ok, hash} <- Store.get_canonical_hash(store, number) do
      if is_nil(hash) do
        {:ok, nil}
      else
        get_block_by_hash(hash, store)
      end
    end
  end

  @doc "Retrieves a full block by hash."
  @spec get_block_by_hash(hash :: <<_::256>>, GenServer.server()) ::
          {:ok, Block.t() | nil} | {:error, term()}
  def get_block_by_hash(hash, store \\ Store) do
    with {:ok, encoded_header} <- Store.get_block_header(store, hash),
         {:ok, encoded_body} <- Store.get_block_body(store, hash) do
      if is_nil(encoded_header) do
        {:ok, nil}
      else
        with {:ok, header} <- Encoding.decode_header(encoded_header),
             {:ok, body} <- decode_body_or_empty(encoded_body) do
          {:ok,
           %Block{
             header: header,
             transactions: body.transactions,
             ommers: body.ommers,
             withdrawals: body.withdrawals
           }}
        end
      end
    end
  end

  @doc "Returns the latest block number."
  @spec latest_block_number(GenServer.server()) ::
          {:ok, non_neg_integer() | nil} | {:error, term()}
  def latest_block_number(store \\ Store) do
    Store.get_latest_block_number(store)
  end

  @spec decode_body_or_empty(binary() | nil) :: {:ok, map()} | {:error, term()}
  defp decode_body_or_empty(nil) do
    {:ok, %{transactions: [], ommers: [], withdrawals: nil}}
  end

  defp decode_body_or_empty(encoded) do
    Encoding.decode_body(encoded)
  end
end
