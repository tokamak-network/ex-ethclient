defmodule EthCrypto.Key do
  alias EthCrypto.Hash

  @spec generate_private_key() :: <<_::256>>
  def generate_private_key do
    :crypto.strong_rand_bytes(32)
  end

  @spec derive_public_key(<<_::256>>) :: {:ok, <<_::520>>} | {:error, String.t()}
  def derive_public_key(<<privkey::binary-size(32)>>) do
    case ExSecp256k1.create_public_key(privkey) do
      {:ok, pubkey} -> {:ok, pubkey}
      {:error, reason} -> {:error, "Failed to derive public key: #{inspect(reason)}"}
    end
  end

  @spec public_key_to_address(<<_::520>>) :: <<_::160>>
  def public_key_to_address(<<0x04, pubkey_body::binary-size(64)>>) do
    <<_first_12::binary-size(12), address::binary-size(20)>> = Hash.keccak256(pubkey_body)
    address
  end

  @spec privkey_to_address(<<_::256>>) :: <<_::160>>
  def privkey_to_address(<<privkey::binary-size(32)>>) do
    {:ok, pubkey} = derive_public_key(privkey)
    public_key_to_address(pubkey)
  end
end
