defmodule EthCore.Types.AddressTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.Address

  describe "new/1" do
    test "accepts 20-byte binary" do
      bytes = :crypto.strong_rand_bytes(20)
      assert {:ok, ^bytes} = Address.new(bytes)
    end

    test "rejects wrong size" do
      assert {:error, :invalid_address} = Address.new(<<1, 2, 3>>)
    end
  end

  describe "from_hex/1" do
    test "parses 0x-prefixed hex" do
      hex = "0x" <> String.duplicate("ab", 20)
      {:ok, addr} = Address.from_hex(hex)
      assert byte_size(addr) == 20
    end

    test "parses plain hex" do
      hex = String.duplicate("cd", 20)
      {:ok, addr} = Address.from_hex(hex)
      assert byte_size(addr) == 20
    end

    test "rejects invalid" do
      assert {:error, :invalid_hex} = Address.from_hex("short")
    end
  end

  describe "to_hex/1" do
    test "round-trips" do
      hex = "0x" <> String.duplicate("ab", 20)
      {:ok, addr} = Address.from_hex(hex)
      assert Address.to_hex(addr) == hex
    end
  end

  describe "to_checksum_hex/1" do
    test "EIP-55 checksum - known vectors" do
      # All caps
      {:ok, addr} = Address.from_hex("0x52908400098527886E0F7030069857D2E4169EE7")
      result = Address.to_checksum_hex(addr)
      assert result == "0x52908400098527886E0F7030069857D2E4169EE7"

      # All lower
      {:ok, addr2} = Address.from_hex("0xde709f2102306220921060314715629080e2fb77")
      result2 = Address.to_checksum_hex(addr2)
      assert result2 == "0xde709f2102306220921060314715629080e2fb77"

      # Mixed case (common known address)
      {:ok, addr3} = Address.from_hex("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
      result3 = Address.to_checksum_hex(addr3)
      assert result3 == "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
    end
  end

  describe "from_public_key/1" do
    test "derives address from known public key" do
      # Known test vector
      private_key =
        Base.decode16!("4C0883A69102937D6231471B5DBB6204FE512961708279F696AE98E0A6D3E7E3",
          case: :upper
        )

      {:ok, public_key} = EthCrypto.Signature.public_key_from_private(private_key)
      address = Address.from_public_key(public_key)

      assert byte_size(address) == 20
      # This is the known address for this private key
      assert Address.to_hex(address) == "0x7d19860ffa09ea2ecf22aea7e662ba224e971b4e"
    end
  end

  describe "zero/0" do
    test "is 20 zero bytes" do
      assert Address.zero() == <<0::160>>
    end
  end
end
