defmodule EthCore.Transaction.EIP7702Test do
  use ExUnit.Case, async: true

  alias EthCore.RLP
  alias EthCore.Transaction.Signer
  alias EthCore.Types.{Address, Authorization, Transaction}

  defp make_authorization do
    %Authorization{
      chain_id: 1,
      address: <<42::160>>,
      nonce: 0,
      y_parity: 0,
      r: 12_345_678_901_234_567_890,
      s: 98_765_432_109_876_543_210
    }
  end

  defp make_eip7702_tx(overrides \\ %{}) do
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
      authorization_list: [make_authorization()]
    }

    struct!(Transaction.EIP7702, Map.merge(defaults, overrides))
  end

  describe "Transaction.type/1" do
    test "returns 4 for EIP-7702" do
      assert Transaction.type(make_eip7702_tx()) == 4
    end
  end

  describe "RLP encode_for_signing/2" do
    test "encodes EIP-7702 with type prefix 0x04" do
      tx = make_eip7702_tx()
      encoded = RLP.encode_for_signing(tx, nil)
      assert <<4, rlp_data::binary>> = encoded
      decoded = RLP.decode(rlp_data)

      # 10 fields: chain_id, nonce, max_priority_fee, max_fee, gas_limit, to, value, data, access_list, authorization_list
      assert length(decoded) == 10
    end
  end

  describe "RLP encode_signed/1" do
    test "encodes signed EIP-7702 with type prefix 0x04" do
      private_key = EthCrypto.Signature.generate_private_key()
      tx = make_eip7702_tx()
      {:ok, signed} = Signer.sign(tx, private_key)
      encoded = RLP.encode_signed(signed)
      assert <<4, rlp_data::binary>> = encoded
      decoded = RLP.decode(rlp_data)
      # 13 fields: 10 + v, r, s
      assert length(decoded) == 13
    end
  end

  describe "sign/3 + recover_sender/1" do
    test "signs and recovers sender" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      tx = make_eip7702_tx()
      {:ok, signed} = Signer.sign(tx, private_key)

      assert signed.v in [0, 1]
      assert signed.r > 0
      assert signed.s > 0

      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end

    test "with multiple authorizations" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      auth2 = %Authorization{
        chain_id: 1,
        address: <<99::160>>,
        nonce: 1,
        y_parity: 1,
        r: 11_111_111_111_111_111_111,
        s: 22_222_222_222_222_222_222
      }

      tx = make_eip7702_tx(%{authorization_list: [make_authorization(), auth2]})
      {:ok, signed} = Signer.sign(tx, private_key)
      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end

    test "contract creation (nil to)" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      tx = make_eip7702_tx(%{to: nil, data: <<0x60, 0x00>>})
      {:ok, signed} = Signer.sign(tx, private_key)
      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end
  end

  describe "encode/decode round-trip" do
    test "EIP-7702 signed tx round-trips through encode/decode" do
      private_key = EthCrypto.Signature.generate_private_key()
      tx = make_eip7702_tx()
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
      assert length(decoded.tx.authorization_list) == 1

      [auth] = decoded.tx.authorization_list
      assert auth.chain_id == 1
      assert auth.address == <<42::160>>
      assert auth.nonce == 0

      assert decoded.v == signed.v
      assert decoded.r == signed.r
      assert decoded.s == signed.s
    end
  end

  describe "tx_hash/1" do
    test "computes transaction hash for EIP-7702" do
      private_key = EthCrypto.Signature.generate_private_key()
      tx = make_eip7702_tx()
      {:ok, signed} = Signer.sign(tx, private_key)

      hash = EthCore.Types.SignedTransaction.tx_hash(signed)
      assert byte_size(hash) == 32
      assert hash == EthCore.Types.SignedTransaction.tx_hash(signed)
    end
  end
end
