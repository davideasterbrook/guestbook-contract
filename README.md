# Multi-Chain Guestbook

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A pure event-based, multi-chain guestbook using LayerZero v2 for cross-chain messaging. **Zero on-chain storage** for ~95% gas savings.

## Deployments
# TODO update
| Chain | Network | Contract Address | Explorer |
|-------|---------|------------------|----------|
| Ethereum | Mainnet | `0xEf1ABFcD0413CA9eFcfFAC2079257A1572058Ade` | [View](https://etherscan.io/address/0xEf1ABFcD0413CA9eFcfFAC2079257A1572058Ade) |
| Base | Mainnet | `0xe14942066fE9d1cbFa8a343C7A8B7d38F6B9B0f5` | [View](https://basescan.org/address/0xe14942066fE9d1cbFa8a343C7A8B7d38F6B9B0f5) |
| Arbitrum | Mainnet | `0xe14942066fE9d1cbFa8a343C7A8B7d38F6B9B0f5` | [View](https://arbiscan.io/address/0xe14942066fE9d1cbFa8a343C7A8B7d38F6B9B0f5) |
| Ethereum | Sepolia | `0x7144AE87f605dB2Aa94Fd32cF3F72Ee0291c6C67` | [View](https://sepolia.etherscan.io/address/0x7144AE87f605dB2Aa94Fd32cF3F72Ee0291c6C67) |
| Base | Sepolia | `0x7144AE87f605dB2Aa94Fd32cF3F72Ee0291c6C67` | [View](https://sepolia.basescan.org/address/0x7144AE87f605dB2Aa94Fd32cF3F72Ee0291c6C67) |
| Arbitrum | Sepolia | `0x7144AE87f605dB2Aa94Fd32cF3F72Ee0291c6C67` | [View](https://sepolia.arbiscan.io/address/0x7144AE87f605dB2Aa94Fd32cF3F72Ee0291c6C67) |

## Features

- ✅ **Always multi-chain** - every signature automatically broadcasts to ALL registered chains
- ✅ **Pure event-based** - no on-chain storage, ~95% gas savings
- ✅ **Cross-chain messaging** via LayerZero v2
- ✅ **The Graph compatible** for indexing (100k queries/month free)
- ✅ **Minimal gas costs** - events cost ~375 gas/byte vs ~20k gas for storage
- ✅ **Simple UX** - sign once, appear everywhere

## Architecture

Pure event-based design with single contract implementation:

```
┌─────────────────────────────────────────┐
│       Guestbook.sol (423 lines)         │
│  ┌───────────────────────────────────┐  │
│  │  • Event definitions              │  │
│  │  • No on-chain storage            │  │
│  │  • LayerZero OApp integration     │  │
│  │  • Automatic peer registration    │  │
│  │  • Cross-chain broadcasting       │  │
│  │  • Owner controls (signFor)       │  │
│  │  • Historical sync                │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

**Benefits:**
- **Gas Efficient**: ~95% cheaper than storage-based approach
- **Scalable**: Unlimited signatures without storage bloat
- **The Graph Ready**: All data in events for easy indexing
- **Simplified**: Single contract with automatic chain registry management
- **Professional**: Follows Solidity best practices

**Data Access:**
- On-chain queries: Not available (no storage)
- Off-chain queries: Use third-party tool such as The Graph subgraph to index events

### Events

- `SignedGuestbook`: Emitted for all signatures (local and cross-chain). Use `sourceChainId` to distinguish: if `sourceChainId == block.chainid`, it's a local signature; otherwise it's cross-chain.
- `ChainAdded`: Emitted when a peer is set (automatically registers chain)
- `ChainRemoved`: Emitted when a peer is removed (automatically deregisters chain)

## Quick Start

### 1. Install Dependencies

```bash
git clone <repo>
cd guestbook
forge install
```

### 2. Build

```bash
forge build
```

### 3. Test

```bash
forge test
```

### 4. Multi-Chain Deployment

See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) for detailed instructions on deploying across multiple chains.

## Usage

### Signing (Always Multi-Chain)

Every signature is automatically broadcast to all registered chains:

```solidity
// Get quote for broadcasting to all chains
uint256 totalFee = guestbook.quoteBroadcast(msg.sender, "Alice", "Hello everywhere!", "");

// Sign once - appears on ALL registered chains
guestbook.signGuestbook{value: totalFee}("Alice", "Hello everywhere!", "");

// Owner can sign on behalf of others (for bootstrapping)
guestbook.signGuestbookFor{value: totalFee}(userAddress, "Bob", "Welcome!", "");
```

**How it works:**
1. Signature is emitted as event on local chain
2. Signature is automatically sent to ALL registered chains via LayerZero
3. Each chain emits the same signature event (with original `sourceChainId`)
4. The Graph indexes all events → users see signatures from all chains

### Chain Management (Owner Only)

Chain management is automatic through LayerZero peer setup:

```solidity
// Set peer - automatically registers chain for broadcasting
guestbook.setPeer(baseEid, bytes32(uint256(uint160(remoteGuestbookAddress))));

// Remove peer - automatically deregisters chain from broadcasting
guestbook.setPeer(oldChainEid, bytes32(0));

// View registered chains
uint32[] memory chains = guestbook.getRegisteredChains();

// Check if chain is registered
bool isRegistered = guestbook.isChainRegistered(chainEid);

// Batch emit historical signatures locally on this chain
// Owner fetches signature data from The Graph subgraph first
Guestbook.SignatureData[] memory sigs = fetchFromSubgraph();
guestbook.batchEmitSignatures(sigs);
```

### Query Signatures

**Note:** Since this is a pure event-based contract with no on-chain storage, all queries must be done via third-party tools such as The Graph subgraph.

Example GraphQL query:
```graphql
{
  signatures(orderBy: timestamp, orderDirection: desc) {
    id
    signer
    sourceChainId
    name
    message
    timestamp
  }

  userSignatures(where: {signer: "0x..."}) {
    id
    name
    message
  }
}
```

On-chain, you can only check:
```solidity
// View registered chains
uint32[] memory chains = guestbook.getRegisteredChains();

// Check if chain is registered
bool isRegistered = guestbook.isChainRegistered(chainEid);

// Get local chain's endpoint ID
uint32 eid = guestbook.localEid();
```

## Development

### Run Tests
```bash
forge test -vv
```

### Decode Signatures
Use the provided utility to decode signature events from transactions:
```bash
./scripts/decode-signature.sh <tx_hash> <rpc_url>
```

### LayerZero Integration
Cross-chain messaging is handled through LayerZero v2's OApp framework with peer configuration.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

