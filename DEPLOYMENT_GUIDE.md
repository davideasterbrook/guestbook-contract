# Multi-Chain Deployment Guide

This guide covers deploying and testing the Guestbook contract across multiple chains using secure keystore management.

## Prerequisites

1. **Foundry installed**
2. **Test ETH on testnets** (or real ETH for mainnet)
3. **RPC endpoints** (Alchemy, Infura, etc.)

## Setup (One-Time)

### 1. Create Encrypted Keystore

```bash
cast wallet import deployer --interactive
```

You'll be prompted to:
1. Enter your private key
2. Choose a password to encrypt it

This stores your encrypted key at `~/.foundry/keystores/deployer`

### 2. Configure Environment Variables

Copy the example file and customize:

```bash
cp example.env .env
```

Update `.env` with your values:

Load environment:
```bash
source .env
```

## Deployment Process

### Step 1: Deploy to All Chains

```bash
source .env
forge script script/DeployMultiChain.s.sol:DeployMultiChainScript \
  --sig "deployAll()" \
  --rpc-url $DEPLOY_NETWORK \
  --account $DEPLOY_ACCOUNT \
  --sender $DEPLOY_ADDRESS \
  --broadcast
```

**You'll be prompted for your keystore password.**

This will:
- Deploy Guestbook to all configured chains
- Save addresses to `deployments.json`
- Output deployment info

**Example output:**
```
=== Multi-Chain Deployment ===
Deploying to 3 chains

Deploying to: sepolia
Chain EID: 40161
Deployed at: 0x1234...
Deployer: 0xYourAddress

Deploying to: base_sepolia
...
```

### Step 2: Configure Peers

After deployment, set up cross-chain communication:

```bash
forge script script/DeployMultiChain.s.sol:DeployMultiChainScript \
  --sig "configurePeers()" \
  --rpc-url $DEPLOY_NETWORK \
  --account $DEPLOY_ACCOUNT \
  --sender $DEPLOY_ADDRESS \
  --broadcast
```

This configures bidirectional peering between all chains.

### Step 3: Validate Deployment

```bash
forge script script/DeployMultiChain.s.sol:DeployMultiChainScript \
  --sig "validate()" \
  --rpc-url $DEPLOY_NETWORK
```

Checks:
- Contract deployed on each chain
- Correct endpoint IDs
- All peers configured
- Ready for testing

**Example output:**
```
=== Validating Deployment ===

Validating: sepolia
Address: 0x1234...
Local EID: 40161
Registered chains: 2
Status: VALID

...

=== Validation PASSED ===
Ready for testing!
```

### Step 4: View Deployments

```bash
forge script script/DeployMultiChain.s.sol:DeployMultiChainScript \
  --sig "showDeployments()" \
  --rpc-url $DEPLOY_NETWORK
```

Shows all deployed addresses and their bytes32 representations.

## Testing Cross-Chain Messages

### 1. Get Quote for Broadcasting

First, set the LayerZero options with 50,000 gas for destination execution:

```bash
# Options: 50,000 gas for lzReceive execution
# Format: 0x0003 (type 3) + 0100 (lzReceive) + 11 (length) + 01 (executor) + gas limit in hex
LZ_OPTIONS=0x0003010011010000000000000000000000000000c350

# Get quote
cast call $GUESTBOOK_ADDRESS \
  "quoteBroadcast(address,string,string,bytes)" \
  $DEPLOY_ADDRESS \
  "David" \
  "Hello from Sepolia" \
  $LZ_OPTIONS \
  --rpc-url $SEPOLIA_RPC_URL
```

Returns the fee in wei (e.g., `500000000000000` = 0.0005 ETH)

### 2. Sign Guestbook (Triggers Cross-Chain Broadcast)

```bash
# Get the quote first (returns hex)
QUOTE=$(cast call $GUESTBOOK_ADDRESS "quoteBroadcast(address,string,string,bytes)" $DEPLOY_ADDRESS "David" "Hello from Sepolia" $LZ_OPTIONS --rpc-url $SEPOLIA_RPC_URL)

# Convert hex quote to decimal for --value
QUOTE_DEC=$(cast to-dec $QUOTE)

# Sign with the quoted fee
cast send $GUESTBOOK_ADDRESS \
  "signGuestbookFor(address,string,string,bytes)" \
  $DEPLOY_ADDRESS \
  "David" \
  "Hello from Sepolia" \
  $LZ_OPTIONS \
  --value $QUOTE_DEC \
  --rpc-url $SEPOLIA_RPC_URL \
  --account $DEPLOY_ACCOUNT
```

### 3. Verify Messages Arrived

Wait 1-5 minutes for LayerZero delivery, then check events on all chains.

For example:

```bash
# Check on Sepolia
# Get block from etherscan or transaction
BLOCK=<get_block_id>
cast logs --address $GUESTBOOK_ADDRESS \
  --from-block $BLOCK \
  --to-block $((BLOCK + 1)) \
  --rpc-url $SEPOLIA_RPC_URL \
  "SignedGuestbook(address,uint32,string,string,uint256)"

# Check on Base Sepolia
BLOCK=<get_block_id>
cast logs --address $GUESTBOOK_ADDRESS \
  --from-block $BLOCK \
  --to-block $((BLOCK + 1)) \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  "SignedGuestbook(address,uint32,string,string,uint256)"
```

#### Decode

The below script can be used to decode the signature data to human readable format.
```bash
./scripts/decode-signature.sh 0xa11c0b5c298d5d878d7c1c0de20a3c4ebc3372452883f2171059e4f20dea806a $ARB_SEPOLIA_RPC_URL
```

### 4. Track Messages on LayerZero Scan

Visit: layerzeroscan.com

Search by:
- Transaction hash (from source chain)
- Contract address

Shows message status, delivery time, and any errors.

### Additional: Bootstrap messages

```bash
# Default usage with bootstrap.csv
./script/bootstrap-signatures.sh

# Custom file
./scripts/bootstrap-signatures.sh my-custom.csv

# Dry run
./scripts/bootstrap-signatures.sh bootstrap.csv true

# Override network via argument - otherwise defaults to .env DEPLOY_NETWORK
./scripts/bootstrap-signatures.sh bootstrap.csv base_sepolia
```


## Configuration

### Adding/Removing Chains

Edit `script/DeployMultiChain.s.sol`, modify the `setUp()` function:

```solidity
function setUp() public {
    // Add a new chain
    CHAINS.push(ChainConfig({
        name: "optimism_sepolia",
        rpcEnvVar: "OP_SEPOLIA_RPC_URL",
        lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
        eid: 40232
    }));

    // Remove a chain: just comment it out or delete
}
```

### Deploying to other chains

1. Update `ACTIVE_CHAINS` in `script/DeployMultiChain.s.sol`

## Troubleshooting

### "Keystore not found"
```bash
# List keystores
cast wallet list

# Reimport if needed
cast wallet import deployer --interactive
```

### "Peer not configured"
Re-run `configurePeers()` step.

### "Message not arriving"
- Check LayerZero Scan for delivery status
- Wait 5-10 minutes (testnets can be slow)
- Verify sufficient fee was paid (check quote)
- Ensure peers are bidirectionally configured

### "RPC URL not set"
```bash
source .env
# or
export SEPOLIA_RPC_URL=...
```

## Next Steps

After successful deployment:

TODO: Add bootstrap signatures


1. **Verify contracts** on block explorers:
   ```bash
   forge verify-contract <ADDRESS> Guestbook --chain sepolia
   ```

