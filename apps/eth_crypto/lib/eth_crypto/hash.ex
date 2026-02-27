defmodule EthCrypto.Hash do
  @moduledoc """
  Keccak-256 hashing using ex_keccak NIF.
  """

  @doc "Computes the Keccak-256 hash of the given binary."
  @spec keccak256(binary()) :: <<_::256>>
  def keccak256(data) when is_binary(data) do
    ExKeccak.hash_256(data)
  end
end
