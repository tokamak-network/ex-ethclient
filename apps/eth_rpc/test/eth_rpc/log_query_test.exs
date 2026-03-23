defmodule EthRpc.LogQueryTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.Log
  alias EthRpc.LogQuery

  describe "matches_filter?/2" do
    test "matches log with matching address" do
      log = %Log{address: <<1::160>>, topics: [], data: <<>>}
      filter = %{address: <<1::160>>}
      assert LogQuery.matches_filter?(log, filter) == true
    end

    test "rejects log with non-matching address" do
      log = %Log{address: <<1::160>>, topics: [], data: <<>>}
      filter = %{address: <<2::160>>}
      assert LogQuery.matches_filter?(log, filter) == false
    end

    test "matches log when address is a list containing the log address" do
      log = %Log{address: <<1::160>>, topics: [], data: <<>>}
      filter = %{address: [<<1::160>>, <<2::160>>]}
      assert LogQuery.matches_filter?(log, filter) == true
    end

    test "matches log when no address filter specified" do
      log = %Log{address: <<1::160>>, topics: [], data: <<>>}
      filter = %{}
      assert LogQuery.matches_filter?(log, filter) == true
    end

    test "matches log with matching topic" do
      topic = <<42::256>>
      log = %Log{address: <<1::160>>, topics: [topic], data: <<>>}
      filter = %{topics: [topic]}
      assert LogQuery.matches_filter?(log, filter) == true
    end

    test "rejects log with non-matching topic" do
      log = %Log{address: <<1::160>>, topics: [<<1::256>>], data: <<>>}
      filter = %{topics: [<<2::256>>]}
      assert LogQuery.matches_filter?(log, filter) == false
    end
  end

  describe "topics_match?/2" do
    test "empty filter matches any topics" do
      assert LogQuery.topics_match?([<<1::256>>], []) == true
    end

    test "nil in filter acts as wildcard" do
      assert LogQuery.topics_match?([<<1::256>>, <<2::256>>], [nil, <<2::256>>]) == true
    end

    test "exact binary match" do
      topic = <<42::256>>
      assert LogQuery.topics_match?([topic], [topic]) == true
    end

    test "exact binary mismatch" do
      assert LogQuery.topics_match?([<<1::256>>], [<<2::256>>]) == false
    end

    test "list in filter position acts as OR" do
      topic_a = <<1::256>>
      topic_b = <<2::256>>
      topic_c = <<3::256>>

      assert LogQuery.topics_match?([topic_b], [[topic_a, topic_b]]) == true
      assert LogQuery.topics_match?([topic_c], [[topic_a, topic_b]]) == false
    end

    test "filter longer than log topics returns false" do
      assert LogQuery.topics_match?([], [<<1::256>>]) == false
    end

    test "filter longer than log topics with wildcards returns true" do
      assert LogQuery.topics_match?([], [nil]) == true
    end

    test "multiple topics with mixed wildcards and exact matches" do
      topic1 = <<1::256>>
      topic2 = <<2::256>>
      topic3 = <<3::256>>

      log_topics = [topic1, topic2, topic3]
      filter_topics = [topic1, nil, topic3]
      assert LogQuery.topics_match?(log_topics, filter_topics) == true
    end
  end

  describe "query_logs/2 with no store" do
    test "returns empty list when store is unavailable" do
      assert {:ok, []} = LogQuery.query_logs(%{from_block: 0, to_block: 0}, :nonexistent)
    end
  end
end
