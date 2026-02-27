defmodule EthCore.TestVectorsTest do
  use ExUnit.Case, async: true

  alias EthCore.RLP
  alias EthCore.Transaction.Signer
  alias EthCore.Types.{Address, SignedTransaction, Transaction}

  # --- Ethereum Official RLP Test Vectors ---
  # From https://github.com/ethereum/tests/blob/develop/RLPTests/rlptest.json

  describe "official RLP test vectors" do
    test "emptystring" do
      assert RLP.encode(<<>>) == Base.decode16!("80", case: :lower)
    end

    test "bytestring00" do
      assert RLP.encode(<<0x00>>) == Base.decode16!("00", case: :lower)
    end

    test "shortstring - dog" do
      assert RLP.encode("dog") == Base.decode16!("83646f67", case: :lower)
    end

    test "shortstring2 - single char a" do
      assert RLP.encode("a") == Base.decode16!("61", case: :lower)
    end

    test "shortlist - cat, dog" do
      assert RLP.encode(["cat", "dog"]) ==
               Base.decode16!("c88363617483646f67", case: :lower)
    end

    test "emptylist" do
      assert RLP.encode([]) == Base.decode16!("c0", case: :lower)
    end

    test "multilist - nested empty lists" do
      # [[], [[]], [[], [[]]]]
      assert RLP.encode([[], [[]], [[], [[]]]]) ==
               Base.decode16!("c7c0c1c0c3c0c1c0", case: :lower)
    end

    test "integer 0" do
      # 0 encodes as empty string
      assert RLP.encode(<<>>) == <<0x80>>
    end

    test "integer 15" do
      assert RLP.encode(<<0x0F>>) == <<0x0F>>
    end

    test "integer 1024" do
      assert RLP.encode(<<0x04, 0x00>>) == <<0x82, 0x04, 0x00>>
    end
  end

  # --- EIP-155 Signing Test Vector ---
  # From https://eips.ethereum.org/EIPS/eip-155

  describe "EIP-155 signing test vector" do
    @eip155_private_key Base.decode16!(
                          "4646464646464646464646464646464646464646464646464646464646464646",
                          case: :upper
                        )

    test "signing hash matches expected value" do
      tx = %Transaction.Legacy{
        nonce: 9,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: Base.decode16!("3535353535353535353535353535353535353535", case: :upper),
        value: 1_000_000_000_000_000_000,
        data: <<>>
      }

      payload = RLP.encode_for_signing(tx, 1)
      hash = EthCrypto.Hash.keccak256(payload)

      expected_hash =
        Base.decode16!(
          "daf5a779ae972f972197303d7b574746c7ef83eadac0f2791ad23db92e4c8e53",
          case: :lower
        )

      assert hash == expected_hash
    end

    test "signs with correct v=37 for chain_id=1" do
      tx = %Transaction.Legacy{
        nonce: 9,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: Base.decode16!("3535353535353535353535353535353535353535", case: :upper),
        value: 1_000_000_000_000_000_000,
        data: <<>>
      }

      {:ok, signed} = Signer.sign(tx, @eip155_private_key, 1)

      # v must be 37 or 38 (chain_id=1: 1*2+35=37, +recovery_id)
      assert signed.v in [37, 38]

      # Verify recovery works
      {:ok, recovered} = Signer.recover_sender(signed)
      {:ok, expected_pub} = EthCrypto.Signature.public_key_from_private(@eip155_private_key)
      expected_addr = Address.from_public_key(expected_pub)
      assert recovered == expected_addr
    end

    test "known sender address from the EIP-155 spec" do
      {:ok, expected_pub} = EthCrypto.Signature.public_key_from_private(@eip155_private_key)
      addr = Address.from_public_key(expected_pub)
      hex_addr = Address.to_hex(addr)

      # The EIP-155 spec sender address
      assert hex_addr == "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f"
    end
  end

  # --- Error path tests (Step 10) ---

  describe "error paths - invalid v values" do
    test "v < 27 returns error" do
      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      signed = SignedTransaction.new(tx, 26, 12345, 67890)
      assert {:error, {:invalid_v_value, 26}} = Signer.recover_sender(signed)
    end

    test "v = 29 returns error" do
      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      signed = SignedTransaction.new(tx, 29, 12345, 67890)
      assert {:error, {:invalid_v_value, 29}} = Signer.recover_sender(signed)
    end

    test "v = 0 returns error" do
      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      signed = SignedTransaction.new(tx, 0, 12345, 67890)
      assert {:error, {:invalid_v_value, 0}} = Signer.recover_sender(signed)
    end
  end

  describe "error paths - invalid signature components" do
    test "r=0 fails with invalid_signature" do
      tx = %Transaction.EIP1559{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1_500_000_000,
        max_fee_per_gas: 30_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>,
        access_list: []
      }

      signed = SignedTransaction.new(tx, 0, 0, 12345)
      assert {:error, {:invalid_signature, _}} = Signer.recover_sender(signed)
    end

    test "s=0 fails with invalid_signature" do
      tx = %Transaction.EIP1559{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1_500_000_000,
        max_fee_per_gas: 30_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>,
        access_list: []
      }

      signed = SignedTransaction.new(tx, 0, 12345, 0)
      assert {:error, {:invalid_signature, _}} = Signer.recover_sender(signed)
    end

    test "typed tx with invalid recovery_id fails" do
      tx = %Transaction.EIP1559{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1_500_000_000,
        max_fee_per_gas: 30_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>,
        access_list: []
      }

      # v=5 is invalid for typed tx (should be 0 or 1)
      signed = SignedTransaction.new(tx, 5, 12345, 67890)
      assert {:error, {:invalid_recovery_id, 5}} = Signer.recover_sender(signed)
    end
  end

  describe "error paths - v value edge cases" do
    test "v values 29-34 are all invalid" do
      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      for v <- 29..34 do
        signed = SignedTransaction.new(tx, v, 12345, 67890)
        assert {:error, {:invalid_v_value, ^v}} = Signer.recover_sender(signed)
      end
    end

    test "negative-ish v value returns error" do
      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      signed = SignedTransaction.new(tx, 1, 12345, 67890)
      assert {:error, {:invalid_v_value, 1}} = Signer.recover_sender(signed)
    end
  end

  describe "error paths - uint256 boundary" do
    test "uint256 max value encodes/decodes correctly" do
      max_uint256 = :math.pow(2, 256) |> round() |> Kernel.-(1)
      encoded = RLP.encode_integer(max_uint256)
      assert byte_size(encoded) == 32
      assert RLP.decode_integer(encoded) == max_uint256
    end

    test "zero encodes as empty binary" do
      assert RLP.encode_integer(0) == <<>>
      assert RLP.decode_integer(<<>>) == 0
    end
  end

  describe "error paths - nil vs empty binary distinction" do
    test "nil address encodes as empty binary, decodes as nil" do
      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 100_000,
        to: nil,
        value: 0,
        data: <<0x60, 0x00>>
      }

      private_key = EthCrypto.Signature.generate_private_key()
      {:ok, signed} = Signer.sign(tx, private_key, 1)
      encoded = RLP.encode_signed(signed)
      {:ok, decoded} = RLP.decode_signed(encoded)

      assert decoded.tx.to == nil
    end
  end

  describe "address checksum validation" do
    test "valid EIP-55 checksum" do
      # Known EIP-55 test vectors
      assert {:ok, _} =
               Address.from_checksum_hex("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")

      assert {:ok, _} =
               Address.from_checksum_hex("0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359")
    end

    test "invalid checksum returns error" do
      # Wrong case (invalid checksum)
      assert {:error, :invalid_checksum} =
               Address.from_checksum_hex("0x5AAEB6053f3e94c9b9a09f33669435e7ef1beaed")
    end

    test "valid_checksum?/1 returns true for all-lowercase" do
      assert Address.valid_checksum?("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
    end

    test "valid_checksum?/1 returns true for all-uppercase" do
      assert Address.valid_checksum?("0x5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED")
    end

    test "valid_checksum?/1 returns true for proper mixed case" do
      assert Address.valid_checksum?("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    end

    test "valid_checksum?/1 returns false for wrong mixed case" do
      refute Address.valid_checksum?("0x5AAEB6053f3e94c9b9a09f33669435e7ef1beaed")
    end
  end

  describe "tx_hash/1" do
    test "computes deterministic hash for legacy transaction" do
      private_key = EthCrypto.Signature.generate_private_key()

      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 1_000_000_000_000_000_000,
        data: <<>>
      }

      {:ok, signed} = Signer.sign(tx, private_key, 1)
      hash1 = SignedTransaction.tx_hash(signed)
      hash2 = SignedTransaction.tx_hash(signed)

      assert byte_size(hash1) == 32
      assert hash1 == hash2
    end

    test "different transactions produce different hashes" do
      private_key = EthCrypto.Signature.generate_private_key()

      tx1 = %Transaction.Legacy{
        nonce: 0,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      tx2 = %Transaction.Legacy{
        nonce: 1,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      {:ok, signed1} = Signer.sign(tx1, private_key, 1)
      {:ok, signed2} = Signer.sign(tx2, private_key, 1)

      refute SignedTransaction.tx_hash(signed1) == SignedTransaction.tx_hash(signed2)
    end
  end
end
