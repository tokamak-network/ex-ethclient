defmodule EthCore.Transaction.RLPHelpers do
  @spec encode_integer(non_neg_integer()) :: binary()
  def encode_integer(0), do: ""
  def encode_integer(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)

  @spec decode_integer(binary()) :: non_neg_integer()
  def decode_integer(""), do: 0
  def decode_integer(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)

  @spec encode_address(binary() | nil) :: binary()
  def encode_address(nil), do: ""
  def encode_address(<<addr::binary-size(20)>>), do: addr

  @spec decode_address(binary()) :: binary() | nil
  def decode_address(""), do: nil
  def decode_address(<<addr::binary-size(20)>>), do: addr

  @spec encode_access_list([{binary(), [binary()]}]) :: list()
  def encode_access_list(access_list) do
    Enum.map(access_list, fn {address, storage_keys} ->
      [address, storage_keys]
    end)
  end

  @spec decode_access_list(list()) :: [{binary(), [binary()]}]
  def decode_access_list(rlp_list) do
    Enum.map(rlp_list, fn [address, storage_keys] ->
      {address, storage_keys}
    end)
  end
end
