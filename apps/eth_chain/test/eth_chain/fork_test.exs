defmodule EthChain.ForkTest do
  use ExUnit.Case, async: true

  alias EthChain.Fork

  describe "active_fork/2" do
    test "returns frontier for genesis block" do
      assert Fork.active_fork(0, 0) == :frontier
    end

    test "returns homestead at block 1_150_000" do
      assert Fork.active_fork(1_150_000, 0) == :homestead
    end

    test "returns london at block 12_965_000" do
      assert Fork.active_fork(12_965_000, 0) == :london
    end

    test "returns paris (the merge) at block 15_537_394" do
      assert Fork.active_fork(15_537_394, 0) == :paris
    end

    test "returns shanghai at appropriate timestamp" do
      # Shanghai activated at timestamp 1_681_338_455
      assert Fork.active_fork(15_537_394, 1_681_338_455) == :shanghai
    end

    test "returns cancun at appropriate timestamp" do
      assert Fork.active_fork(15_537_394, 1_710_338_135) == :cancun
    end

    test "returns prague at appropriate timestamp" do
      assert Fork.active_fork(15_537_394, 1_740_434_112) == :prague
    end

    test "timestamp-based forks take priority over block-based" do
      # Even at a very high block number, if timestamp is low, no Shanghai
      assert Fork.active_fork(20_000_000, 0) == :paris
    end

    test "returns berlin before london activation" do
      assert Fork.active_fork(12_964_999, 0) == :berlin
    end
  end

  describe "active_fork/3 holesky" do
    test "returns paris at genesis for holesky" do
      assert Fork.active_fork(0, 0, :holesky) == :paris
    end

    test "returns shanghai at holesky activation timestamp" do
      assert Fork.active_fork(0, 1_696_000_704, :holesky) == :shanghai
    end

    test "returns cancun at holesky activation timestamp" do
      assert Fork.active_fork(0, 1_707_305_664, :holesky) == :cancun
    end

    test "returns prague at holesky activation timestamp" do
      assert Fork.active_fork(0, 1_740_434_112, :holesky) == :prague
    end

    test "returns paris before shanghai activation on holesky" do
      assert Fork.active_fork(0, 1_696_000_703, :holesky) == :paris
    end
  end

  describe "fork_schedule/1 holesky" do
    test "returns holesky fork schedule" do
      schedule = Fork.fork_schedule(:holesky)
      assert length(schedule) == 4

      forks = Enum.map(schedule, &elem(&1, 0))
      assert :paris in forks
      assert :shanghai in forks
      assert :cancun in forks
      assert :prague in forks
    end
  end

  describe "eip1559?/1" do
    test "false for pre-London forks" do
      refute Fork.eip1559?(:frontier)
      refute Fork.eip1559?(:homestead)
      refute Fork.eip1559?(:berlin)
    end

    test "true for London and later" do
      assert Fork.eip1559?(:london)
      assert Fork.eip1559?(:paris)
      assert Fork.eip1559?(:shanghai)
      assert Fork.eip1559?(:cancun)
      assert Fork.eip1559?(:prague)
    end
  end

  describe "withdrawals?/1" do
    test "false for pre-Shanghai forks" do
      refute Fork.withdrawals?(:london)
      refute Fork.withdrawals?(:paris)
    end

    test "true for Shanghai and later" do
      assert Fork.withdrawals?(:shanghai)
      assert Fork.withdrawals?(:cancun)
      assert Fork.withdrawals?(:prague)
    end
  end

  describe "blob_transactions?/1" do
    test "false for pre-Cancun forks" do
      refute Fork.blob_transactions?(:shanghai)
      refute Fork.blob_transactions?(:paris)
    end

    test "true for Cancun and later" do
      assert Fork.blob_transactions?(:cancun)
      assert Fork.blob_transactions?(:prague)
    end
  end
end
