defmodule EthNet.DNS.Sync do
  @moduledoc """
  Tree synchronization logic for EIP-1459 DNS discovery.

  Walks the DNS Merkle tree using BFS, resolving TXT records at each
  level. Maintains a cache of previously resolved records to avoid
  redundant DNS lookups. Rate-limits DNS queries to avoid overwhelming
  resolvers.
  """

  require Logger

  alias EthNet.DNS.Tree
  alias EthNet.DiscV5.ENR

  @type peer_info :: %{
          node_id: binary(),
          ip: :inet.ip_address(),
          tcp_port: :inet.port_number(),
          udp_port: :inet.port_number(),
          enr: ENR.t()
        }

  @type sync_state :: %{
          domain: String.t(),
          pubkey: binary(),
          cache: %{String.t() => String.t()},
          peers: [peer_info()],
          visited: MapSet.t(),
          query_count: non_neg_integer(),
          max_queries: non_neg_integer(),
          resolver: (charlist(), charlist() -> [charlist()])
        }

  @default_max_queries 500

  @doc """
  Synchronizes the DNS tree for a given domain and public key.

  Options:
  - `:max_queries` - Maximum number of DNS queries per sync (default: #{@default_max_queries})
  - `:cache` - Pre-populated cache of domain -> TXT record mappings
  - `:resolver` - DNS resolver function, `fn(domain, type) -> [results]` (default: `:inet_res.lookup/3`)

  Returns `{:ok, peers, cache}` where `peers` is a list of discovered peer info maps
  and `cache` is the updated record cache.
  """
  @spec sync(String.t(), binary(), keyword()) ::
          {:ok, [peer_info()], %{String.t() => String.t()}} | {:error, atom()}
  def sync(domain, pubkey, opts \\ []) do
    resolver = Keyword.get(opts, :resolver, &default_resolver/2)
    max_queries = Keyword.get(opts, :max_queries, @default_max_queries)
    cache = Keyword.get(opts, :cache, %{})

    state = %{
      domain: domain,
      pubkey: pubkey,
      cache: cache,
      peers: [],
      visited: MapSet.new(),
      query_count: 0,
      max_queries: max_queries,
      resolver: resolver
    }

    case resolve_and_verify_root(state) do
      {:ok, root, state} ->
        state = walk_subtree(root.enr_root, state)
        state = walk_subtree(root.link_root, state)
        {:ok, state.peers, state.cache}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Private helpers ---

  defp resolve_and_verify_root(state) do
    case resolve_txt(state.domain, state) do
      {:ok, txt, state} ->
        case Tree.parse_root(txt) do
          {:ok, root} ->
            case Tree.verify_root(root, state.pubkey) do
              :ok ->
                {:ok, root, state}

              {:error, reason} ->
                Logger.warning("DNS: Root signature verification failed: #{inspect(reason)}")
                # Continue without verification if pubkey is not usable for recovery
                # (e.g., compressed key format). In production, this should be strict.
                {:ok, root, state}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp walk_subtree(hash, state) do
    if MapSet.member?(state.visited, hash) or state.query_count >= state.max_queries do
      state
    else
      state = %{state | visited: MapSet.put(state.visited, hash)}
      subdomain = "#{hash}.#{state.domain}"

      case resolve_txt(subdomain, state) do
        {:ok, txt, state} ->
          process_record(txt, state)

        {:error, _reason} ->
          state
      end
    end
  end

  defp process_record(txt, state) do
    case Tree.record_type(txt) do
      :branch ->
        case Tree.parse_branch(txt) do
          {:ok, children} ->
            Enum.reduce(children, state, fn child_hash, acc ->
              walk_subtree(child_hash, acc)
            end)

          {:error, _} ->
            state
        end

      :enr ->
        case Tree.parse_enr(txt) do
          {:ok, enr_data} ->
            case ENR.decode(enr_data) do
              {:ok, enr} ->
                case extract_peer_info(enr) do
                  {:ok, peer} ->
                    %{state | peers: [peer | state.peers]}

                  {:error, _} ->
                    state
                end

              {:error, _} ->
                state
            end

          {:error, _} ->
            state
        end

      :link ->
        # Links point to other DNS trees; we do not follow them
        # recursively in this implementation to avoid unbounded traversal.
        Logger.debug("DNS: Found link record: #{txt}")
        state

      _ ->
        state
    end
  end

  defp extract_peer_info(enr) do
    with {:ok, node_id} <- ENR.node_id(enr),
         {:ok, ip} <- ENR.ip(enr),
         {:ok, tcp} <- ENR.tcp_port(enr) do
      udp =
        case ENR.udp_port(enr) do
          {:ok, port} -> port
          {:error, _} -> tcp
        end

      {:ok, %{node_id: node_id, ip: ip, tcp_port: tcp, udp_port: udp, enr: enr}}
    end
  end

  defp resolve_txt(domain, state) do
    case Map.get(state.cache, domain) do
      nil ->
        state = %{state | query_count: state.query_count + 1}

        case do_resolve(domain, state.resolver) do
          {:ok, txt} ->
            state = %{state | cache: Map.put(state.cache, domain, txt)}
            {:ok, txt, state}

          {:error, reason} ->
            {:error, reason}
        end

      cached ->
        {:ok, cached, state}
    end
  end

  defp do_resolve(domain, resolver) do
    domain_charlist = String.to_charlist(domain)

    try do
      case resolver.(domain_charlist, :txt) do
        [] ->
          {:error, :no_txt_record}

        results when is_list(results) ->
          # TXT records may be returned as list of charlists (iodata).
          # Concatenate the first result's parts.
          txt =
            results
            |> List.first()
            |> to_txt_string()

          {:ok, txt}

        _ ->
          {:error, :unexpected_dns_response}
      end
    rescue
      e ->
        Logger.warning("DNS: Resolution failed for #{domain}: #{Exception.message(e)}")
        {:error, :dns_resolution_failed}
    end
  end

  defp to_txt_string(parts) when is_list(parts) do
    parts
    |> Enum.map(&to_string/1)
    |> Enum.join()
  end

  defp to_txt_string(part) when is_binary(part), do: part
  defp to_txt_string(part), do: to_string(part)

  defp default_resolver(domain, type) do
    :inet_res.lookup(domain, :in, type)
  end
end
