defmodule EthNet.DNS.TreeTest do
  use ExUnit.Case, async: true

  alias EthNet.DNS.Tree

  describe "parse_root/1" do
    test "parses a valid root record" do
      sig_bytes = :crypto.strong_rand_bytes(65)
      sig_b64 = Base.url_encode64(sig_bytes, padding: false)

      root = "enrtree-root:v1 e=JWXYDBPXYWG6FX3GMDIBFA6CJ4 l=C7HRFPF3BLGF3YR4DY5KX3SMBE seq=1 sig=#{sig_b64}"

      assert {:ok, parsed} = Tree.parse_root(root)
      assert parsed.enr_root == "JWXYDBPXYWG6FX3GMDIBFA6CJ4"
      assert parsed.link_root == "C7HRFPF3BLGF3YR4DY5KX3SMBE"
      assert parsed.seq == 1
      assert is_binary(parsed.signature)
    end

    test "parses root with higher sequence number" do
      sig_bytes = :crypto.strong_rand_bytes(65)
      sig_b64 = Base.url_encode64(sig_bytes, padding: false)

      root = "enrtree-root:v1 e=ABCD l=EFGH seq=42 sig=#{sig_b64}"

      assert {:ok, parsed} = Tree.parse_root(root)
      assert parsed.seq == 42
    end

    test "returns error for missing prefix" do
      assert {:error, :invalid_root} = Tree.parse_root("invalid root record")
    end

    test "returns error for missing fields" do
      assert {:error, :invalid_root} = Tree.parse_root("enrtree-root:v1 e=HASH1")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_root} = Tree.parse_root("")
    end
  end

  describe "parse_branch/1" do
    test "parses a branch with multiple hashes" do
      assert {:ok, hashes} = Tree.parse_branch("enrtree-branch:HASH1,HASH2,HASH3")
      assert hashes == ["HASH1", "HASH2", "HASH3"]
    end

    test "parses a branch with single hash" do
      assert {:ok, hashes} = Tree.parse_branch("enrtree-branch:SINGLE")
      assert hashes == ["SINGLE"]
    end

    test "parses an empty branch" do
      assert {:ok, hashes} = Tree.parse_branch("enrtree-branch:")
      assert hashes == []
    end

    test "returns error for invalid prefix" do
      assert {:error, :invalid_branch} = Tree.parse_branch("enr-branch:foo")
    end
  end

  describe "parse_enr/1" do
    test "parses a valid ENR record" do
      # Create a real ENR and encode it
      privkey = EthCrypto.Signature.generate_private_key()
      {:ok, enr} = EthNet.DiscV5.ENR.new(1, {192, 168, 1, 1}, 30303, 30303, privkey)
      enr_binary = EthNet.DiscV5.ENR.encode(enr)
      enr_b64 = Base.url_encode64(enr_binary, padding: false)

      assert {:ok, decoded_binary} = Tree.parse_enr("enr:#{enr_b64}")
      assert decoded_binary == enr_binary
    end

    test "returns error for invalid base64" do
      assert {:error, :invalid_enr_encoding} = Tree.parse_enr("enr:!!!invalid!!!")
    end

    test "returns error for missing prefix" do
      assert {:error, :invalid_enr} = Tree.parse_enr("not-enr:data")
    end
  end

  describe "parse_link/1" do
    test "parses a valid link record" do
      # Create a 33-byte compressed pubkey and base32 encode it
      pubkey = :crypto.strong_rand_bytes(33)
      pubkey_b32 = Base.encode32(pubkey, padding: false)

      link = "enrtree://#{pubkey_b32}@nodes.example.org"

      assert {:ok, parsed} = Tree.parse_link(link)
      assert parsed.pubkey == pubkey
      assert parsed.domain == "nodes.example.org"
    end

    test "returns error for missing domain" do
      assert {:error, :invalid_link} = Tree.parse_link("enrtree://PUBKEY@")
    end

    test "returns error for missing pubkey" do
      assert {:error, :invalid_link} = Tree.parse_link("enrtree://@domain.com")
    end

    test "returns error for invalid prefix" do
      assert {:error, :invalid_link} = Tree.parse_link("http://pubkey@domain.com")
    end
  end

  describe "record_type/1" do
    test "identifies root records" do
      assert Tree.record_type("enrtree-root:v1 e=A l=B seq=1 sig=C") == :root
    end

    test "identifies branch records" do
      assert Tree.record_type("enrtree-branch:HASH1,HASH2") == :branch
    end

    test "identifies ENR records" do
      assert Tree.record_type("enr:abc123") == :enr
    end

    test "identifies link records" do
      assert Tree.record_type("enrtree://KEY@domain.org") == :link
    end

    test "returns unknown for unrecognized records" do
      assert Tree.record_type("something else") == :unknown
    end
  end
end
