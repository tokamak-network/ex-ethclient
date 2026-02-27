defmodule EthNet.Protocol.Eth68 do
  @moduledoc """
  eth/68 protocol messages. Currently implements Status (msg code 0x00 in eth sub-protocol,
  which maps to 0x10 after the P2P offset of 0x10).

  Status message: `rlp([version, networkId, td, bestHash, genesisHash, forkID])`
  """

  # eth sub-protocol message offset (after P2P base messages)
  @eth_offset 0x10

  @status_code @eth_offset + 0x00

  @eth_version 68

  @doc "Returns the eth/68 Status message code (with P2P offset)."
  def status_code, do: @status_code

  @doc "Encodes a Status message."
  @spec encode_status(map()) :: {non_neg_integer(), binary()}
  def encode_status(params) do
    %{
      network_id: network_id,
      total_difficulty: td,
      best_hash: best_hash,
      genesis_hash: genesis_hash,
      fork_id: fork_id
    } = params

    payload =
      ExRLP.encode([
        @eth_version,
        encode_integer(network_id),
        encode_integer(td),
        best_hash,
        genesis_hash,
        EthNet.ForkID.encode(fork_id)
      ])

    {@status_code, payload}
  end

  @doc "Decodes a Status message payload."
  @spec decode_status(binary()) :: {:ok, map()} | {:error, term()}
  def decode_status(payload) do
    case ExRLP.decode(payload) do
      [version, network_id, td, best_hash, genesis_hash, fork_id_rlp | _] ->
        {:ok,
         %{
           version: decode_integer(version),
           network_id: decode_integer(network_id),
           total_difficulty: decode_integer(td),
           best_hash: best_hash,
           genesis_hash: genesis_hash,
           fork_id: EthNet.ForkID.decode(fork_id_rlp)
         }}

      _ ->
        {:error, :invalid_status_message}
    end
  end

  @doc "Builds a Status message for mainnet with the given head info."
  def build_mainnet_status(head_block \\ 0, head_timestamp \\ 0) do
    genesis_hash = EthNet.Chain.genesis_hash(:mainnet)
    fork_id = EthNet.ForkID.compute(:mainnet, head_block, head_timestamp)

    encode_status(%{
      network_id: EthNet.Chain.network_id(:mainnet),
      total_difficulty: EthNet.Chain.terminal_td(:mainnet),
      best_hash: genesis_hash,
      genesis_hash: genesis_hash,
      fork_id: fork_id
    })
  end

  @doc "Returns true if the message code is an eth/68 message."
  def eth_message?(code), do: code >= @eth_offset

  defp encode_integer(0), do: <<>>
  defp encode_integer(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)

  defp decode_integer(<<>>), do: 0
  defp decode_integer(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)
end
