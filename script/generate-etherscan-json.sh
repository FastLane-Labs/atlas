#!/bin/bash

# Generate Perfect Etherscan-Style JSON using Foundry's built-in flag
# Usage: ./script/generate-etherscan-json.sh <contract_address> <contract_path:contract_name> [constructor_args]

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [ $# -lt 2 ]; then
    echo "Usage: $0 <contract_address> <contract_path:contract_name> [constructor_args]"
    echo ""
    echo "Example:"
    echo "  $0 0x123... src/MyContract.sol:MyContract 0x456..."
    exit 1
fi

CONTRACT_ADDRESS=$1
CONTRACT_PATH=$2
CONSTRUCTOR_ARGS=${3:-""}

# Extract contract name for filename
CONTRACT_NAME=$(echo $CONTRACT_PATH | cut -d':' -f2)

echo -e "${BLUE}Generating Etherscan-style verification JSON using Foundry...${NC}"
echo "Address: $CONTRACT_ADDRESS"
echo "Contract: $CONTRACT_PATH"

if [ -n "$CONSTRUCTOR_ARGS" ]; then
    echo "Constructor args: $CONSTRUCTOR_ARGS"
fi

echo ""
echo -e "${BLUE}Running forge verify-contract --show-standard-json-input...${NC}"

# Create cache directory if it doesn't exist
mkdir -p cache

# Generate the standard JSON in cache directory
JSON_FILE="cache/etherscan_${CONTRACT_NAME}_$(date +%s).json"

if [ -n "$CONSTRUCTOR_ARGS" ]; then
    forge verify-contract --show-standard-json-input $CONTRACT_ADDRESS $CONTRACT_PATH --constructor-args $CONSTRUCTOR_ARGS > "$JSON_FILE"
else
    forge verify-contract --show-standard-json-input $CONTRACT_ADDRESS $CONTRACT_PATH > "$JSON_FILE"
fi

echo -e "${GREEN}✅ Generated perfect Etherscan verification JSON: $JSON_FILE${NC}"
echo ""
echo -e "${YELLOW}Upload options:${NC}"
echo ""
echo "1. 📋 Manual web upload to Hyperscan:"
echo "   - Go to https://www.hyperscan.com/verifyContract"
echo "   - Or try https://www.hyperscan.com/address/$CONTRACT_ADDRESS"
echo "   - Upload the generated JSON file"
echo ""
echo "2. 🚀 Direct API call (when Hyperscan API is available):"
echo "   curl -X POST https://www.hyperscan.com/api \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d @$JSON_FILE"
echo ""
echo "3. 📄 View the JSON contents:"
echo "   cat $JSON_FILE | jq ."
echo ""
echo -e "${GREEN}This JSON contains all source code, compilation settings, and metadata${NC}"
echo -e "${GREEN}exactly as Foundry would send it to an Etherscan-style API.${NC}"