defmodule EthStorage.AccountRLP do
  @moduledoc """
  RLP encoding/decoding for Ethereum accounts in the state trie.

  Encodes accounts as RLP([nonce, balance, storage_root, code_hash]) per the
  Yellow Paper specification. Integer fields use minimal big-endian encoding.
  """

  alias EthCore.Types.Account

  @doc """
  Encodes an account to RLP for state trie storage.

  Fields are encoded as:
  - nonce: big-endian binary (empty binary for 0)
  - balance: big-endian binary (empty binary for 0)
  - storage_root: 32-byte hash as-is
  - code_hash: 32-byte hash as-is
  """
  @spec encode(Account.t()) :: binary()
  def encode(%Account{} = account) do
    [
      encode_integer(account.nonce),
      encode_integer(account.balance),
      account.storage_root,
      account.code_hash
    ]
    |> ExRLP.encode()
  end

  @doc "Decodes an RLP-encoded account."
  @spec decode(binary()) :: {:ok, Account.t()} | {:error, atom()}
  def decode(bin) when is_binary(bin) do
    case ExRLP.decode(bin) do
      [nonce_bin, balance_bin, storage_root, code_hash]
      when byte_size(storage_root) == 32 and byte_size(code_hash) == 32 ->
        {:ok,
         %Account{
           nonce: decode_integer(nonce_bin),
           balance: decode_integer(balance_bin),
           storage_root: storage_root,
           code_hash: code_hash
         }}

      _ ->
        {:error, :invalid_account_rlp}
    end
  rescue
    _ -> {:error, :decode_error}
  end

  @spec encode_integer(non_neg_integer()) :: binary()
  defp encode_integer(0), do: <<>>

  defp encode_integer(n) when is_integer(n) and n > 0 do
    :binary.encode_unsigned(n)
  end

  @spec decode_integer(binary()) :: non_neg_integer()
  defp decode_integer(<<>>), do: 0
  defp decode_integer(bin), do: :binary.decode_unsigned(bin)
end
