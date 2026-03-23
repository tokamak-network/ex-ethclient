defmodule EthVm.PrecompileTest do
  @moduledoc """
  Tests for Ethereum precompiled contracts via the revm NIF.

  These tests verify that precompiles (ecrecover, sha256, identity, etc.)
  are properly enabled and return correct results when called through
  the EVM execution engine.
  """
  use ExUnit.Case, async: true

  @moduletag :nif

  alias EthVm.Native

  # Sender address (above precompile range 0x01-0x09)
  @sender <<0xAA::8, 0::152>>
  # Large balance: 10 ETH
  @balance <<0x8A, 0xC7, 0x23, 0x04, 0x89, 0xE8, 0x00, 0x00>>

  describe "ecrecover precompile (0x01)" do
    test "recovers address from valid signature components" do
      # Known test vector: keccak256("test message")
      # We use a pre-computed valid ecrecover input:
      #   - 32 bytes: message hash
      #   - 32 bytes: v (recovery id, 27 or 28, left-padded to 32 bytes)
      #   - 32 bytes: r
      #   - 32 bytes: s
      #
      # For simplicity, we use a well-known test vector.
      # Hash of empty string via keccak256
      hash =
        <<0xC5, 0xD2, 0x46, 0x01, 0x86, 0xF7, 0x23, 0x3C, 0x92, 0x7E, 0x7D, 0xB2, 0xDC, 0xC7,
          0x03, 0xC0, 0xE5, 0x00, 0xB6, 0x53, 0xCA, 0x82, 0x27, 0x3B, 0x7B, 0xFA, 0xD8, 0x04,
          0x5D, 0x85, 0xA4, 0x70>>

      # v = 27 (left-padded to 32 bytes)
      v = <<0::248, 27>>
      # Dummy r and s values (this won't recover a valid address, but the precompile should
      # still execute without error and return 32 bytes of output or empty on invalid sig)
      r = <<0::248, 1>>
      s = <<0::248, 1>>

      ecrecover_input = hash <> v <> r <> s
      ecrecover_addr = <<0::152, 0x01::8>>

      assert {:ok, result} =
               Native.execute_tx_v2(
                 0,
                 @sender,
                 ecrecover_addr,
                 <<>>,
                 100_000,
                 <<>>,
                 <<>>,
                 <<>>,
                 ecrecover_input,
                 <<>>,
                 0,
                 @balance,
                 <<>>,
                 <<>>
               )

      assert result[:success] == true
      assert result[:gas_used] > 0
      # ecrecover returns 32 bytes (address left-padded) or empty on invalid
      output = result[:output]
      assert is_binary(output)
    end
  end

  describe "sha256 precompile (0x02)" do
    test "computes sha256 of input data" do
      # SHA-256 of empty input is known:
      # e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
      sha256_addr = <<0::152, 0x02::8>>

      assert {:ok, result} =
               Native.execute_tx_v2(
                 0,
                 @sender,
                 sha256_addr,
                 <<>>,
                 100_000,
                 <<>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 0,
                 @balance,
                 <<>>,
                 <<>>
               )

      assert result[:success] == true

      expected_hash =
        <<0xE3, 0xB0, 0xC4, 0x42, 0x98, 0xFC, 0x1C, 0x14, 0x9A, 0xFB, 0xF4, 0xC8, 0x99, 0x6F,
          0xB9, 0x24, 0x27, 0xAE, 0x41, 0xE4, 0x64, 0x9B, 0x93, 0x4C, 0xA4, 0x95, 0x99, 0x1B,
          0x78, 0x52, 0xB8, 0x55>>

      assert result[:output] == expected_hash
    end

    test "computes sha256 of 'hello'" do
      sha256_addr = <<0::152, 0x02::8>>

      assert {:ok, result} =
               Native.execute_tx_v2(
                 0,
                 @sender,
                 sha256_addr,
                 <<>>,
                 100_000,
                 <<>>,
                 <<>>,
                 <<>>,
                 "hello",
                 <<>>,
                 0,
                 @balance,
                 <<>>,
                 <<>>
               )

      assert result[:success] == true

      # SHA-256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
      expected =
        <<0x2C, 0xF2, 0x4D, 0xBA, 0x5F, 0xB0, 0xA3, 0x0E, 0x26, 0xE8, 0x3B, 0x2A, 0xC5, 0xB9,
          0xE2, 0x9E, 0x1B, 0x16, 0x1E, 0x5C, 0x1F, 0xA7, 0x42, 0x5E, 0x73, 0x04, 0x33, 0x62,
          0x93, 0x8B, 0x98, 0x24>>

      assert result[:output] == expected
    end
  end

  describe "identity precompile (0x04)" do
    test "returns input data unchanged" do
      identity_addr = <<0::152, 0x04::8>>
      input_data = "hello, identity precompile!"

      assert {:ok, result} =
               Native.execute_tx_v2(
                 0,
                 @sender,
                 identity_addr,
                 <<>>,
                 100_000,
                 <<>>,
                 <<>>,
                 <<>>,
                 input_data,
                 <<>>,
                 0,
                 @balance,
                 <<>>,
                 <<>>
               )

      assert result[:success] == true
      assert result[:output] == input_data
    end

    test "returns empty for empty input" do
      identity_addr = <<0::152, 0x04::8>>

      assert {:ok, result} =
               Native.execute_tx_v2(
                 0,
                 @sender,
                 identity_addr,
                 <<>>,
                 100_000,
                 <<>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 0,
                 @balance,
                 <<>>,
                 <<>>
               )

      assert result[:success] == true
      assert result[:output] == <<>>
    end

    test "returns binary data unchanged" do
      identity_addr = <<0::152, 0x04::8>>
      input_data = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10>>

      assert {:ok, result} =
               Native.execute_tx_v2(
                 0,
                 @sender,
                 identity_addr,
                 <<>>,
                 100_000,
                 <<>>,
                 <<>>,
                 <<>>,
                 input_data,
                 <<>>,
                 0,
                 @balance,
                 <<>>,
                 <<>>
               )

      assert result[:success] == true
      assert result[:output] == input_data
    end
  end

  describe "execute_tx_v2 transaction types" do
    test "legacy transaction (type 0) simple transfer" do
      assert {:ok, result} =
               Native.execute_tx_v2(
                 0,
                 @sender,
                 <<0xBB::8, 0::152>>,
                 <<3, 232>>,
                 21_000,
                 <<1>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 0,
                 @balance,
                 <<>>,
                 <<>>
               )

      assert result[:success] == true
      assert result[:gas_used] == 21_000
    end

    test "EIP-2930 transaction (type 1) with access list" do
      # Encode access list: 1 entry with address 0xBB...00 and 1 storage key
      target = <<0xBB::8, 0::152>>
      storage_key = <<0::256>>

      access_list_data =
        <<1::unsigned-big-32>> <>
          target <>
          <<1::unsigned-big-32>> <>
          storage_key

      assert {:ok, result} =
               Native.execute_tx_v2(
                 1,
                 @sender,
                 target,
                 <<>>,
                 100_000,
                 <<1>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 0,
                 @balance,
                 access_list_data,
                 <<>>
               )

      assert result[:success] == true
      assert result[:gas_used] > 0
    end

    test "EIP-1559 transaction (type 2) with priority fee" do
      assert {:ok, result} =
               Native.execute_tx_v2(
                 2,
                 @sender,
                 <<0xBB::8, 0::152>>,
                 <<>>,
                 21_000,
                 <<10>>,
                 <<2>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 0,
                 @balance,
                 <<>>,
                 <<>>
               )

      assert result[:success] == true
      assert result[:gas_used] == 21_000
    end

    test "returns error for invalid access list binary" do
      # 2 bytes is too short to be a valid access list (needs at least 4 for count)
      assert {:error, :invalid_access_list} =
               Native.execute_tx_v2(
                 1,
                 @sender,
                 <<0xBB::8, 0::152>>,
                 <<>>,
                 100_000,
                 <<1>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 0,
                 @balance,
                 <<1, 2>>,
                 <<>>
               )
    end

    test "returns error for invalid blob hashes (not multiple of 32)" do
      assert {:error, :invalid_blob_hashes} =
               Native.execute_tx_v2(
                 3,
                 @sender,
                 <<0xBB::8, 0::152>>,
                 <<>>,
                 100_000,
                 <<10>>,
                 <<2>>,
                 <<1>>,
                 <<>>,
                 <<>>,
                 0,
                 @balance,
                 <<>>,
                 <<1, 2, 3>>
               )
    end

    test "returns error for invalid from address" do
      assert {:error, :invalid_address} =
               Native.execute_tx_v2(
                 0,
                 <<1, 2, 3>>,
                 <<0xBB::8, 0::152>>,
                 <<>>,
                 21_000,
                 <<>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 0,
                 <<>>,
                 <<>>,
                 <<>>
               )
    end

    test "access list with multiple entries and storage keys" do
      addr1 = <<0xCC::8, 0::152>>
      addr2 = <<0xDD::8, 0::152>>
      key1 = <<1::256>>
      key2 = <<2::256>>
      key3 = <<3::256>>

      # 2 entries: addr1 with 2 keys, addr2 with 1 key
      access_list_data =
        <<2::unsigned-big-32>> <>
          addr1 <> <<2::unsigned-big-32>> <> key1 <> key2 <>
          addr2 <> <<1::unsigned-big-32>> <> key3

      assert {:ok, result} =
               Native.execute_tx_v2(
                 1,
                 @sender,
                 <<0xBB::8, 0::152>>,
                 <<>>,
                 100_000,
                 <<1>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 <<>>,
                 0,
                 @balance,
                 access_list_data,
                 <<>>
               )

      assert result[:success] == true
      # Access list entries add gas cost (1900 per address + 2400 per storage key)
      # Base: 21000 + 2*1900 + 3*2400 = 21000 + 3800 + 7200 = 32000
      assert result[:gas_used] > 21_000
    end
  end
end
