defmodule EthNet.Peer.ScorerTest do
  use ExUnit.Case, async: true

  alias EthNet.Peer.Scorer

  setup do
    {:ok, pid} = Scorer.start_link(name: :"scorer_#{:erlang.unique_integer()}")
    {:ok, scorer: pid}
  end

  describe "scoring" do
    test "unknown peer returns base score", %{scorer: scorer} do
      assert Scorer.get_score(scorer, "peer_a") == 50.0
    end

    test "successful responses increase score", %{scorer: scorer} do
      Scorer.record_success(scorer, "peer_a", 50)
      Scorer.record_success(scorer, "peer_a", 50)
      # Allow cast to process
      :sys.get_state(scorer)
      score = Scorer.get_score(scorer, "peer_a")
      assert score > 50.0
    end

    test "failures decrease score", %{scorer: scorer} do
      Scorer.record_failure(scorer, "peer_a")
      Scorer.record_failure(scorer, "peer_a")
      :sys.get_state(scorer)
      score = Scorer.get_score(scorer, "peer_a")
      assert score < 50.0
    end

    test "timeouts decrease score significantly", %{scorer: scorer} do
      Scorer.record_timeout(scorer, "peer_a")
      :sys.get_state(scorer)
      score = Scorer.get_score(scorer, "peer_a")
      assert score < 50.0
    end

    test "get_best_peers returns peers sorted by score", %{scorer: scorer} do
      Scorer.record_success(scorer, "good_peer", 10)
      Scorer.record_success(scorer, "good_peer", 10)
      Scorer.record_failure(scorer, "bad_peer")
      Scorer.record_failure(scorer, "bad_peer")
      :sys.get_state(scorer)

      best = Scorer.get_best_peers(scorer, 2)
      assert length(best) == 2
      [{first_id, _}, {second_id, _}] = best
      assert first_id == "good_peer"
      assert second_id == "bad_peer"
    end

    test "get_bad_peers returns peers below threshold", %{scorer: scorer} do
      # Drive score very low
      for _ <- 1..20, do: Scorer.record_timeout(scorer, "terrible_peer")
      :sys.get_state(scorer)

      bad = Scorer.get_bad_peers(scorer)
      assert "terrible_peer" in bad
    end

    test "remove_peer deletes peer data", %{scorer: scorer} do
      Scorer.record_success(scorer, "peer_a", 50)
      :sys.get_state(scorer)
      assert Scorer.get_score(scorer, "peer_a") != 50.0

      Scorer.remove_peer(scorer, "peer_a")
      :sys.get_state(scorer)
      assert Scorer.get_score(scorer, "peer_a") == 50.0
    end
  end

  describe "rate limiting" do
    test "allows messages within rate limit", %{scorer: scorer} do
      assert :ok == Scorer.check_rate_limit(scorer, "peer_a")
    end

    test "blocks messages exceeding rate limit", %{scorer: scorer} do
      # Exhaust the rate limit (100 per second)
      for _ <- 1..100, do: assert(:ok == Scorer.check_rate_limit(scorer, "fast_peer"))

      assert {:error, :rate_limited} == Scorer.check_rate_limit(scorer, "fast_peer")
    end
  end
end
