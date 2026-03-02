defmodule EthCrypto.KeyTest do
  use ExUnit.Case, async: true

  alias EthCrypto.Key

  # Test vectors from ethereum/tests BasicTests/keyaddrtest.json
  @cow_privkey Base.decode16!(
                 "c85ef7d79691fe79573b1a7064c19c1a9819ebdbd1faaab1a8ec92344438aaf4",
                 case: :lower
               )
  @horse_privkey Base.decode16!(
                   "c87f65ff3f271bf5dc8643484f66b200109caffe4bf98c4cb393dc35740b28c0",
                   case: :lower
                 )

  @cow_address Base.decode16!("cd2a3d9f938e13cd947ec05abc7fe734df8dd826", case: :lower)
  @horse_address Base.decode16!("13978aee95f38490e9769c39b2773ed763d9cd5f", case: :lower)

  describe "derive_public_key/1" do
    test "cow privkey derives 65-byte uncompressed pubkey" do
      {:ok, pubkey} = Key.derive_public_key(@cow_privkey)
      assert byte_size(pubkey) == 65
      # Uncompressed pubkey starts with 0x04
      assert <<0x04, _rest::binary-size(64)>> = pubkey
    end

    test "horse privkey derives 65-byte uncompressed pubkey" do
      {:ok, pubkey} = Key.derive_public_key(@horse_privkey)
      assert byte_size(pubkey) == 65
    end

    test "invalid privkey returns error" do
      assert {:error, _} = Key.derive_public_key(<<0::256>>)
    end
  end

  describe "public_key_to_address/1" do
    test "cow pubkey produces known address" do
      {:ok, pubkey} = Key.derive_public_key(@cow_privkey)
      address = Key.public_key_to_address(pubkey)
      assert address == @cow_address
    end

    test "horse pubkey produces known address" do
      {:ok, pubkey} = Key.derive_public_key(@horse_privkey)
      address = Key.public_key_to_address(pubkey)
      assert address == @horse_address
    end

    test "address is always 20 bytes" do
      {:ok, pubkey} = Key.derive_public_key(@cow_privkey)
      address = Key.public_key_to_address(pubkey)
      assert byte_size(address) == 20
    end
  end

  describe "generate_private_key/0" do
    test "returns 32 bytes" do
      key = Key.generate_private_key()
      assert byte_size(key) == 32
    end

    test "each call returns different key" do
      key1 = Key.generate_private_key()
      key2 = Key.generate_private_key()
      refute key1 == key2
    end

    test "generated key can derive valid pubkey" do
      key = Key.generate_private_key()
      assert {:ok, pubkey} = Key.derive_public_key(key)
      assert byte_size(pubkey) == 65
    end
  end

  describe "privkey_to_address/1" do
    test "cow privkey to address shortcut" do
      assert Key.privkey_to_address(@cow_privkey) == @cow_address
    end

    test "horse privkey to address shortcut" do
      assert Key.privkey_to_address(@horse_privkey) == @horse_address
    end
  end
end
