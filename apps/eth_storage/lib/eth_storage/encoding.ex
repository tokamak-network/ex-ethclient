defmodule EthStorage.Encoding do
  @moduledoc """
  Encoding helpers for storing and retrieving blocks.

  Uses `:erlang.term_to_binary/1` for serialization to keep the initial
  implementation simple while remaining lossless for all Elixir structs.
  """

  alias EthCore.Types.{Account, BlockHeader}

  @doc "Encodes a block header to binary for storage."
  @spec encode_header(BlockHeader.t()) :: binary()
  def encode_header(%BlockHeader{} = header) do
    :erlang.term_to_binary(header)
  end

  @doc "Decodes a block header from stored binary."
  @spec decode_header(binary()) :: {:ok, BlockHeader.t()} | {:error, atom()}
  def decode_header(bin) when is_binary(bin) do
    case safe_binary_to_term(bin) do
      {:ok, %BlockHeader{} = header} -> {:ok, header}
      {:ok, _} -> {:error, :invalid_header}
      {:error, _} = err -> err
    end
  end

  @doc "Encodes a block body (transactions, ommers, optional withdrawals) to binary."
  @spec encode_body(list(), list(), list() | nil) :: binary()
  def encode_body(transactions, ommers, withdrawals) do
    :erlang.term_to_binary(%{
      transactions: transactions,
      ommers: ommers,
      withdrawals: withdrawals
    })
  end

  @doc "Decodes a block body from stored binary."
  @spec decode_body(binary()) :: {:ok, map()} | {:error, atom()}
  def decode_body(bin) when is_binary(bin) do
    case safe_binary_to_term(bin) do
      {:ok, %{transactions: _, ommers: _, withdrawals: _} = body} ->
        {:ok, body}

      {:ok, _} ->
        {:error, :invalid_body}

      {:error, _} = err ->
        err
    end
  end

  @doc "Encodes an account to binary for storage."
  @spec encode_account(Account.t()) :: binary()
  def encode_account(%Account{} = account) do
    :erlang.term_to_binary(account)
  end

  @doc "Decodes an account from stored binary."
  @spec decode_account(binary()) :: {:ok, Account.t()} | {:error, atom()}
  def decode_account(bin) when is_binary(bin) do
    case safe_binary_to_term(bin) do
      {:ok, %Account{} = account} -> {:ok, account}
      {:ok, _} -> {:error, :invalid_account}
      {:error, _} = err -> err
    end
  end

  @doc "Computes the block hash from a header (keccak256 of RLP-encoded header)."
  @spec block_hash(BlockHeader.t()) :: <<_::256>>
  def block_hash(%BlockHeader{} = header) do
    header
    |> EthCore.RLP.encode_header()
    |> EthCrypto.Hash.keccak256()
  end

  @spec safe_binary_to_term(binary()) :: {:ok, term()} | {:error, atom()}
  defp safe_binary_to_term(bin) do
    {:ok, :erlang.binary_to_term(bin)}
  rescue
    ArgumentError -> {:error, :decode_error}
  end
end
