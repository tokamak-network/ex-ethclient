defmodule EthNet.ChainTest do
  use ExUnit.Case, async: true

  alias EthNet.Chain

  describe "Sepolia constants" do
    test "genesis hash is 32 bytes and matches known value" do
      hash = Chain.genesis_hash(:sepolia)
      assert byte_size(hash) == 32

      expected =
        Base.decode16!(
          "25A5CC106EEA7138ACAB33231D7160D69CB777EE0C2C553FCDDF5138993E6DD9",
          case: :upper
        )

      assert hash == expected
    end

    test "network_id is 11155111" do
      assert Chain.network_id(:sepolia) == 11_155_111
    end

    test "terminal_td matches Sepolia value" do
      assert Chain.terminal_td(:sepolia) == 17_000_000_000_000_000
    end

    test "bootnodes are valid enode URLs" do
      bootnodes = Chain.bootnodes(:sepolia)
      assert length(bootnodes) == 2

      Enum.each(bootnodes, fn node ->
        assert String.starts_with?(node, "enode://")
        assert String.contains?(node, "@")
        assert String.contains?(node, ":30303")
      end)
    end

    test "block_forks is empty (Sepolia launched post-merge)" do
      assert Chain.block_forks(:sepolia) == []
    end

    test "time_forks includes Shanghai and Cancun" do
      forks = Chain.time_forks(:sepolia)
      fork_names = Enum.map(forks, &elem(&1, 0))
      assert :shanghai in fork_names
      assert :cancun in fork_names
    end

    test "all_fork_values returns correct structure" do
      {block_values, time_values} = Chain.all_fork_values(:sepolia)
      assert block_values == []
      assert length(time_values) == 2
      assert 1_677_557_088 in time_values
      assert 1_706_655_072 in time_values
    end
  end

  describe "mainnet constants" do
    test "genesis hash is 32 bytes" do
      assert byte_size(Chain.genesis_hash(:mainnet)) == 32
    end

    test "network_id is 1" do
      assert Chain.network_id(:mainnet) == 1
    end

    test "bootnodes is non-empty" do
      assert length(Chain.bootnodes(:mainnet)) > 0
    end
  end
end
