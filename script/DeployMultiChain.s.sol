// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console2} from "forge-std/Script.sol";
import {Guestbook} from "../src/Guestbook.sol";
import {stdJson} from "forge-std/StdJson.sol";

/**
 * @title DeployMultiChainScript
 * @notice Multi-chain deployment and configuration script for Guestbook
 * @dev Handles deployment, peer configuration, and validation across multiple chains
 *
 * Setup (one-time):
 *   1. Create encrypted keystore:
 *      cast wallet import deployer --interactive
 *      (Enter your private key and a password to encrypt it)
 *
 *   2. Set RPC URLs in .env:
 *      SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
 *      BASE_SEPOLIA_RPC_URL=https://base-sepolia.g.alchemy.com/v2/YOUR_KEY
 *      ARB_SEPOLIA_RPC_URL=https://arb-sepolia.g.alchemy.com/v2/YOUR_KEY
 *
 * Usage:
 *   Deploy to all chains:
 *     forge script script/DeployMultiChain.s.sol:DeployMultiChainScript --sig "deployAll()" -f sepolia --account deployer --broadcast
 *
 *   Configure peers (after deployment):
 *     forge script script/DeployMultiChain.s.sol:DeployMultiChainScript --sig "configurePeers()" -f sepolia --account deployer --broadcast
 *
 *   Validate deployment:
 *     forge script script/DeployMultiChain.s.sol:DeployMultiChainScript --sig "validate()" -f sepolia
 *
 * Configuration:
 *   - Edit ACTIVE_CHAINS array at the top to select which chains to deploy to
 *   - All available chains are pre-configured (testnets and mainnets)
 */
