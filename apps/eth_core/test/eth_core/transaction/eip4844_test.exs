defmodule EthCore.Transaction.EIP4844Test do
  use ExUnit.Case, async: true

  alias EthCore.RLP
  alias EthCore.Transaction.Signer
  alias EthCore.Types.{Address, Transaction}

  @blob_hash <<1, 0::248>>

  defp make_eip4844_tx(overrides \\ %{}) do
    defaults = %{
      chain_id: 1,
      nonce: 0,
      max_priority_fee_per_gas: 1_500_000_000,
      max_fee_per_gas: 30_000_000_000,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>,
      access_list: [],
      max_fee_per_blob_gas: 1_000_000_000,
      blob_versioned_hashes: [@blob_hash]
    }

    struct!(Transaction.EIP4844, Map.merge(defaults, overrides))
  end

  describe "Transaction.type/1" do
    test "returns 3 for EIP-4844" do
      assert Transaction.type(make_eip4844_tx()) == 3
    end
  end

  describe "RLP encode_for_signing/2" do
    test "encodes EIP-4844 with type prefix 0x03" do
      tx = make_eip4844_tx()
      encoded = RLP.encode_for_signing(tx, nil)
      assert <<3, rlp_data::binary>> = encoded
      decoded = RLP.decode(rlp_data)

      # 11 fields: chain_id, nonce, max_priority_fee, max_fee, gas_limit, to, value, data, access_list, max_fee_per_blob_gas, blob_versioned_hashes
      assert length(decoded) == 11
    end
  end

  describe "RLP encode_signed/1" do
    test "encodes signed EIP-4844 with type prefix 0x03" do
      private_key = EthCrypto.Signature.generate_private_key()
      tx = make_eip4844_tx()
      {:ok, signed} = Signer.sign(tx, private_key)
      encoded = RLP.encode_signed(signed)
      assert <<3, rlp_data::binary>> = encoded
      decoded = RLP.decode(rlp_data)
      # 14 fields: 11 + v, r, s
      assert length(decoded) == 14
    end
  end

  describe "sign/3 + recover_sender/1" do
    test "signs and recovers sender" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      tx = make_eip4844_tx()
      {:ok, signed} = Signer.sign(tx, private_key)

      assert signed.v in [0, 1]
      assert signed.r > 0
      assert signed.s > 0

      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end

    test "with multiple blob hashes" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      tx =
        make_eip4844_tx(%{
          blob_versioned_hashes: [
            <<1, 0::248>>,
            <<1, 1::248>>,
            <<1, 2::248>>
          ]
        })

      {:ok, signed} = Signer.sign(tx, private_key)
      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end

    test "with access list and data" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      tx =
        make_eip4844_tx(%{
          nonce: 42,
          data: <<0xDE, 0xAD, 0xBE, 0xEF>>,
          access_list: [{<<10::160>>, [<<100::256>>]}],
          value: 1_000_000_000
        })

      {:ok, signed} = Signer.sign(tx, private_key)
      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end
  end

  describe "encode/decode round-trip" do
    test "EIP-4844 signed tx round-trips through encode/decode" do
      private_key = EthCrypto.Signature.generate_private_key()
      tx = make_eip4844_tx()
      {:ok, signed} = Signer.sign(tx, private_key)

      encoded = RLP.encode_signed(signed)
      {:ok, decoded} = RLP.decode_signed(encoded)

      assert decoded.tx.chain_id == tx.chain_id
      assert decoded.tx.nonce == tx.nonce
      assert decoded.tx.max_priority_fee_per_gas == tx.max_priority_fee_per_gas
      assert decoded.tx.max_fee_per_gas == tx.max_fee_per_gas
      assert decoded.tx.gas_limit == tx.gas_limit
      assert decoded.tx.to == tx.to
      assert decoded.tx.value == tx.value
      assert decoded.tx.data == tx.data
      assert decoded.tx.max_fee_per_blob_gas == tx.max_fee_per_blob_gas
      assert decoded.tx.blob_versioned_hashes == tx.blob_versioned_hashes
      assert decoded.v == signed.v
      assert decoded.r == signed.r
      assert decoded.s == signed.s
    end
  end

  describe "tx_hash/1" do
    test "computes transaction hash for EIP-4844" do
      private_key = EthCrypto.Signature.generate_private_key()
      tx = make_eip4844_tx()
      {:ok, signed} = Signer.sign(tx, private_key)

      hash = EthCore.Types.SignedTransaction.tx_hash(signed)
      assert byte_size(hash) == 32

      # Deterministic
      assert hash == EthCore.Types.SignedTransaction.tx_hash(signed)
    end
  end
end
