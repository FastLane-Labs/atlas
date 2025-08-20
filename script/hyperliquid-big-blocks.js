#!/usr/bin/env node

const https = require('https');
const crypto = require('crypto');
const { execSync } = require('child_process');

// EIP712 Domain for Hyperliquid Mainnet
const EIP712_DOMAIN = {
    name: "Exchange",
    version: "1",
    chainId: 999,
    verifyingContract: "0x0000000000000000000000000000000000000000"
};

// EIP712 Types for Agent signing (following Python SDK pattern)
const AGENT_TYPES = {
    Agent: [
        { name: "source", type: "string" },
        { name: "connectionId", type: "bytes32" }
    ]
};

function makeRequest(hostname, path, data) {
    return new Promise((resolve, reject) => {
        const options = {
            hostname: hostname,
            port: 443,
            path: path,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(data)
            }
        };

        const req = https.request(options, (res) => {
            let responseData = '';
            res.on('data', (chunk) => {
                responseData += chunk;
            });
            res.on('end', () => {
                try {
                    resolve(JSON.parse(responseData));
                } catch (e) {
                    resolve(responseData);
                }
            });
        });

        req.on('error', (error) => {
            reject(error);
        });

        req.write(data);
        req.end();
    });
}

function getPrivateKey() {
    // Try to get private key from environment
    const privateKey = process.env.GOV_PRIVATE_KEY;
    if (!privateKey) {
        throw new Error('GOV_PRIVATE_KEY environment variable is not set. Please export it before running this script.');
    }
    // Remove 0x prefix if present
    return privateKey.replace(/^0x/i, '');
}

function getAddress(privateKey) {
    // Use cast wallet address to get the address from private key
    try {
        const result = execSync(`cast wallet address --private-key 0x${privateKey}`, { encoding: 'utf8' });
        return result.trim();
    } catch (error) {
        throw new Error(`Failed to get address from private key: ${error.message}`);
    }
}

async function signEIP712(domain, types, primaryType, message, privateKey) {
    // Create the EIP712 typed data structure
    const typedData = {
        types: {
            EIP712Domain: [
                { name: "name", type: "string" },
                { name: "version", type: "string" },
                { name: "chainId", type: "uint256" },
                { name: "verifyingContract", type: "address" }
            ],
            ...types
        },
        primaryType: primaryType,
        domain: domain,
        message: message
    };

    // Convert to JSON for cast command
    const typedDataJson = JSON.stringify(typedData);
    
    try {
        // Use cast wallet sign with --data flag for typed data
        // Write JSON to temp file to avoid shell escaping issues
        const fs = require('fs');
        const tmpFile = `/tmp/typed-data-${Date.now()}.json`;
        fs.writeFileSync(tmpFile, typedDataJson);
        
        const command = `cast wallet sign --data --from-file --private-key 0x${privateKey} ${tmpFile}`;
        const signature = execSync(command, { encoding: 'utf8' }).trim();
        
        // Clean up temp file
        fs.unlinkSync(tmpFile);
        
        // Parse the signature (remove 0x prefix)
        const sig = signature.replace(/^0x/i, '');
        
        // Extract r, s, v from the signature
        const r = '0x' + sig.slice(0, 64);
        const s = '0x' + sig.slice(64, 128);
        const v = parseInt(sig.slice(128, 130), 16);
        
        return { r, s, v };
    } catch (error) {
        throw new Error(`Failed to sign EIP712 data: ${error.message}`);
    }
}

async function toggleBigBlocks(enable) {
    const hostname = 'api.hyperliquid.xyz';
    const path = '/exchange';
    const action = enable ? 'Enabling' : 'Disabling';
    
    console.log(`${action} big blocks on mainnet...`);
    
    try {
        // Get private key and address
        const privateKey = getPrivateKey();
        const address = getAddress(privateKey);
        console.log(`Using address: ${address}`);
        
        // Use mainnet domain
        const domain = EIP712_DOMAIN;
        
        // Generate nonce (timestamp as in Python SDK)
        const nonce = Date.now();
        
        // Create the action structure
        const actionStruct = {
            type: "evmUserModify",
            usingBigBlocks: enable
        };
        
        // Calculate action hash as connectionId (following Python SDK pattern)
        // Hash the action structure to use as connectionId
        const actionJson = JSON.stringify(actionStruct);
        const actionHash = '0x' + crypto.createHash('sha256').update(actionJson).digest('hex');
        
        // Create agent for signing (following Python SDK pattern)
        const agent = {
            source: "a",  // "a" for mainnet as in Python SDK
            connectionId: actionHash
        };
        
        // Sign the Agent (not the action directly, as per Python SDK)
        console.log('Signing EIP712 Agent message...');
        const signature = await signEIP712(
            domain,
            AGENT_TYPES,
            'Agent',
            agent,
            privateKey
        );
        
        // Create the payload with signature (following Python SDK structure)
        const payload = JSON.stringify({
            action: actionStruct,
            nonce: nonce,
            signature: signature,
            vaultAddress: null  // Not using vault delegation
        });
        
        console.log(`Sending ${action.toLowerCase()} request...`);
        const result = await makeRequest(hostname, path, payload);
        
        // Check for success
        if (result.status === 'ok' || (typeof result === 'object' && !result.error)) {
            console.log(`✅ Successfully ${action.toLowerCase()} big blocks`);
            return true;
        } else {
            console.error(`❌ Failed to ${action.toLowerCase()} big blocks:`, result);
            return false;
        }
    } catch (error) {
        console.error(`❌ Error ${action.toLowerCase()} big blocks:`, error.message);
        return false;
    }
}

