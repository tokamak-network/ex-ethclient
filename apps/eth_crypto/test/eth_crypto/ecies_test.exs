defmodule EthCrypto.ECIESTest do
  use ExUnit.Case, async: true

  alias EthCrypto.ECIES

  describe "encrypt/decrypt roundtrip" do
    test "basic roundtrip" do
      privkey = EthCrypto.Signature.generate_private_key()
      {:ok, pubkey} = EthCrypto.Signature.public_key_from_private(privkey)

      plaintext = "hello world"
      {:ok, ciphertext} = ECIES.encrypt(plaintext, pubkey)
      {:ok, decrypted} = ECIES.decrypt(ciphertext, privkey)

      assert decrypted == plaintext
    end

    test "empty plaintext" do
      privkey = EthCrypto.Signature.generate_private_key()
      {:ok, pubkey} = EthCrypto.Signature.public_key_from_private(privkey)

      {:ok, ciphertext} = ECIES.encrypt(<<>>, pubkey)
      {:ok, decrypted} = ECIES.decrypt(ciphertext, privkey)

      assert decrypted == <<>>
    end

    test "large plaintext" do
      privkey = EthCrypto.Signature.generate_private_key()
      {:ok, pubkey} = EthCrypto.Signature.public_key_from_private(privkey)

      plaintext = :crypto.strong_rand_bytes(1024)
      {:ok, ciphertext} = ECIES.encrypt(plaintext, pubkey)
      {:ok, decrypted} = ECIES.decrypt(ciphertext, privkey)

      assert decrypted == plaintext
    end

    test "wrong key fails decryption" do
      privkey = EthCrypto.Signature.generate_private_key()
      {:ok, pubkey} = EthCrypto.Signature.public_key_from_private(privkey)

      wrong_privkey = EthCrypto.Signature.generate_private_key()

      {:ok, ciphertext} = ECIES.encrypt("secret", pubkey)
      assert {:error, :invalid_mac} = ECIES.decrypt(ciphertext, wrong_privkey)
    end

    test "ciphertext format is correct" do
      privkey = EthCrypto.Signature.generate_private_key()
      {:ok, pubkey} = EthCrypto.Signature.public_key_from_private(privkey)

      plaintext = "test"
      {:ok, ciphertext} = ECIES.encrypt(plaintext, pubkey)

      # 1 (0x04) + 64 (pubkey) + 16 (iv) + 4 (ciphertext) + 32 (hmac) = 117
      assert byte_size(ciphertext) == 1 + 64 + 16 + byte_size(plaintext) + 32
      assert <<4, _::binary>> = ciphertext
    end

    test "tampered ciphertext fails" do
      privkey = EthCrypto.Signature.generate_private_key()
      {:ok, pubkey} = EthCrypto.Signature.public_key_from_private(privkey)

      {:ok, ciphertext} = ECIES.encrypt("secret", pubkey)

      # Flip a byte in the ciphertext portion
      <<prefix::binary-size(81), byte, rest::binary>> = ciphertext
      tampered = prefix <> <<Bitwise.bxor(byte, 0xFF)>> <> rest

      assert {:error, :invalid_mac} = ECIES.decrypt(tampered, privkey)
    end
  end

  describe "ecdh/2" do
    test "shared secret is symmetric" do
      privkey_a = EthCrypto.Signature.generate_private_key()
      {:ok, pubkey_a} = EthCrypto.Signature.public_key_from_private(privkey_a)

      privkey_b = EthCrypto.Signature.generate_private_key()
      {:ok, pubkey_b} = EthCrypto.Signature.public_key_from_private(privkey_b)

      {:ok, shared_ab} = ECIES.ecdh(pubkey_b, privkey_a)
      {:ok, shared_ba} = ECIES.ecdh(pubkey_a, privkey_b)

      assert shared_ab == shared_ba
    end

    test "shared secret is 32 bytes" do
      privkey_a = EthCrypto.Signature.generate_private_key()
      privkey_b = EthCrypto.Signature.generate_private_key()
      {:ok, pubkey_b} = EthCrypto.Signature.public_key_from_private(privkey_b)

      {:ok, shared} = ECIES.ecdh(pubkey_b, privkey_a)
      assert byte_size(shared) == 32
    end
  end

  describe "concat_kdf/2" do
    test "produces deterministic output" do
      secret = :crypto.strong_rand_bytes(32)
      assert ECIES.concat_kdf(secret, 32) == ECIES.concat_kdf(secret, 32)
    end

    test "different secrets produce different keys" do
      s1 = :crypto.strong_rand_bytes(32)
      s2 = :crypto.strong_rand_bytes(32)
      refute ECIES.concat_kdf(s1, 32) == ECIES.concat_kdf(s2, 32)
    end
  end
end
