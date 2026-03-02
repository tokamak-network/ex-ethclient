defmodule EthCrypto.Hash do
  @spec keccak256(binary()) :: <<_::256>>
  def keccak256(data) when is_binary(data) do
    ExKeccak.hash_256(data)
  end
end
