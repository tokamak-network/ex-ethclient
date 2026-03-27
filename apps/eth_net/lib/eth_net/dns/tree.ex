defmodule EthNet.DNS.Tree do
  @moduledoc """
  Parsing and verification of EIP-1459 DNS discovery tree records.

  The DNS tree consists of four record types published as TXT records:

  - **Root**: `enrtree-root:v1 e=<enr-root> l=<link-root> seq=<seq> sig=<sig>`
  - **Branch**: `enrtree-branch:<hash1>,<hash2>,...`
  - **ENR leaf**: `enr:<base64url-encoded-enr>`
  - **Link**: `enrtree://<base32-pubkey>@<domain>`
  """

  alias EthCrypto.Hash

  @type root :: %{
          enr_root: String.t(),
          link_root: String.t(),
          seq: non_neg_integer(),
          signature: binary()
        }

  @type link :: %{pubkey: binary(), domain: String.t()}

  @doc """
  Parses a root TXT record.

  ## Example

      iex> EthNet.DNS.Tree.parse_root("enrtree-root:v1 e=HASH1 l=HASH2 seq=1 sig=BASE64SIG")
      {:ok, %{enr_root: "HASH1", link_root: "HASH2", seq: 1, signature: <<...>>}}
  """
  @spec parse_root(String.t()) :: {:ok, root()} | {:error, atom()}
  def parse_root("enrtree-root:v1 " <> rest) do
    with {:ok, fields} <- parse_root_fields(rest),
         {:ok, enr_root} <- Map.fetch(fields, "e"),
         {:ok, link_root} <- Map.fetch(fields, "l"),
         {:ok, seq_str} <- Map.fetch(fields, "seq"),
         {:ok, sig_str} <- Map.fetch(fields, "sig"),
         {seq, ""} <- Integer.parse(seq_str),
         {:ok, signature} <- base64url_decode(sig_str) do
      {:ok, %{enr_root: enr_root, link_root: link_root, seq: seq, signature: signature}}
    else
      _ -> {:error, :invalid_root}
    end
  end

  def parse_root(_), do: {:error, :invalid_root}

  @doc """
  Parses a branch TXT record, returning a list of child hashes.

  ## Example

      iex> EthNet.DNS.Tree.parse_branch("enrtree-branch:HASH1,HASH2,HASH3")
      {:ok, ["HASH1", "HASH2", "HASH3"]}
  """
  @spec parse_branch(String.t()) :: {:ok, [String.t()]} | {:error, atom()}
  def parse_branch("enrtree-branch:" <> rest) do
    hashes =
      rest
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {:ok, hashes}
  end

  def parse_branch(_), do: {:error, :invalid_branch}

  @doc """
  Parses an ENR leaf TXT record. Returns the decoded ENR binary.

  The record format is `enr:<base64url-encoded-enr>`.
  """
  @spec parse_enr(String.t()) :: {:ok, binary()} | {:error, atom()}
  def parse_enr("enr:" <> base64_data) do
    # ENR records use base64url encoding (no padding)
    case base64url_decode(base64_data) do
      {:ok, data} -> {:ok, data}
      :error -> {:error, :invalid_enr_encoding}
    end
  end

  def parse_enr(_), do: {:error, :invalid_enr}

  @doc """
  Parses a link TXT record.

  Format: `enrtree://<base32-pubkey>@<domain>`
  Returns the compressed public key (decoded from base32) and domain.
  """
  @spec parse_link(String.t()) :: {:ok, link()} | {:error, atom()}
  def parse_link("enrtree://" <> rest) do
    case String.split(rest, "@", parts: 2) do
      [pubkey_b32, domain] when pubkey_b32 != "" and domain != "" ->
        case base32_decode(pubkey_b32) do
          {:ok, pubkey} ->
            {:ok, %{pubkey: pubkey, domain: domain}}

          :error ->
            {:error, :invalid_link_pubkey}
        end

      _ ->
        {:error, :invalid_link}
    end
  end

  def parse_link(_), do: {:error, :invalid_link}

  @doc """
  Verifies the root record signature against the tree's public key.

  The signed content is: `enrtree-root:v1 e=<enr-root> l=<link-root> seq=<seq>`
  The signature is a secp256k1 signature over the keccak256 of the signed content.
  """
  @spec verify_root(root(), binary()) :: :ok | {:error, atom()}
  def verify_root(%{enr_root: enr_root, link_root: link_root, seq: seq, signature: sig}, pubkey)
      when is_binary(pubkey) do
    content = "enrtree-root:v1 e=#{enr_root} l=#{link_root} seq=#{seq}"
    content_hash = Hash.keccak256(content)

    with {:ok, {r, s, v}} <- decode_signature(sig),
         {:ok, recovered} <- EthCrypto.Signature.recover(content_hash, r, s, v) do
      if recovered == pubkey do
        :ok
      else
        {:error, :signature_mismatch}
      end
    else
      {:error, _} = err -> err
    end
  end

  @doc """
  Identifies the type of a DNS TXT record.

  Returns `:root`, `:branch`, `:enr`, `:link`, or `:unknown`.
  """
  @spec record_type(String.t()) :: :root | :branch | :enr | :link | :unknown
  def record_type("enrtree-root:v1 " <> _), do: :root
  def record_type("enrtree-branch:" <> _), do: :branch
  def record_type("enr:" <> _), do: :enr
  def record_type("enrtree://" <> _), do: :link
  def record_type(_), do: :unknown

  # --- Private helpers ---

  defp parse_root_fields(str) do
    fields =
      str
      |> String.split(" ", trim: true)
      |> Enum.reduce(%{}, fn token, acc ->
        case String.split(token, "=", parts: 2) do
          [key, value] -> Map.put(acc, key, value)
          _ -> acc
        end
      end)

    {:ok, fields}
  end

  defp base64url_decode(str) do
    # Add padding if needed
    padded =
      case rem(String.length(str), 4) do
        2 -> str <> "=="
        3 -> str <> "="
        _ -> str
      end

    # Convert URL-safe chars to standard base64
    standard =
      padded
      |> String.replace("-", "+")
      |> String.replace("_", "/")

    case Base.decode64(standard) do
      {:ok, data} -> {:ok, data}
      :error -> :error
    end
  end

  defp base32_decode(str) do
    # EIP-1459 uses base32 (RFC 4648) without padding
    upper = String.upcase(str)

    padded =
      case rem(String.length(upper), 8) do
        0 -> upper
        n -> upper <> String.duplicate("=", 8 - n)
      end

    case Base.decode32(padded) do
      {:ok, data} -> {:ok, data}
      :error -> :error
    end
  end

  defp decode_signature(sig) when byte_size(sig) == 65 do
    <<r::binary-size(32), s::binary-size(32), v>> = sig
    recovery_id = if v >= 27, do: v - 27, else: v

    if recovery_id in [0, 1] do
      {:ok, {r, s, recovery_id}}
    else
      {:error, :invalid_recovery_id}
    end
  end

  defp decode_signature(_), do: {:error, :invalid_signature_length}
end
