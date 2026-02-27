defmodule EthNet.ForkIDTest do
  use ExUnit.Case, async: true

  alias EthNet.ForkID

  describe "compute/3 mainnet" do
    test "genesis (no forks passed)" do
      {fork_hash, fork_next} = ForkID.compute(:mainnet, 0, 0)
      assert byte_size(fork_hash) == 4
      # At genesis, fork_next should be the first fork (Homestead at 1_150_000)
      assert fork_next == 1_150_000
    end

    test "after homestead" do
      {hash_before, _} = ForkID.compute(:mainnet, 0, 0)
      {hash_after, fork_next} = ForkID.compute(:mainnet, 1_150_000, 0)

      # Hash should change after homestead activates
      refute hash_before == hash_after
      # Next fork is DAO fork
      assert fork_next == 1_920_000
    end

    test "after all block forks, before timestamp forks" do
      # gray_glacier is at 15_050_000, the last block fork
      {_fork_hash, fork_next} = ForkID.compute(:mainnet, 20_000_000, 0)
      # paris is the first time fork at block 15_537_394 but it's in block_forks...
      # Actually paris is in time_forks, so next would be a time fork
      # Since head_timestamp is 0, no time forks have passed
      # The remaining time forks start with paris at 15_537_394
      assert fork_next == 15_537_394
    end

    test "after all forks" do
      # Well past all known forks (block and timestamp)
      {_fork_hash, fork_next} = ForkID.compute(:mainnet, 20_000_000, 2_000_000_000)
      assert fork_next == 0
    end

    test "fork_hash is deterministic" do
      result1 = ForkID.compute(:mainnet, 1_150_000, 0)
      result2 = ForkID.compute(:mainnet, 1_150_000, 0)
      assert result1 == result2
    end
  end

  describe "encode/decode roundtrip" do
    test "roundtrip with non-zero fork_next" do
      fork_id = ForkID.compute(:mainnet, 0, 0)
      encoded = ForkID.encode(fork_id)
      decoded = ForkID.decode(encoded)
      assert decoded == fork_id
    end

    test "roundtrip with zero fork_next" do
      fork_id = ForkID.compute(:mainnet, 20_000_000, 2_000_000_000)
      encoded = ForkID.encode(fork_id)
      decoded = ForkID.decode(encoded)
      assert decoded == fork_id
    end
  end
end
