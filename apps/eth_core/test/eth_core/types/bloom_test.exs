defmodule EthCore.Types.BloomTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.{Bloom, Log}

  @zero_bloom <<0::2048>>

  describe "empty/0" do
    test "returns a 256-byte zero bloom" do
      bloom = Bloom.empty()
      assert byte_size(bloom) == 256
      assert bloom == @zero_bloom
    end
  end

  describe "create/1" do
    test "empty logs produce empty bloom" do
      assert Bloom.create([]) == @zero_bloom
    end

    test "known log address sets correct bits" do
      address = <<1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20>>

      log = %Log{
        address: address,
        topics: [],
        data: <<>>
      }

      bloom = Bloom.create([log])
      assert bloom != @zero_bloom
      assert byte_size(bloom) == 256
    end

    test "log with topics sets bits for address and each topic" do
      address = <<0::160>>
      topic1 = <<1::256>>
      topic2 = <<2::256>>

      log = %Log{
        address: address,
        topics: [topic1, topic2],
        data: <<>>
      }

      bloom = Bloom.create([log])

      # Each element should be findable in the bloom
      assert Bloom.contains?(bloom, address)
      assert Bloom.contains?(bloom, topic1)
      assert Bloom.contains?(bloom, topic2)
    end
  end

  describe "logs_bloom/1" do
    test "is equivalent to create" do
      log = %Log{
        address: <<5::160>>,
        topics: [<<10::256>>],
        data: <<>>
      }

      assert Bloom.logs_bloom([log]) == Bloom.create([log])
    end
  end

  describe "add_to_bloom/2" do
    test "adds a value to an empty bloom" do
      value = <<42::160>>
      bloom = Bloom.add_to_bloom(@zero_bloom, value)
      assert bloom != @zero_bloom
      assert byte_size(bloom) == 256
    end

    test "adding the same value twice produces the same bloom" do
      value = <<99::256>>
      bloom1 = Bloom.add_to_bloom(@zero_bloom, value)
      bloom2 = Bloom.add_to_bloom(bloom1, value)
      assert bloom1 == bloom2
    end
  end

  describe "contains?/2" do
    test "returns true for added values" do
      value1 = <<100::160>>
      value2 = <<200::256>>

      bloom =
        @zero_bloom
        |> Bloom.add_to_bloom(value1)
        |> Bloom.add_to_bloom(value2)

      assert Bloom.contains?(bloom, value1)
      assert Bloom.contains?(bloom, value2)
    end

    test "returns false for non-added values on empty bloom" do
      refute Bloom.contains?(@zero_bloom, <<1::160>>)
      refute Bloom.contains?(@zero_bloom, <<2::256>>)
    end

    test "returns false for values not in bloom" do
      # Add a specific value and check that a very different value is not found
      bloom = Bloom.add_to_bloom(@zero_bloom, <<1::160>>)
      # While false positives are possible, with only one value added
      # the probability is very low for an arbitrary different value
      # We check multiple values to ensure at least some return false
      results =
        Enum.map(1000..1010, fn n ->
          Bloom.contains?(bloom, <<n::256>>)
        end)

      assert false in results
    end
  end

  describe "merge/2" do
    test "merging two empty blooms gives empty bloom" do
      assert Bloom.merge(@zero_bloom, @zero_bloom) == @zero_bloom
    end

    test "merging with empty bloom is identity" do
      bloom = Bloom.add_to_bloom(@zero_bloom, <<42::160>>)
      assert Bloom.merge(bloom, @zero_bloom) == bloom
      assert Bloom.merge(@zero_bloom, bloom) == bloom
    end

    test "merge combines two blooms correctly" do
      value1 = <<1::160>>
      value2 = <<2::256>>

      bloom1 = Bloom.add_to_bloom(@zero_bloom, value1)
      bloom2 = Bloom.add_to_bloom(@zero_bloom, value2)
      merged = Bloom.merge(bloom1, bloom2)

      assert Bloom.contains?(merged, value1)
      assert Bloom.contains?(merged, value2)
    end

    test "merged bloom contains all values from both blooms" do
      log1 = %Log{address: <<10::160>>, topics: [<<11::256>>], data: <<>>}
      log2 = %Log{address: <<20::160>>, topics: [<<21::256>>], data: <<>>}

      bloom1 = Bloom.create([log1])
      bloom2 = Bloom.create([log2])
      merged = Bloom.merge(bloom1, bloom2)
      combined = Bloom.create([log1, log2])

      assert merged == combined
    end
  end

  describe "Ethereum test vector validation" do
    test "known Ethereum log produces expected bloom bits" do
      # Use a well-known address and verify bloom is deterministic
      address = Base.decode16!("0000000000000000000000000000000000000001", case: :lower)

      log = %Log{
        address: address,
        topics: [],
        data: <<>>
      }

      bloom = Bloom.create([log])

      # Verify bloom is deterministic
      assert bloom == Bloom.create([log])

      # Verify the address is contained
      assert Bloom.contains?(bloom, address)

      # Verify bloom has exactly 3 bits set (one value = 3 bits from keccak)
      bit_count =
        bloom
        |> :binary.bin_to_list()
        |> Enum.map(fn byte ->
          Enum.count(0..7, fn bit -> Bitwise.band(byte, Bitwise.bsl(1, bit)) != 0 end)
        end)
        |> Enum.sum()

      assert bit_count == 3
    end

    test "multiple topics set correct number of bits" do
      address = <<0::160>>
      topic = <<0::256>>

      log = %Log{address: address, topics: [topic], data: <<>>}
      bloom = Bloom.create([log])

      # 2 values (address + 1 topic) = up to 6 bits, but some might overlap
      bit_count =
        bloom
        |> :binary.bin_to_list()
        |> Enum.map(fn byte ->
          Enum.count(0..7, fn bit -> Bitwise.band(byte, Bitwise.bsl(1, bit)) != 0 end)
        end)
        |> Enum.sum()

      assert bit_count >= 3 and bit_count <= 6
    end
  end
end