async function getBigBlockGasPrice() {
    const hostname = 'rpc.hyperliquid.xyz';
    const path = '/evm';
    
    const payload = JSON.stringify({
        jsonrpc: "2.0",
        method: "eth_bigBlockGasPrice",
        params: [],
        id: 1
    });
    
    try {
        const result = await makeRequest(hostname, path, payload);
        if (result.result) {
            console.log(`Big block gas price: ${result.result}`);
            return result.result;
        } else if (result.error) {
            console.error('Error from RPC:', result.error);
        }
    } catch (error) {
        console.error('Error getting big block gas price:', error);
    }
    return null;
}

async function checkBigBlockStatus() {
    const hostname = 'rpc.hyperliquid.xyz';
    const path = '/evm';
    
    try {
        // Get private key and address
        const privateKey = getPrivateKey();
        const address = getAddress(privateKey);
        
        const payload = JSON.stringify({
            jsonrpc: "2.0",
            method: "eth_usingBigBlocks",
            params: [address],
            id: 1
        });
        
        const result = await makeRequest(hostname, path, payload);
        if (result.result !== undefined) {
            const isEnabled = result.result;
            console.log(`Big blocks enabled for ${address}: ${isEnabled}`);
            
            // If not enabled, suggest the web UI
            if (!isEnabled && !process.env.SKIP_WEB_UI_CHECK) {
                console.log('');
                console.log('⚠️  Big blocks are not enabled for your address.');
                console.log('📌 You can enable big blocks using the web UI:');
                console.log('   https://hyperevm-block-toggle.vercel.app/');
                console.log('');
                console.log('Alternatively, use: node script/hyperliquid-big-blocks.js enable');
            }
            
            return isEnabled;
        } else if (result.error) {
            console.error('Error from RPC:', result.error);
        }
    } catch (error) {
        console.error('Error checking big block status:', error);
    }
    return null;
}

async function main() {
    const args = process.argv.slice(2);
    const command = args[0];
    
    if (!command || !['enable', 'disable', 'gas-price', 'status', 'check'].includes(command)) {
        console.log('Usage: node hyperliquid-big-blocks.js [command]');
        console.log('');
        console.log('Commands:');
        console.log('  check      - Check status and suggest web UI if not enabled');
        console.log('  status     - Check if big blocks are enabled for your address');
        console.log('  enable     - Enable big blocks for deployment');
        console.log('  disable    - Disable big blocks after deployment');
        console.log('  gas-price  - Get current big block gas price');
        console.log('');
        console.log('Environment:');
        console.log('  GOV_PRIVATE_KEY - Required for enable/disable/status/check commands');
        console.log('');
        console.log('Examples:');
        console.log('  export GOV_PRIVATE_KEY=your_private_key_here');
        console.log('  node hyperliquid-big-blocks.js check');
        console.log('  node hyperliquid-big-blocks.js enable');
        console.log('  node hyperliquid-big-blocks.js disable');
        process.exit(1);
    }
    
    switch(command) {
        case 'check':
        case 'status':
            const status = await checkBigBlockStatus();
            process.exit(status === true ? 0 : 1);
            break;
        case 'enable':
            const enableSuccess = await toggleBigBlocks(true);
            process.exit(enableSuccess ? 0 : 1);
            break;
        case 'disable':
            const disableSuccess = await toggleBigBlocks(false);
            process.exit(disableSuccess ? 0 : 1);
            break;
        case 'gas-price':
            await getBigBlockGasPrice();
            break;
    }
}

main().catch(console.error);