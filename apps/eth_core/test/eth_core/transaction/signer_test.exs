defmodule EthCore.Transaction.SignerTest do
  use ExUnit.Case, async: true

  alias EthCore.Transaction.Signer
  alias EthCore.Types.{Address, Transaction}

  @known_private_key Base.decode16!(
                       "4C0883A69102937D6231471B5DBB6204FE512961708279F696AE98E0A6D3E7E3",
                       case: :upper
                     )

  describe "sign/3 + recover_sender/1 - Legacy (EIP-155)" do
    test "signs and recovers sender" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 1_000_000_000_000_000_000,
        data: <<>>
      }

      {:ok, signed} = Signer.sign(tx, private_key, 1)

      assert signed.v >= 37
      assert signed.r > 0
      assert signed.s > 0

      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end

    test "EIP-155 known test vector - chain_id 1" do
      # Famous EIP-155 test vector:
      # nonce=9, gasprice=20gwei, gaslimit=21000, to=0x3535..., value=1eth
      tx = %Transaction.Legacy{
        nonce: 9,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: Base.decode16!("3535353535353535353535353535353535353535", case: :upper),
        value: 1_000_000_000_000_000_000,
        data: <<>>
      }

      # Sign with the known private key
      {:ok, signed} = Signer.sign(tx, @known_private_key, 1)
      {:ok, recovered} = Signer.recover_sender(signed)

      # Verify the recovered address matches the known address
      {:ok, expected_pub} = EthCrypto.Signature.public_key_from_private(@known_private_key)
      expected_addr = Address.from_public_key(expected_pub)

      assert recovered == expected_addr
    end

    test "contract creation (nil to)" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 100_000,
        to: nil,
        value: 0,
        data: <<0x60, 0x00, 0x60, 0x00>>
      }

      {:ok, signed} = Signer.sign(tx, private_key, 1)
      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end
  end

  describe "sign/3 + recover_sender/1 - EIP-2930" do
    test "signs and recovers sender" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      tx = %Transaction.EIP2930{
        chain_id: 1,
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>,
        access_list: []
      }

      {:ok, signed} = Signer.sign(tx, private_key)

      assert signed.v in [0, 1]
      assert signed.r > 0
      assert signed.s > 0

      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end

    test "with access list" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      storage_key = <<1::256>>

      tx = %Transaction.EIP2930{
        chain_id: 1,
        nonce: 5,
        gas_price: 30_000_000_000,
        gas_limit: 50_000,
        to: <<2::160>>,
        value: 100,
        data: <<0xDE, 0xAD>>,
        access_list: [{<<3::160>>, [storage_key]}]
      }

      {:ok, signed} = Signer.sign(tx, private_key)
      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end
  end

  describe "sign/3 + recover_sender/1 - EIP-1559" do
    test "signs and recovers sender" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      tx = %Transaction.EIP1559{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1_500_000_000,
        max_fee_per_gas: 30_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 1_000_000_000_000_000_000,
        data: <<>>,
        access_list: []
      }

      {:ok, signed} = Signer.sign(tx, private_key)

      assert signed.v in [0, 1]
      assert signed.r > 0
      assert signed.s > 0

      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end

    test "with data and access list" do
      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      expected_address = Address.from_public_key(public_key)

      tx = %Transaction.EIP1559{
        chain_id: 1,
        nonce: 42,
        max_priority_fee_per_gas: 2_000_000_000,
        max_fee_per_gas: 50_000_000_000,
        gas_limit: 100_000,
        to: <<5::160>>,
        value: 0,
        data: :crypto.strong_rand_bytes(100),
        access_list: [
          {<<10::160>>, [<<100::256>>, <<200::256>>]},
          {<<20::160>>, []}
        ]
      }

      {:ok, signed} = Signer.sign(tx, private_key)
      {:ok, recovered} = Signer.recover_sender(signed)
      assert recovered == expected_address
    end
  end

  describe "different chain IDs" do
    test "chain_id affects legacy signature" do
      private_key = EthCrypto.Signature.generate_private_key()

      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      {:ok, signed_1} = Signer.sign(tx, private_key, 1)
      {:ok, signed_5} = Signer.sign(tx, private_key, 5)

      # Different chain IDs produce different v values
      refute signed_1.v == signed_5.v

      # Both should recover correctly
      {:ok, addr_1} = Signer.recover_sender(signed_1)
      {:ok, addr_5} = Signer.recover_sender(signed_5)
      assert addr_1 == addr_5
    end
  end
end
