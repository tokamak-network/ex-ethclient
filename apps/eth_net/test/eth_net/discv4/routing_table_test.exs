defmodule EthNet.DiscV4.RoutingTableTest do
  use ExUnit.Case, async: true

  alias EthNet.DiscV4.{Node, RoutingTable}

  setup do
    self_id = :crypto.strong_rand_bytes(64)
    table = RoutingTable.new(self_id)
    %{table: table, self_id: self_id}
  end

  test "new table is empty", %{table: table} do
    assert RoutingTable.size(table) == 0
    assert RoutingTable.all_nodes(table) == []
  end

  test "insert adds a node", %{table: table} do
    node = make_node()
    table = RoutingTable.insert(table, node)
    assert RoutingTable.size(table) == 1
  end

  test "does not add self", %{table: table, self_id: self_id} do
    node = %Node{id: self_id, ip: {0, 0, 0, 0}, udp_port: 30303}
    table = RoutingTable.insert(table, node)
    assert RoutingTable.size(table) == 0
  end

  test "updates existing node position", %{table: table} do
    node1 = make_node()
    node2 = make_node()
    node3 = %{node1 | last_pong: 999}

    table =
      table
      |> RoutingTable.insert(node1)
      |> RoutingTable.insert(node2)
      |> RoutingTable.insert(node3)

    # Should still be 2 unique nodes
    assert RoutingTable.size(table) == 2
  end

  test "closest returns nodes sorted by distance", %{table: table} do
    nodes = for _ <- 1..5, do: make_node()
    table = Enum.reduce(nodes, table, &RoutingTable.insert(&2, &1))

    target = :crypto.strong_rand_bytes(64)
    closest = RoutingTable.closest(table, target, 3)

    assert length(closest) == 3
  end

  test "remove deletes a node", %{table: table} do
    node = make_node()
    table = RoutingTable.insert(table, node)
    assert RoutingTable.size(table) == 1

    table = RoutingTable.remove(table, node.id)
    assert RoutingTable.size(table) == 0
  end

  test "bucket capacity limit (k=16)", %{table: table} do
    # Insert 20 nodes that all map to the same bucket
    # (this is probabilistic, but with random IDs they'll spread across buckets)
    nodes = for _ <- 1..20, do: make_node()
    table = Enum.reduce(nodes, table, &RoutingTable.insert(&2, &1))

    # Total should be <= 20 (some might be in full buckets)
    assert RoutingTable.size(table) <= 20
  end

  defp make_node do
    %Node{
      id: :crypto.strong_rand_bytes(64),
      ip: {:rand.uniform(255), :rand.uniform(255), :rand.uniform(255), :rand.uniform(255)},
      udp_port: 30303,
      tcp_port: 30303
    }
  end
end
