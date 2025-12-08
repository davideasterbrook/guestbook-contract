#!/bin/bash

# Usage: ./scripts/decode-signature.sh <tx_hash> <rpc_url>

TX_HASH=$1
RPC_URL=$2

if [ -z "$TX_HASH" ] || [ -z "$RPC_URL" ]; then
    echo "Usage: ./scripts/decode-signature.sh <tx_hash> <rpc_url>"
    echo "Example: ./scripts/decode-signature.sh 0x123... \$SEPOLIA_RPC_URL"
    exit 1
fi

echo "=== Guestbook Signature Decoder ==="
echo ""

# Get the receipt
RECEIPT=$(cast receipt $TX_HASH --rpc-url $RPC_URL --json)

# Check if transaction succeeded
STATUS=$(echo $RECEIPT | jq -r '.status')
if [ "$STATUS" != "0x1" ]; then
    echo "❌ Transaction failed"
    exit 1
fi

echo "✅ Transaction succeeded"
echo ""

# Extract SignedGuestbook event (topic[0] = 0x9c56749eeeae483bed72b61f7c7759e604b35cb2604ed7325f2c6b1387a5fecb)
EVENT=$(echo $RECEIPT | jq -r '.logs[] | select(.topics[0] == "0x9c56749eeeae483bed72b61f7c7759e604b35cb2604ed7325f2c6b1387a5fecb") | @json' | head -1)

if [ -z "$EVENT" ] || [ "$EVENT" == "null" ]; then
    echo "No SignedGuestbook event found"
    exit 0
fi

# Parse event data
SIGNER=$(echo $EVENT | jq -r '.topics[1]' | sed 's/^0x000000000000000000000000/0x/')
SOURCE_CHAIN_HEX=$(echo $EVENT | jq -r '.topics[2]')
SOURCE_CHAIN=$(cast to-dec $SOURCE_CHAIN_HEX)
DATA=$(echo $EVENT | jq -r '.data')

# Decode all the data properly using cast
# The data contains: string name, string message, uint256 timestamp
DECODED=$(cast decode-abi "f()(string,string,uint256)" $DATA 2>&1)

if echo "$DECODED" | grep -q "Error"; then
    echo "Failed to decode event data"
    echo "Raw data: $DATA"
    exit 1
fi

# Cast outputs each value on a new line with quotes around strings
NAME=$(echo "$DECODED" | sed -n '1p' | tr -d '"')
MESSAGE=$(echo "$DECODED" | sed -n '2p' | tr -d '"')
TIMESTAMP=$(echo "$DECODED" | sed -n '3p' | awk '{print $1}')
TIMESTAMP_DATE=$(date -r $TIMESTAMP 2>/dev/null || date -d @$TIMESTAMP 2>/dev/null || echo "timestamp: $TIMESTAMP")

echo "📝 Signature Details:"
echo "  Signer:         $SIGNER"
echo "  Source Chain:   $SOURCE_CHAIN"
echo "  Name:           $NAME"
echo "  Message:        $MESSAGE"
echo "  Timestamp:      $TIMESTAMP_DATE"
echo ""

# Count LayerZero PacketSent events
PACKETS=$(echo $RECEIPT | jq '[.logs[] | select(.topics[0] == "0x1ab700d4ced0c005b164c0f789fd09fcbb0156d4c2041b8a3bfbcd961cd1567f")] | length')
echo "📤 Cross-chain messages sent: $PACKETS"
echo ""
echo "🔍 Track delivery: https://testnet.layerzeroscan.com/tx/$TX_HASH"