contract DeployMultiChainScript is Script {
    using stdJson for string;

    // ============ Configuration ============

    // ========== EDIT THIS: Active chains to deploy ==========
    string[] public ACTIVE_CHAINS = [
        "sepolia",
        "base_sepolia",
        "arbitrum_sepolia"
    ];
    // ========================================================

    struct ChainConfig {
        string name;                // Chain identifier (e.g., "sepolia")
        string rpcEnvVar;          // Environment variable for RPC URL
        address lzEndpoint;        // LayerZero V2 endpoint address
        uint32 eid;                // LayerZero endpoint ID
    }

    // All available chain configurations
    mapping(string => ChainConfig) public ALL_CHAINS;

    // Active chains to deploy (populated from ACTIVE_CHAINS)
    ChainConfig[] public CHAINS;

    // Deployment artifacts storage
    string constant DEPLOYMENTS_FILE = "deployments.json";

    function setUp() public {
        // ============ Testnet Configurations ============

        ALL_CHAINS["sepolia"] = ChainConfig({
            name: "sepolia",
            rpcEnvVar: "SEPOLIA_RPC_URL",
            lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
            eid: 40161
        });

        ALL_CHAINS["base_sepolia"] = ChainConfig({
            name: "base_sepolia",
            rpcEnvVar: "BASE_SEPOLIA_RPC_URL",
            lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
            eid: 40245
        });

        ALL_CHAINS["arbitrum_sepolia"] = ChainConfig({
            name: "arbitrum_sepolia",
            rpcEnvVar: "ARB_SEPOLIA_RPC_URL",
            lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
            eid: 40231
        });

        ALL_CHAINS["optimism_sepolia"] = ChainConfig({
            name: "optimism_sepolia",
            rpcEnvVar: "OP_SEPOLIA_RPC_URL",
            lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
            eid: 40232
        });

        ALL_CHAINS["polygon_amoy"] = ChainConfig({
            name: "polygon_amoy",
            rpcEnvVar: "POLYGON_AMOY_RPC_URL",
            lzEndpoint: 0x6EDCE65403992e310A62460808c4b910D972f10f,
            eid: 40267
        });

        // ============ Mainnet Configurations ============

        ALL_CHAINS["ethereum"] = ChainConfig({
            name: "ethereum",
            rpcEnvVar: "ETHEREUM_RPC_URL",
            lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            eid: 30101
        });

        ALL_CHAINS["base"] = ChainConfig({
            name: "base",
            rpcEnvVar: "BASE_RPC_URL",
            lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            eid: 30184
        });

        ALL_CHAINS["arbitrum"] = ChainConfig({
            name: "arbitrum",
            rpcEnvVar: "ARBITRUM_RPC_URL",
            lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            eid: 30110
        });

        ALL_CHAINS["optimism"] = ChainConfig({
            name: "optimism",
            rpcEnvVar: "OPTIMISM_RPC_URL",
            lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            eid: 30111
        });

        ALL_CHAINS["polygon"] = ChainConfig({
            name: "polygon",
            rpcEnvVar: "POLYGON_RPC_URL",
            lzEndpoint: 0x1a44076050125825900e736c501f859c50fE728c,
            eid: 30109
        });

        // ============ Populate CHAINS from ACTIVE_CHAINS ============
        for (uint256 i = 0; i < ACTIVE_CHAINS.length; i++) {
            ChainConfig memory config = ALL_CHAINS[ACTIVE_CHAINS[i]];
            require(bytes(config.name).length > 0, string.concat("Chain not configured: ", ACTIVE_CHAINS[i]));
            CHAINS.push(config);
        }
    }

    // ============ Main Functions ============

    /**
     * @notice Deploy Guestbook to all configured chains
     * @dev Saves deployment addresses to deployments.json
     *      IMPORTANT: Use --account flag to specify the deployer account
     *      The account specified will become the owner of all deployed contracts
     */
    function deployAll() public {
        console2.log("=== Multi-Chain Deployment ===");
        console2.log("Deploying to", CHAINS.length, "chains\n");

        string memory deploymentsJson = "{";

        for (uint256 i = 0; i < CHAINS.length; i++) {
            ChainConfig memory chain = CHAINS[i];

            console2.log("Deploying to:", chain.name);
            console2.log("Chain EID:", chain.eid);

            // Switch to chain's RPC
            string memory rpcUrl = vm.envString(chain.rpcEnvVar);
            vm.createSelectFork(rpcUrl);

            // Deploy and broadcast
            // When using --account flag, vm.startBroadcast() automatically uses that account
            vm.startBroadcast();

            Guestbook guestbook = new Guestbook(
                chain.lzEndpoint,
                msg.sender,  // msg.sender will be the --account address during broadcast
                chain.eid
            );

            vm.stopBroadcast();

            console2.log("Deployed at:", address(guestbook));
            console2.log("Owner:", msg.sender);
            console2.log("");

            // Build JSON
            if (i > 0) deploymentsJson = string.concat(deploymentsJson, ",");
            deploymentsJson = string.concat(
                deploymentsJson,
                '"', chain.name, '":{"address":"',
                vm.toString(address(guestbook)),
                '","eid":', vm.toString(chain.eid),
                ',"endpoint":"', vm.toString(chain.lzEndpoint), '"}'
            );
        }

        deploymentsJson = string.concat(deploymentsJson, "}");

        // Save to file
        vm.writeFile(DEPLOYMENTS_FILE, deploymentsJson);

        console2.log("=== Deployment Complete ===");
        console2.log("Addresses saved to:", DEPLOYMENTS_FILE);
        console2.log("\nNext step: Run configurePeers()");
    }

    /**
     * @notice Configure peers between all deployed contracts
     * @dev Reads from deployments.json and sets up bidirectional peering
     *      IMPORTANT: Use --account flag with the same account that deployed the contracts
     */
    function configurePeers() public {
        console2.log("=== Configuring Peers ===\n");

        // Load deployments
        string memory deploymentsJson = vm.readFile(DEPLOYMENTS_FILE);

        // Parse deployments for each chain
        address[] memory addresses = new address[](CHAINS.length);
        for (uint256 i = 0; i < CHAINS.length; i++) {
            string memory key = string.concat(".", CHAINS[i].name, ".address");
            addresses[i] = deploymentsJson.readAddress(key);
            console2.log(CHAINS[i].name, "contract:", addresses[i]);
        }
        console2.log("");

        // Configure peers for each chain
        for (uint256 i = 0; i < CHAINS.length; i++) {
            ChainConfig memory chain = CHAINS[i];
            address guestbookAddress = addresses[i];

            console2.log("Configuring peers on:", chain.name);

            // Switch to chain's RPC
            string memory rpcUrl = vm.envString(chain.rpcEnvVar);
            vm.createSelectFork(rpcUrl);

            // When using --account flag, vm.startBroadcast() automatically uses that account
            vm.startBroadcast();
            Guestbook guestbook = Guestbook(payable(guestbookAddress));

            // Add all other chains as peers
            for (uint256 j = 0; j < CHAINS.length; j++) {
                if (i == j) continue; // Skip self

                bytes32 peerBytes32 = bytes32(uint256(uint160(addresses[j])));

                console2.log("  Adding peer:", CHAINS[j].name, "->", addresses[j]);
                guestbook.setPeer(CHAINS[j].eid, peerBytes32);
            }

            vm.stopBroadcast();
            console2.log("");
        }

        console2.log("=== Peer Configuration Complete ===");
        console2.log("\nNext step: Run validate()");
    }

    /**
     * @notice Validate deployment and peer configuration
     * @dev Checks all contracts are properly configured
     */
    function validate() public {
        console2.log("=== Validating Deployment ===\n");

        // Load deployments
        string memory deploymentsJson = vm.readFile(DEPLOYMENTS_FILE);

        bool allValid = true;

        for (uint256 i = 0; i < CHAINS.length; i++) {
            ChainConfig memory chain = CHAINS[i];

            // Parse address
            string memory key = string.concat(".", chain.name, ".address");
            address guestbookAddress = deploymentsJson.readAddress(key);

            console2.log("Validating:", chain.name);
            console2.log("Address:", guestbookAddress);

            // Switch to chain's RPC
            string memory rpcUrl = vm.envString(chain.rpcEnvVar);
            vm.createSelectFork(rpcUrl);

            Guestbook guestbook = Guestbook(payable(guestbookAddress));

            // Check local EID
            uint32 localEid = guestbook.localEid();
            console2.log("Local EID:", localEid);
            if (localEid != chain.eid) {
                console2.log("ERROR: EID mismatch!");
                allValid = false;
            }

            // Check registered chains
            uint32[] memory registeredChains = guestbook.getRegisteredChains();
            console2.log("Registered chains:", registeredChains.length);

            if (registeredChains.length != CHAINS.length - 1) {
                console2.log("ERROR: Expected", CHAINS.length - 1, "peers, found", registeredChains.length);
                allValid = false;
            }

            // Check each peer
            for (uint256 j = 0; j < CHAINS.length; j++) {
                if (i == j) continue;

                bytes32 peer = guestbook.peers(CHAINS[j].eid);
                if (peer == bytes32(0)) {
                    console2.log("ERROR: Missing peer for", CHAINS[j].name);
                    allValid = false;
                }
            }

            console2.log("Status:", allValid ? "VALID" : "INVALID");
            console2.log("");
        }

        console2.log("=== Validation", allValid ? "PASSED" : "FAILED", "===");

        if (allValid) {
            console2.log("\nReady for testing!");
            console2.log("Test with: cast send <ADDRESS> \"signGuestbookFor(address,string,string,bytes)\" ...");
        }
    }

    /**
     * @notice Helper to display deployment info
     */
    function showDeployments() public {
        string memory deploymentsJson = vm.readFile(DEPLOYMENTS_FILE);

        console2.log("=== Deployed Contracts ===\n");

        for (uint256 i = 0; i < CHAINS.length; i++) {
            string memory key = string.concat(".", CHAINS[i].name, ".address");
            address addr = deploymentsJson.readAddress(key);

            console2.log(CHAINS[i].name);
            console2.log("  Address:", addr);
            console2.log("  EID:", CHAINS[i].eid);
            console2.log("  As bytes32:", vm.toString(bytes32(uint256(uint160(addr)))));
            console2.log("");
        }
    }
}
