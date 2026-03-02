defmodule EthCrypto.SignatureTest do
  use ExUnit.Case, async: true

  alias EthCrypto.{Hash, Key, Signature}

  # Test vectors from ethereum/tests BasicTests/keyaddrtest.json
  @cow_privkey Base.decode16!(
                 "c85ef7d79691fe79573b1a7064c19c1a9819ebdbd1faaab1a8ec92344438aaf4",
                 case: :lower
               )
  @horse_privkey Base.decode16!(
                   "c87f65ff3f271bf5dc8643484f66b200109caffe4bf98c4cb393dc35740b28c0",
                   case: :lower
                 )

  # secp256k1 curve order
  @secp256k1_n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @half_n div(@secp256k1_n, 2)

  describe "sign/2" do
    test "cow key signs empty string and recovers correct address" do
      msg_hash = Hash.keccak256("")
      {:ok, {r, s, v}} = Signature.sign(msg_hash, @cow_privkey)

      # s must be low (EIP-2)
      s_int = :binary.decode_unsigned(s)
      assert s_int <= @half_n

      # Recovery roundtrip proves signature is valid
      {:ok, pubkey} = Signature.recover(msg_hash, r <> s, v)
      assert Key.public_key_to_address(pubkey) == Key.privkey_to_address(@cow_privkey)
    end

    test "horse key signs empty string and recovers correct address" do
      msg_hash = Hash.keccak256("")
      {:ok, {r, s, v}} = Signature.sign(msg_hash, @horse_privkey)

      s_int = :binary.decode_unsigned(s)
      assert s_int <= @half_n

      {:ok, pubkey} = Signature.recover(msg_hash, r <> s, v)
      assert Key.public_key_to_address(pubkey) == Key.privkey_to_address(@horse_privkey)
    end

    test "returns 32-byte r, 32-byte s, and recovery_id 0 or 1" do
      msg_hash = Hash.keccak256("test message")
      {:ok, {r, s, v}} = Signature.sign(msg_hash, @cow_privkey)

      assert byte_size(r) == 32
      assert byte_size(s) == 32
      assert v in [0, 1]
    end
  end

  describe "recover/3" do
    test "sign then recover roundtrip with cow key" do
      msg_hash = Hash.keccak256("roundtrip test")
      {:ok, {r, s, v}} = Signature.sign(msg_hash, @cow_privkey)
      {:ok, pubkey} = Signature.recover(msg_hash, r <> s, v)

      expected_address = Key.privkey_to_address(@cow_privkey)
      recovered_address = Key.public_key_to_address(pubkey)
      assert recovered_address == expected_address
    end

    test "sign then recover roundtrip with horse key" do
      msg_hash = Hash.keccak256("another test")
      {:ok, {r, s, v}} = Signature.sign(msg_hash, @horse_privkey)
      {:ok, pubkey} = Signature.recover(msg_hash, r <> s, v)

      expected_address = Key.privkey_to_address(@horse_privkey)
      recovered_address = Key.public_key_to_address(pubkey)
      assert recovered_address == expected_address
    end

    test "sign then recover with random key" do
      privkey = Key.generate_private_key()
      msg_hash = Hash.keccak256("random key test")
      {:ok, {r, s, v}} = Signature.sign(msg_hash, privkey)
      {:ok, pubkey} = Signature.recover(msg_hash, r <> s, v)

      expected_address = Key.privkey_to_address(privkey)
      recovered_address = Key.public_key_to_address(pubkey)
      assert recovered_address == expected_address
    end
  end

  describe "EIP-2 low-s normalization" do
    test "sign always returns low-s value" do
      for _ <- 1..20 do
        privkey = Key.generate_private_key()
        msg_hash = :crypto.strong_rand_bytes(32)
        {:ok, {_r, s, _v}} = Signature.sign(msg_hash, privkey)
        s_int = :binary.decode_unsigned(s)
        assert s_int <= @half_n, "s value #{s_int} exceeds half curve order"
      end
    end

    test "normalize_s flips high-s to low-s" do
      # Create a high s value (just above half_n)
      high_s = @half_n + 1
      high_s_bin = <<high_s::unsigned-big-size(256)>>

      {normalized, _flipped} = Signature.normalize_s(high_s_bin)
      normalized_int = :binary.decode_unsigned(normalized)

      assert normalized_int <= @half_n
      assert normalized_int == @secp256k1_n - high_s
    end

    test "normalize_s keeps low-s unchanged" do
      low_s = @half_n - 1
      low_s_bin = <<low_s::unsigned-big-size(256)>>

      {normalized, flipped} = Signature.normalize_s(low_s_bin)
      assert normalized == low_s_bin
      refute flipped
    end
  end
end
