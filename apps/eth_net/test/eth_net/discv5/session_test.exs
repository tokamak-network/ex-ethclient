defmodule EthNet.DiscV5.SessionTest do
  use ExUnit.Case, async: true

  alias EthNet.DiscV5.Session

  describe "new_challenge/1" do
    test "creates a challenge with random id_nonce" do
      challenge = Session.new_challenge(0)
      assert byte_size(challenge.id_nonce) == 16
      assert challenge.enr_seq == 0
    end

    test "creates unique challenges" do
      c1 = Session.new_challenge(1)
      c2 = Session.new_challenge(1)
      assert c1.id_nonce != c2.id_nonce
    end

    test "stores enr_seq" do
      challenge = Session.new_challenge(42)
      assert challenge.enr_seq == 42
    end
  end

  describe "derive_keys/4" do
    test "derives two 16-byte keys from shared secret" do
      shared_secret = :crypto.strong_rand_bytes(32)
      id_nonce = :crypto.strong_rand_bytes(16)
      initiator_id = :crypto.strong_rand_bytes(32)
      recipient_id = :crypto.strong_rand_bytes(32)

      assert {:ok, {init_key, recip_key}} =
               Session.derive_keys(shared_secret, id_nonce, initiator_id, recipient_id)

      assert byte_size(init_key) == 16
      assert byte_size(recip_key) == 16
      assert init_key != recip_key
    end

    test "same inputs produce same keys" do
      shared_secret = :crypto.strong_rand_bytes(32)
      id_nonce = :crypto.strong_rand_bytes(16)
      initiator_id = :crypto.strong_rand_bytes(32)
      recipient_id = :crypto.strong_rand_bytes(32)

      {:ok, keys1} = Session.derive_keys(shared_secret, id_nonce, initiator_id, recipient_id)
      {:ok, keys2} = Session.derive_keys(shared_secret, id_nonce, initiator_id, recipient_id)
      assert keys1 == keys2
    end

    test "different id_nonces produce different keys" do
      shared_secret = :crypto.strong_rand_bytes(32)
      id1 = :crypto.strong_rand_bytes(32)
      id2 = :crypto.strong_rand_bytes(32)

      {:ok, keys1} =
        Session.derive_keys(shared_secret, :crypto.strong_rand_bytes(16), id1, id2)

      {:ok, keys2} =
        Session.derive_keys(shared_secret, :crypto.strong_rand_bytes(16), id1, id2)

      assert keys1 != keys2
    end
  end

  describe "from_keys/3" do
    test "creates a session with zero nonce counter" do
      node_id = :crypto.strong_rand_bytes(32)
      init_key = :crypto.strong_rand_bytes(16)
      recip_key = :crypto.strong_rand_bytes(16)

      session = Session.from_keys(node_id, init_key, recip_key)
      assert session.node_id == node_id
      assert session.initiator_key == init_key
      assert session.recipient_key == recip_key
      assert session.nonce_counter == 0
    end
  end

  describe "next_nonce/1" do
    test "returns a 12-byte nonce and increments counter" do
      session = Session.from_keys(:crypto.strong_rand_bytes(32), <<0::128>>, <<0::128>>)

      {nonce, session} = Session.next_nonce(session)
      assert byte_size(nonce) == 12
      assert session.nonce_counter == 1

      {nonce2, session} = Session.next_nonce(session)
      assert nonce2 != nonce
      assert session.nonce_counter == 2
    end
  end

  describe "encrypt/decrypt roundtrip" do
    test "encrypts and decrypts a message" do
      init_key = :crypto.strong_rand_bytes(16)
      recip_key = :crypto.strong_rand_bytes(16)
      node_id = :crypto.strong_rand_bytes(32)

      # Sender uses initiator_key to encrypt
      sender = Session.from_keys(node_id, init_key, recip_key)
      # Receiver uses the same init_key as recipient_key to decrypt
      receiver = Session.from_keys(node_id, recip_key, init_key)

      plaintext = "hello discv5"
      ad = "associated data"

      {nonce, _sender} = Session.next_nonce(sender)
      {:ok, ciphertext, _sender} = Session.encrypt(sender, plaintext, ad)

      assert {:ok, ^plaintext} = Session.decrypt(receiver, ciphertext, nonce, ad)
    end

    test "decryption fails with wrong key" do
      init_key = :crypto.strong_rand_bytes(16)
      wrong_key = :crypto.strong_rand_bytes(16)
      node_id = :crypto.strong_rand_bytes(32)

      sender = Session.from_keys(node_id, init_key, <<0::128>>)
      receiver = Session.from_keys(node_id, <<0::128>>, wrong_key)

      plaintext = "secret data"
      ad = "ad"

      {nonce, _sender} = Session.next_nonce(sender)
      {:ok, ciphertext, _sender} = Session.encrypt(sender, plaintext, ad)

      assert {:error, :decryption_failed} = Session.decrypt(receiver, ciphertext, nonce, ad)
    end

    test "decryption fails with wrong associated data" do
      key = :crypto.strong_rand_bytes(16)
      node_id = :crypto.strong_rand_bytes(32)

      sender = Session.from_keys(node_id, key, <<0::128>>)
      receiver = Session.from_keys(node_id, <<0::128>>, key)

      {nonce, _sender} = Session.next_nonce(sender)
      {:ok, ciphertext, _sender} = Session.encrypt(sender, "hello", "correct ad")

      assert {:error, :decryption_failed} = Session.decrypt(receiver, ciphertext, nonce, "wrong ad")
    end

    test "decryption fails with too short ciphertext" do
      key = :crypto.strong_rand_bytes(16)
      node_id = :crypto.strong_rand_bytes(32)
      session = Session.from_keys(node_id, <<0::128>>, key)

      assert {:error, :ciphertext_too_short} =
               Session.decrypt(session, <<1, 2, 3>>, <<0::96>>, "ad")
    end
  end

  describe "sign_id_nonce/3" do
    test "produces a 32-byte hash" do
      id_nonce = :crypto.strong_rand_bytes(16)
      ephemeral_pubkey = :crypto.strong_rand_bytes(32)
      dest_node_id = :crypto.strong_rand_bytes(32)

      result = Session.sign_id_nonce(id_nonce, ephemeral_pubkey, dest_node_id)
      assert byte_size(result) == 32
    end

    test "produces deterministic output" do
      id_nonce = :crypto.strong_rand_bytes(16)
      eph = :crypto.strong_rand_bytes(32)
      dest = :crypto.strong_rand_bytes(32)

      assert Session.sign_id_nonce(id_nonce, eph, dest) ==
               Session.sign_id_nonce(id_nonce, eph, dest)
    end
  end
end
