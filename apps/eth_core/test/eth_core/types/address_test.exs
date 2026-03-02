defmodule EthCore.Types.AddressTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.Address

  # From ethereum/tests BasicTests/keyaddrtest.json
  @cow_privkey Base.decode16!(
                 "c85ef7d79691fe79573b1a7064c19c1a9819ebdbd1faaab1a8ec92344438aaf4",
                 case: :lower
               )
  @cow_address_hex "0xcd2a3d9f938e13cd947ec05abc7fe734df8dd826"
  @cow_address_bytes Base.decode16!("cd2a3d9f938e13cd947ec05abc7fe734df8dd826", case: :lower)

  @horse_privkey Base.decode16!(
                   "c87f65ff3f271bf5dc8643484f66b200109caffe4bf98c4cb393dc35740b28c0",
                   case: :lower
                 )
  @horse_address_bytes Base.decode16!("13978aee95f38490e9769c39b2773ed763d9cd5f", case: :lower)

  describe "new/1" do
    test "accepts 20-byte binary" do
      assert {:ok, addr} = Address.new(@cow_address_bytes)
      assert addr.bytes == @cow_address_bytes
    end

    test "rejects wrong size binary" do
      assert {:error, _} = Address.new(<<0::8*19>>)
      assert {:error, _} = Address.new(<<0::8*21>>)
      assert {:error, _} = Address.new(<<>>)
    end
  end

  describe "from_hex/1" do
    test "parses 0x-prefixed hex" do
      assert {:ok, addr} = Address.from_hex(@cow_address_hex)
      assert addr.bytes == @cow_address_bytes
    end

    test "parses without 0x prefix" do
      assert {:ok, addr} = Address.from_hex("cd2a3d9f938e13cd947ec05abc7fe734df8dd826")
      assert addr.bytes == @cow_address_bytes
    end

    test "handles mixed case" do
      assert {:ok, addr} = Address.from_hex("0xCD2A3D9F938E13CD947EC05ABC7FE734DF8DD826")
      assert addr.bytes == @cow_address_bytes
    end

    test "rejects invalid hex" do
      assert {:error, _} = Address.from_hex("0xZZZZ")
      assert {:error, _} = Address.from_hex("0x1234")
    end
  end

  describe "to_hex/1" do
    test "returns 0x-prefixed lowercase hex" do
      {:ok, addr} = Address.new(@cow_address_bytes)
      assert Address.to_hex(addr) == @cow_address_hex
    end
  end

  describe "zero/0" do
    test "returns 20-byte zero address" do
      addr = Address.zero()
      assert addr.bytes == <<0::160>>
      assert Address.to_hex(addr) == "0x" <> String.duplicate("0", 40)
    end
  end

  describe "from_private_key/1" do
    test "cow private key derives known address" do
      addr = Address.from_private_key(@cow_privkey)
      assert addr.bytes == @cow_address_bytes
    end

    test "horse private key derives known address" do
      addr = Address.from_private_key(@horse_privkey)
      assert addr.bytes == @horse_address_bytes
    end
  end
end
