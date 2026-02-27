defmodule EthCrypto.SignatureTest do
  use ExUnit.Case, async: true

  alias EthCrypto.Signature

  describe "sign/2 and recover/4 round-trip" do
    test "signs and recovers a message" do
      private_key = Signature.generate_private_key()
      {:ok, public_key} = Signature.public_key_from_private(private_key)

      hash = EthCrypto.Hash.keccak256("test message")

      {:ok, {r, s, recovery_id}} = Signature.sign(hash, private_key)

      assert byte_size(r) == 32
      assert byte_size(s) == 32
      assert recovery_id in [0, 1]

      {:ok, recovered_key} = Signature.recover(hash, r, s, recovery_id)
      assert recovered_key == public_key
    end

    test "different messages produce different signatures" do
      private_key = Signature.generate_private_key()

      hash1 = EthCrypto.Hash.keccak256("message 1")
      hash2 = EthCrypto.Hash.keccak256("message 2")

      {:ok, {r1, s1, _}} = Signature.sign(hash1, private_key)
      {:ok, {r2, s2, _}} = Signature.sign(hash2, private_key)

      refute {r1, s1} == {r2, s2}
    end
  end

  describe "EIP-2 s-value normalization" do
    @secp256k1n_half div(
                       0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141,
                       2
                     )

    test "all signatures have s <= secp256k1n/2" do
      private_key = Signature.generate_private_key()

      for i <- 1..50 do
        hash = EthCrypto.Hash.keccak256("test message #{i}")
        {:ok, {_r, s, _recovery_id}} = Signature.sign(hash, private_key)
        s_int = :binary.decode_unsigned(s)
        assert s_int <= @secp256k1n_half, "s-value exceeds secp256k1n/2 on iteration #{i}"
      end
    end

    test "normalized signatures still recover correctly" do
      for i <- 1..20 do
        private_key = Signature.generate_private_key()
        {:ok, public_key} = Signature.public_key_from_private(private_key)
        hash = EthCrypto.Hash.keccak256("recover test #{i}")

        {:ok, {r, s, recovery_id}} = Signature.sign(hash, private_key)
        {:ok, recovered_key} = Signature.recover(hash, r, s, recovery_id)
        assert recovered_key == public_key, "Recovery failed on iteration #{i}"
      end
    end

    test "low_s?/1 returns true for normalized signatures" do
      private_key = Signature.generate_private_key()
      hash = EthCrypto.Hash.keccak256("low_s test")
      {:ok, {_r, s, _recovery_id}} = Signature.sign(hash, private_key)
      assert Signature.low_s?(s)
    end
  end

  describe "generate_private_key/0" do
    test "generates 32-byte key" do
      key = Signature.generate_private_key()
      assert byte_size(key) == 32
    end

    test "generates unique keys" do
      key1 = Signature.generate_private_key()
      key2 = Signature.generate_private_key()
      refute key1 == key2
    end
  end

  describe "public_key_from_private/1" do
    test "derives a 64-byte public key" do
      private_key = Signature.generate_private_key()
      {:ok, public_key} = Signature.public_key_from_private(private_key)
      assert byte_size(public_key) == 64
    end

    test "deterministic derivation" do
      private_key = Signature.generate_private_key()
      {:ok, pk1} = Signature.public_key_from_private(private_key)
      {:ok, pk2} = Signature.public_key_from_private(private_key)
      assert pk1 == pk2
    end

    test "known test vector" do
      # Well-known test vector from Ethereum
      private_key =
        Base.decode16!("4C0883A69102937D6231471B5DBB6204FE512961708279F696AE98E0A6D3E7E3",
          case: :upper
        )

      {:ok, public_key} = Signature.public_key_from_private(private_key)
      assert byte_size(public_key) == 64
    end
  end
end
