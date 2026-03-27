defmodule EthChain.ConfigTest do
  use ExUnit.Case, async: true

  alias EthChain.Config

  describe "holesky/0" do
    test "returns holesky config with correct chain_id" do
      config = Config.holesky()
      assert config.network == :holesky
      assert config.chain_id == 17_000
      assert config.network_id == 17_000
    end

    test "returns non-empty bootnodes" do
      config = Config.holesky()
      assert length(config.bootnodes) > 0
    end
  end

  describe "from_env/1 with holesky" do
    test "returns holesky defaults when network is :holesky" do
      config = Config.from_env(network: :holesky)
      assert config.network == :holesky
      assert config.chain_id == 17_000
      assert config.network_id == 17_000
    end

    test "allows overriding holesky chain_id" do
      config = Config.from_env(network: :holesky, chain_id: 99)
      assert config.chain_id == 99
      assert config.network == :holesky
    end
  end
end
