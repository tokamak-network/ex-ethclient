---
name: eip
description: Fetch and summarize an Ethereum Improvement Proposal by number. Use when implementing protocol features or researching EIP specifications.
user-invocable: true
allowed-tools: WebFetch, WebSearch, Read, Grep
argument-hint: <eip-number>
---

# EIP Lookup

Fetch and analyze EIP-$ARGUMENTS for implementation in ex_ethclient.

## Steps

1. Fetch the EIP specification from https://eips.ethereum.org/EIPS/eip-$ARGUMENTS
2. If the page is unavailable, search the web for "EIP-$ARGUMENTS ethereum specification"
3. Summarize:
   - **Status**: Draft / Review / Final / Stagnant
   - **Type**: Standards Track (Core/Networking/Interface/ERC) / Meta / Informational
   - **Summary**: One paragraph of what the EIP does
   - **Key Changes**: Bullet list of concrete protocol changes
   - **Parameters**: Any new constants, gas costs, or limits introduced
   - **Activation**: Which hard fork, block/slot number if applicable
4. Analyze impact on ex_ethclient:
   - Which umbrella apps are affected (eth_core, eth_crypto, eth_net, eth_storage, eth_rpc)
   - Which modules need changes
   - Estimated complexity (Low / Medium / High)
5. List related EIPs that may need to be implemented together
