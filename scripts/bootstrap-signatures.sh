#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
BOOTSTRAP_FILE="${1:-bootstrap.csv}"
NETWORK="${2}"
DRY_RUN="${3:-false}"

# LayerZero options: 50,000 gas for lzReceive execution
LZ_OPTIONS=0x0003010011010000000000000000000000000000c350

echo -e "${BLUE}=== Bootstrap Guestbook Signatures ===${NC}"
echo ""

# Load .env file
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found${NC}"
    echo "Please create .env from example.env"
    exit 1
fi

set -a
source .env
set +a

# Use network from argument or fall back to DEPLOY_NETWORK from .env
if [ -n "$NETWORK" ]; then
    DEPLOY_NETWORK="$NETWORK"
elif [ -z "$DEPLOY_NETWORK" ]; then
    echo -e "${RED}Error: No network specified${NC}"
    echo "Usage: $0 [bootstrap_file.csv] [network] [dry_run]"
    echo "Example: $0 bootstrap.csv ethereum"
    echo ""
    echo "Available networks:"
    echo "  Testnets: sepolia, base_sepolia, arbitrum_sepolia"
    echo "  Mainnets: ethereum, base, arbitrum"
    exit 1
fi

# Check if bootstrap file exists
if [ ! -f "$BOOTSTRAP_FILE" ]; then
    echo -e "${RED}Error: Bootstrap file not found: $BOOTSTRAP_FILE${NC}"
    echo "Usage: $0 [bootstrap_file.csv] [network] [dry_run]"
    exit 1
fi

# Determine RPC URL based on network
case "$DEPLOY_NETWORK" in
    sepolia)
        RPC_URL="$SEPOLIA_RPC_URL"
        ;;
    base_sepolia)
        RPC_URL="$BASE_SEPOLIA_RPC_URL"
        ;;
    arbitrum_sepolia)
        RPC_URL="$ARB_SEPOLIA_RPC_URL"
        ;;
    ethereum)
        RPC_URL="$ETHEREUM_RPC_URL"
        ;;
    base)
        RPC_URL="$BASE_RPC_URL"
        ;;
    arbitrum)
        RPC_URL="$ARBITRUM_RPC_URL"
        ;;
    *)
        echo -e "${RED}Error: Unknown DEPLOY_NETWORK: $DEPLOY_NETWORK${NC}"
        exit 1
        ;;
esac

# Get guestbook address from deployments.json
if [ ! -f "deployments.json" ]; then
    echo -e "${RED}Error: deployments.json not found${NC}"
    echo "Please deploy contracts first"
    exit 1
fi

GUESTBOOK_ADDRESS=$(jq -r ".${DEPLOY_NETWORK}.address" deployments.json)

if [ "$GUESTBOOK_ADDRESS" == "null" ] || [ -z "$GUESTBOOK_ADDRESS" ]; then
    echo -e "${RED}Error: No deployment found for network: $DEPLOY_NETWORK${NC}"
    exit 1
fi

echo -e "Network:           ${GREEN}$DEPLOY_NETWORK${NC}"
echo -e "RPC URL:           ${GREEN}${RPC_URL:0:30}...${NC}"
echo -e "Guestbook Address: ${GREEN}$GUESTBOOK_ADDRESS${NC}"
echo -e "Bootstrap File:    ${GREEN}$BOOTSTRAP_FILE${NC}"
echo -e "Deployer Account:  ${GREEN}$DEPLOY_ACCOUNT${NC}"
echo ""

if [ "$DRY_RUN" == "true" ]; then
    echo -e "${YELLOW}DRY RUN MODE - No transactions will be sent${NC}"
    echo ""
fi

# Count entries (excluding comments and empty lines)
TOTAL_ENTRIES=$(grep -v '^#' "$BOOTSTRAP_FILE" | grep -v '^$' | wc -l | tr -d ' ')
echo -e "Found ${GREEN}$TOTAL_ENTRIES${NC} entries to process"
echo ""

CURRENT=0
SUCCESSFUL=0
FAILED=0

# Read and process each line
while IFS=',' read -r address name message || [ -n "$address" ]; do
    # Skip comments and empty lines
    if [[ "$address" =~ ^#.*$ ]] || [ -z "$address" ]; then
        continue
    fi

    CURRENT=$((CURRENT + 1))

    echo -e "${BLUE}[$CURRENT/$TOTAL_ENTRIES]${NC} Processing signature for: ${GREEN}$name${NC}"
    echo -e "  Address: $address"
    echo -e "  Message: $message"

    # Get quote
    echo -e "  ${YELLOW}Getting quote...${NC}"
    QUOTE=$(cast call "$GUESTBOOK_ADDRESS" \
        "quoteBroadcast(address,string,string,bytes)" \
        "$address" \
        "$name" \
        "$message" \
        "$LZ_OPTIONS" \
        --rpc-url "$RPC_URL" 2>&1)

    if [ $? -ne 0 ]; then
        echo -e "  ${RED}✗ Failed to get quote${NC}"
        echo -e "  Error: $QUOTE"
        FAILED=$((FAILED + 1))
        echo ""
        continue
    fi

    # Convert to decimal
    QUOTE_DEC=$(cast to-dec "$QUOTE")
    QUOTE_ETH=$(cast from-wei "$QUOTE")
    echo -e "  Quote: ${GREEN}$QUOTE_ETH ETH${NC} ($QUOTE_DEC wei)"

    if [ "$DRY_RUN" == "true" ]; then
        echo -e "  ${YELLOW}[DRY RUN] Would send transaction${NC}"
        SUCCESSFUL=$((SUCCESSFUL + 1))
        echo ""
        continue
    fi

    # Send transaction
    echo -e "  ${YELLOW}Sending transaction...${NC}"
    TX_RESULT=$(cast send "$GUESTBOOK_ADDRESS" \
        "signGuestbookFor(address,string,string,bytes)" \
        "$address" \
        "$name" \
        "$message" \
        "$LZ_OPTIONS" \
        --value "$QUOTE_DEC" \
        --rpc-url "$RPC_URL" \
        --account "$DEPLOY_ACCOUNT" 2>&1)

    if [ $? -eq 0 ]; then
        # Extract transaction hash
        TX_HASH=$(echo "$TX_RESULT" | grep -i "transactionHash" | awk '{print $2}')
        echo -e "  ${GREEN}✓ Success${NC}"
        echo -e "  TX: $TX_HASH"
        SUCCESSFUL=$((SUCCESSFUL + 1))
    else
        echo -e "  ${RED}✗ Failed${NC}"
        echo -e "  Error: $TX_RESULT"
        FAILED=$((FAILED + 1))
    fi

    echo ""

    # Small delay to avoid rate limiting
    sleep 2

done < "$BOOTSTRAP_FILE"

echo -e "${BLUE}=== Bootstrap Complete ===${NC}"
echo -e "Total:      $TOTAL_ENTRIES"
echo -e "Successful: ${GREEN}$SUCCESSFUL${NC}"
echo -e "Failed:     ${RED}$FAILED${NC}"
echo ""

if [ "$DRY_RUN" != "true" ]; then
    echo -e "${YELLOW}Note: Cross-chain messages may take 1-5 minutes to propagate${NC}"
    echo -e "Track messages at: ${BLUE}https://layerzeroscan.com${NC}"
fi
