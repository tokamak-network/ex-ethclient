defmodule EthNet.DNS.SyncTest do
  use ExUnit.Case, async: true

  alias EthNet.DNS.Sync
  alias EthNet.DiscV5.ENR

  # Helper to build a mock DNS resolver from a map of domain -> TXT record
  defp mock_resolver(records) do
    fn domain_charlist, :txt ->
      domain = to_string(domain_charlist)

      case Map.get(records, domain) do
        nil -> []
        txt -> [[String.to_charlist(txt)]]
      end
    end
  end

  # Helper to create an ENR TXT record for a test peer
  defp make_enr_txt(ip, tcp_port, udp_port) do
    privkey = EthCrypto.Signature.generate_private_key()
    {:ok, enr} = ENR.new(1, ip, udp_port, tcp_port, privkey)
    enr_binary = ENR.encode(enr)
    "enr:" <> Base.url_encode64(enr_binary, padding: false)
  end

  defp make_root_txt(enr_root, link_root, seq) do
    # We use a dummy signature since verify_root gracefully continues
    sig = :crypto.strong_rand_bytes(65)
    sig_b64 = Base.url_encode64(sig, padding: false)
    "enrtree-root:v1 e=#{enr_root} l=#{link_root} seq=#{seq} sig=#{sig_b64}"
  end

  describe "sync/3" do
    test "discovers peers from a simple tree" do
      enr_txt = make_enr_txt({192, 168, 1, 1}, 30303, 30303)

      records = %{
        "example.org" => make_root_txt("LEAF1", "EMPTY", 1),
        "LEAF1.example.org" => enr_txt,
        "EMPTY.example.org" => "enrtree-branch:"
      }

      resolver = mock_resolver(records)
      pubkey = :crypto.strong_rand_bytes(64)

      assert {:ok, peers, _cache} =
               Sync.sync("example.org", pubkey, resolver: resolver)

      assert length(peers) == 1
      [peer] = peers
      assert peer.ip == {192, 168, 1, 1}
      assert peer.tcp_port == 30303
      assert is_binary(peer.node_id)
      assert byte_size(peer.node_id) == 32
    end

    test "discovers peers through branch nodes" do
      enr1 = make_enr_txt({10, 0, 0, 1}, 30303, 30303)
      enr2 = make_enr_txt({10, 0, 0, 2}, 30304, 30304)

      records = %{
        "example.org" => make_root_txt("BRANCH1", "EMPTY", 1),
        "BRANCH1.example.org" => "enrtree-branch:LEAF1,LEAF2",
        "LEAF1.example.org" => enr1,
        "LEAF2.example.org" => enr2,
        "EMPTY.example.org" => "enrtree-branch:"
      }

      resolver = mock_resolver(records)
      pubkey = :crypto.strong_rand_bytes(64)

      assert {:ok, peers, _cache} =
               Sync.sync("example.org", pubkey, resolver: resolver)

      assert length(peers) == 2

      ips = Enum.map(peers, & &1.ip) |> Enum.sort()
      assert {10, 0, 0, 1} in ips
      assert {10, 0, 0, 2} in ips
    end

    test "handles nested branches" do
      enr = make_enr_txt({172, 16, 0, 1}, 9000, 9000)

      records = %{
        "example.org" => make_root_txt("B1", "EMPTY", 1),
        "B1.example.org" => "enrtree-branch:B2",
        "B2.example.org" => "enrtree-branch:LEAF",
        "LEAF.example.org" => enr,
        "EMPTY.example.org" => "enrtree-branch:"
      }

      resolver = mock_resolver(records)
      pubkey = :crypto.strong_rand_bytes(64)

      assert {:ok, peers, _cache} =
               Sync.sync("example.org", pubkey, resolver: resolver)

      assert length(peers) == 1
      assert hd(peers).ip == {172, 16, 0, 1}
    end

    test "handles missing DNS records gracefully" do
      records = %{
        "example.org" => make_root_txt("MISSING", "ALSOMISSING", 1)
      }

      resolver = mock_resolver(records)
      pubkey = :crypto.strong_rand_bytes(64)

      assert {:ok, peers, _cache} =
               Sync.sync("example.org", pubkey, resolver: resolver)

      assert peers == []
    end

    test "returns error when root record is missing" do
      resolver = mock_resolver(%{})
      pubkey = :crypto.strong_rand_bytes(64)

      assert {:error, :no_txt_record} =
               Sync.sync("example.org", pubkey, resolver: resolver)
    end

    test "uses cache to avoid redundant lookups" do
      enr = make_enr_txt({10, 0, 0, 5}, 30303, 30303)

      # Pre-populate cache with the leaf record
      cache = %{
        "LEAF.example.org" => enr
      }

      # The resolver should only be called for uncached domains
      call_count = :counters.new(1, [:atomics])

      resolver = fn domain_charlist, :txt ->
        :counters.add(call_count, 1, 1)
        domain = to_string(domain_charlist)

        records = %{
          "example.org" => make_root_txt("LEAF", "EMPTY", 1),
          "EMPTY.example.org" => "enrtree-branch:"
        }

        case Map.get(records, domain) do
          nil -> []
          txt -> [[String.to_charlist(txt)]]
        end
      end

      pubkey = :crypto.strong_rand_bytes(64)

      assert {:ok, peers, new_cache} =
               Sync.sync("example.org", pubkey,
                 resolver: resolver,
                 cache: cache
               )

      assert length(peers) == 1
      # The LEAF record was cached, so it should not trigger a DNS query
      # Only root + EMPTY should be resolved = 2 queries
      assert :counters.get(call_count, 1) == 2
      # Cache should still contain the leaf
      assert Map.has_key?(new_cache, "LEAF.example.org")
    end

    test "respects max_queries limit" do
      # Build a wide branch with many leaves
      leaf_names = Enum.map(1..20, &"L#{&1}")
      branch_txt = "enrtree-branch:" <> Enum.join(leaf_names, ",")

      records =
        %{
          "example.org" => make_root_txt("WIDE", "EMPTY", 1),
          "WIDE.example.org" => branch_txt,
          "EMPTY.example.org" => "enrtree-branch:"
        }
        |> Map.merge(
          Enum.into(leaf_names, %{}, fn name ->
            {name <> ".example.org", make_enr_txt({10, 0, 0, 1}, 30303, 30303)}
          end)
        )

      resolver = mock_resolver(records)
      pubkey = :crypto.strong_rand_bytes(64)

      # Set max_queries very low so we stop early
      assert {:ok, peers, _cache} =
               Sync.sync("example.org", pubkey,
                 resolver: resolver,
                 max_queries: 5
               )

      # Should have fewer peers than the 20 available
      assert length(peers) < 20
    end

    test "handles invalid ENR records gracefully" do
      records = %{
        "example.org" => make_root_txt("BAD", "EMPTY", 1),
        "BAD.example.org" => "enr:" <> Base.url_encode64("not-valid-rlp", padding: false),
        "EMPTY.example.org" => "enrtree-branch:"
      }

      resolver = mock_resolver(records)
      pubkey = :crypto.strong_rand_bytes(64)

      assert {:ok, peers, _cache} =
               Sync.sync("example.org", pubkey, resolver: resolver)

      assert peers == []
    end
  end
end
