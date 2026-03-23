defmodule EthVm.StateLoaderTest do
  use ExUnit.Case, async: true

  alias EthVm.StateLoader

  @from_addr :crypto.strong_rand_bytes(20)
  @to_addr :crypto.strong_rand_bytes(20)

  describe "collect_addresses/1" do
    test "collects from and to addresses" do
      tx_info = %{from: @from_addr, to: @to_addr}
      addresses = StateLoader.collect_addresses(tx_info)

      assert MapSet.member?(addresses, @from_addr)
      assert MapSet.member?(addresses, @to_addr)
      assert MapSet.size(addresses) == 2
    end

    test "handles nil to address for contract creation" do
      tx_info = %{from: @from_addr, to: nil}
      addresses = StateLoader.collect_addresses(tx_info)

      assert MapSet.member?(addresses, @from_addr)
      assert MapSet.size(addresses) == 1
    end

    test "handles missing from and to" do
      addresses = StateLoader.collect_addresses(%{})
      assert MapSet.size(addresses) == 0
    end

    test "collects access list addresses as tuples" do
      access_addr1 = :crypto.strong_rand_bytes(20)
      access_addr2 = :crypto.strong_rand_bytes(20)

      tx_info = %{
        from: @from_addr,
        to: @to_addr,
        access_list: [
          {access_addr1, []},
          {access_addr2, [<<1::256>>]}
        ]
      }

      addresses = StateLoader.collect_addresses(tx_info)

      assert MapSet.member?(addresses, @from_addr)
      assert MapSet.member?(addresses, @to_addr)
      assert MapSet.member?(addresses, access_addr1)
      assert MapSet.member?(addresses, access_addr2)
      assert MapSet.size(addresses) == 4
    end

    test "collects access list addresses as maps" do
      access_addr = :crypto.strong_rand_bytes(20)

      tx_info = %{
        from: @from_addr,
        to: @to_addr,
        access_list: [%{address: access_addr}]
      }

      addresses = StateLoader.collect_addresses(tx_info)
      assert MapSet.member?(addresses, access_addr)
    end

    test "deduplicates addresses" do
      tx_info = %{from: @from_addr, to: @from_addr}
      addresses = StateLoader.collect_addresses(tx_info)

      assert MapSet.size(addresses) == 1
    end
  end

  describe "serialize_state/1" do
    test "serializes empty state" do
      binary = StateLoader.serialize_state(%{})

      assert <<0::unsigned-big-32>> = binary
    end

    test "serializes a single account with no code and no storage" do
      address = <<1::160>>

      accounts = %{
        address => %{nonce: 5, balance: 1000, code: <<>>, storage: %{}}
      }

      binary = StateLoader.serialize_state(accounts)

      # Parse: 4 bytes num_accounts
      <<1::unsigned-big-32, rest::binary>> = binary
      # 20 bytes address
      <<^address::binary-size(20), rest::binary>> = rest
      # 8 bytes nonce
      <<5::unsigned-big-64, rest::binary>> = rest
      # 32 bytes balance
      <<balance_val::unsigned-big-256, rest::binary>> = rest
      assert balance_val == 1000
      # 4 bytes code length = 0
      <<0::unsigned-big-32, rest::binary>> = rest
      # 4 bytes num_storage_slots = 0
      <<0::unsigned-big-32>> = rest
    end

    test "serializes account with code" do
      address = <<2::160>>
      code = <<0x60, 0x00, 0x60, 0x00, 0xF3>>

      accounts = %{
        address => %{nonce: 0, balance: 0, code: code, storage: %{}}
      }

      binary = StateLoader.serialize_state(accounts)

      <<1::unsigned-big-32, rest::binary>> = binary
      <<_addr::binary-size(20), rest::binary>> = rest
      <<0::unsigned-big-64, rest::binary>> = rest
      <<0::unsigned-big-256, rest::binary>> = rest
      <<5::unsigned-big-32, rest::binary>> = rest
      <<^code::binary-size(5), rest::binary>> = rest
      <<0::unsigned-big-32>> = rest
    end

    test "serializes account with storage slots" do
      address = <<3::160>>
      slot_key = <<1::256>>
      slot_val = <<42::256>>

      accounts = %{
        address => %{
          nonce: 1,
          balance: 500,
          code: <<>>,
          storage: %{slot_key => slot_val}
        }
      }

      binary = StateLoader.serialize_state(accounts)

      <<1::unsigned-big-32, rest::binary>> = binary
      <<_addr::binary-size(20), rest::binary>> = rest
      <<1::unsigned-big-64, rest::binary>> = rest
      <<500::unsigned-big-256, rest::binary>> = rest
      <<0::unsigned-big-32, rest::binary>> = rest
      <<1::unsigned-big-32, rest::binary>> = rest
      <<^slot_key::binary-size(32), rest::binary>> = rest
      <<^slot_val::binary-size(32)>> = rest
    end

    test "serializes multiple accounts" do
      addr1 = <<1::160>>
      addr2 = <<2::160>>

      accounts = %{
        addr1 => %{nonce: 0, balance: 100, code: <<>>, storage: %{}},
        addr2 => %{nonce: 1, balance: 200, code: <<>>, storage: %{}}
      }

      binary = StateLoader.serialize_state(accounts)

      <<2::unsigned-big-32, _rest::binary>> = binary
      # Both accounts should be present (68 bytes each: 20 + 8 + 32 + 4 + 4)
      assert byte_size(binary) == 4 + 2 * (20 + 8 + 32 + 4 + 4)
    end

    test "serializes large balance correctly" do
      address = <<4::160>>
      # 10 ETH in wei
      balance = 10_000_000_000_000_000_000

      accounts = %{
        address => %{nonce: 0, balance: balance, code: <<>>, storage: %{}}
      }

      binary = StateLoader.serialize_state(accounts)

      <<1::unsigned-big-32, _addr::binary-size(20), _nonce::binary-size(8),
        balance_val::unsigned-big-256, _rest::binary>> = binary

      assert balance_val == balance
    end
  end
end
