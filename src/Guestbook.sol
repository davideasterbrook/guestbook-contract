// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OApp, MessagingFee, MessagingReceipt, Origin} from "@layerzero-v2/packages/layerzero-v2/evm/oapp/contracts/oapp/OApp.sol";

/**
 * @title Guestbook
 * @notice Event-based multi-chain guestbook
 * @dev Uses LayerZero v2 for cross-chain messaging.
 *
 * Features:
 * - Every signature is automatically broadcast to ALL registered chains
 * - Owner controls:
 *   - Create signatures on behalf of others (for bootstrapping)
 *   - Batch emit historical signatures to new chains/contracts
 *
 * Data Access:
 * - Off-chain queries: Use third-party tool such as The Graph subgraph to index events
 */
contract Guestbook is Ownable, OApp {

    // ============ Errors ============

    /// @notice Thrown when attempting to set the current chain as a peer
    error CannotAddCurrentChain();

    /// @notice Thrown when insufficient fee is provided for cross-chain broadcast
    error InsufficientFee();

    /// @notice Thrown when no signatures are provided to batch emit
    error NoSignaturesToEmit();

    /// @notice Thrown when refund transfer fails
    error RefundFailed();

    // ============ Events ============

    /**
     * @notice Emitted when someone signs the guestbook (locally or via cross-chain message)
     * @param signer The address that signed the guestbook
     * @param sourceChainId The chain ID where the signature originated
     * @param name The display name provided by the signer
     * @param message The message content
     * @param timestamp The block timestamp when the signature was created
     */
    event SignedGuestbook(
        address indexed signer,
        uint32 indexed sourceChainId,
        string name,
        string message,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a new chain is added to the registry
     * @param chainEid The LayerZero endpoint ID of the added chain
     */
    event ChainAdded(uint32 indexed chainEid);

    /**
     * @notice Emitted when a chain is removed from the registry
     * @param chainEid The LayerZero endpoint ID of the removed chain
     */
    event ChainRemoved(uint32 indexed chainEid);

    // ============ Storage ============

    /// @notice Array of registered chain endpoint IDs for auto-broadcasting
    uint32[] private _registeredChains;

    /// @notice The LayerZero endpoint ID for this chain
    uint32 private immutable _localEid;

    // ============ Constructor ============

    /**
     * @notice Initialize the Guestbook contract
     * @param _endpoint The LayerZero endpoint address for this chain
     * @param _delegate The address that will own this contract and manage LayerZero settings
     * @param localChainEid The LayerZero endpoint ID for this chain
     */
    constructor(
        address _endpoint,
        address _delegate,
        uint32 localChainEid
    )
        Ownable(_delegate)
        OApp(_endpoint, _delegate)
    {
        _localEid = localChainEid;
    }

    // ============ Fee Handling ============

    /**
     * @notice Override to change fee check from equivalency to >= since batch fees are cumulative
     * @dev Allows msg.value to exceed the required fee, with excess refunded to sender
     * @param _nativeFee The required native fee amount
     * @return nativeFee The native fee amount to use
     */
    function _payNative(uint256 _nativeFee) internal override returns (uint256 nativeFee) {
        if (msg.value < _nativeFee) revert NotEnoughNative(msg.value);
        return _nativeFee;
    }

    // ============ Peer & Chain Registry Management ============

    /**
     * @notice Set a peer and automatically register it for broadcasting
     * @dev Overrides OApp's setPeer to automatically manage the broadcast registry.
     *      Setting a peer with a non-zero address adds the chain to the broadcast list.
     *      Setting a peer to bytes32(0) removes it from the broadcast list.
     * @param _eid The LayerZero endpoint ID of the peer chain
     * @param _peer The peer Guestbook contract address (as bytes32), or bytes32(0) to remove
     */
    function setPeer(uint32 _eid, bytes32 _peer) public override onlyOwner {
        // Validate not setting current chain as peer
        if (_eid == _localEid) revert CannotAddCurrentChain();

        // Set the peer in OApp
        super.setPeer(_eid, _peer);

        bool isInArray = _isChainInArray(_eid);

        // If setting a non-zero peer, add to registry (if not already there)
        if (_peer != bytes32(0)) {
            if (!isInArray) {
                _registeredChains.push(_eid);
                emit ChainAdded(_eid);
            }
        }
        // If removing peer (setting to zero), remove from registry
        else {
            if (isInArray) {
                _removeChainFromArray(_eid);
                emit ChainRemoved(_eid);
            }
        }
    }

    /**
     * @notice Get all registered chains
     * @return Array of chain endpoint IDs
     */
    function getRegisteredChains() external view returns (uint32[] memory) {
        return _registeredChains;
    }

    /**
     * @notice Check if a chain is registered
     * @param chainEid The chain endpoint ID to check
     * @return True if the chain is registered
     */
    function isChainRegistered(uint32 chainEid) external view returns (bool) {
        return _isChainInArray(chainEid);
    }

    /**
     * @notice Get the LayerZero endpoint ID for this chain
     * @return The local endpoint ID
     */
    function localEid() external view returns (uint32) {
        return _localEid;
    }

    /**
     * @notice Internal helper to check if a chain exists in the array
     * @param chainEid The chain endpoint ID to check
     * @return True if the chain is in the array
     */
    function _isChainInArray(uint32 chainEid) private view returns (bool) {
        for (uint256 i = 0; i < _registeredChains.length; i++) {
            if (_registeredChains[i] == chainEid) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Internal helper to remove a chain from the array
     * @dev Uses swap-and-pop for O(1) removal
     * @param chainEid The chain endpoint ID to remove
     */
    function _removeChainFromArray(uint32 chainEid) private {
        for (uint256 i = 0; i < _registeredChains.length; i++) {
            if (_registeredChains[i] == chainEid) {
                _registeredChains[i] = _registeredChains[_registeredChains.length - 1];
                _registeredChains.pop();
                return;
            }
        }
    }

    // ============ Multi-Chain Signature Functions ============

    /**
     * @notice Data structure for batch syncing signatures
     * @dev Used for cross-chain messages
     */
    struct SignatureData {
        address signer;
        uint32 sourceChainId;
        string name;
        string message;
        uint256 timestamp;
    }

    /**
     * @notice Get total fee for broadcasting a signature to all registered chains
     * @dev WARNING: Gas cost scales linearly with number of registered chains. May be expensive with many chains.
     * @param signer The address that will sign the guestbook
     * @param name The display name
     * @param message The message content
     * @param options LayerZero options
     * @return totalNativeFee The total native token fee required
     */
    function quoteBroadcast(
        address signer,
        string calldata name,
        string calldata message,
        bytes calldata options
    ) public view returns (uint256 totalNativeFee) {
        SignatureData memory sig = SignatureData({
            signer: signer,
            sourceChainId: uint32(block.chainid),
            name: name,
            message: message,
            timestamp: block.timestamp
        });

        return _quoteBroadcast(sig, options);
    }

    /**
     * @notice Internal function to calculate total fee for broadcasting a signature
     * @dev WARNING: Gas cost scales linearly with number of registered chains. May be expensive with many chains.
     * @param sig The signature data to broadcast
     * @param options LayerZero options
     * @return totalNativeFee The total native token fee required
     */
    function _quoteBroadcast(
        SignatureData memory sig,
        bytes calldata options
    ) internal view returns (uint256 totalNativeFee) {
        if (_registeredChains.length == 0) return 0;

        bytes memory payload = abi.encode(sig);

        for (uint256 i = 0; i < _registeredChains.length; i++) {
            MessagingFee memory fee = _quote(_registeredChains[i], payload, options, false);
            totalNativeFee += fee.nativeFee;
        }
    }

    /**
     * @notice Sign the guestbook - automatically broadcasts to all registered chains
     * @param name Your display name
     * @param message Your message
     * @param options LayerZero message options (can be empty for defaults)
     */
    function signGuestbook(
        string calldata name,
        string calldata message,
        bytes calldata options
    ) external payable {
        signGuestbookFor(msg.sender, name, message, options);
    }

    /**
     * @notice Sign the guestbook on behalf of another address (owner only) and broadcast to all registered chains
     * @param signer The address to attribute the signature to
     * @param name The display name
     * @param message The message content
     * @param options LayerZero message options (can be empty for defaults)
     */
    function signGuestbookFor(
        address signer,
        string calldata name,
        string calldata message,
        bytes calldata options
    ) public payable {
        // Only owner can sign for others, anyone can sign for themselves
        if (signer != msg.sender) {
            _checkOwner();
        }

        // Build signature data once for consistency
        SignatureData memory sig = SignatureData({
            signer: signer,
            sourceChainId: uint32(block.chainid),
            name: name,
            message: message,
            timestamp: block.timestamp
        });

        // Gas efficiency: calculate total fees upfront (fail-fast pattern)
        uint256 totalFee = _quoteBroadcast(sig, options);
        if (msg.value < totalFee) revert InsufficientFee();

        // Create local signature
        _createSignature(sig.signer, sig.sourceChainId, sig.name, sig.message, sig.timestamp);

        // Broadcast to all registered chains
        _broadcastSignature(sig, options);
    }

    /**
     * @notice Internal function to create a signature (emits event only)
     * @dev No storage - purely event-based. Subgraph indexes this event.
     *      Used for both local signatures and cross-chain received signatures.
     * @param signer The address that is signing
     * @param sourceChainId The chain where the signature originated
     * @param name The display name
     * @param message The message content
     * @param timestamp The timestamp of the signature
     */
    function _createSignature(
        address signer,
        uint32 sourceChainId,
        string memory name,
        string memory message,
        uint256 timestamp
    ) internal {
        emit SignedGuestbook(
            signer,
            sourceChainId,
            name,
            message,
            timestamp
        );
    }

    /**
     * @notice Broadcast a signature to all registered chains
     * @dev Internal function called after creating local signature.
     *      Each chain gets exactly the fee it needs, excess is refunded.
     *      WARNING: Gas cost scales linearly with number of registered chains. May hit block gas limit with many chains.
     * @param sig The signature data to broadcast
     * @param options LayerZero options
     */
    function _broadcastSignature(
        SignatureData memory sig,
        bytes calldata options
    ) internal {
        if (_registeredChains.length == 0) return;

        bytes memory payload = abi.encode(sig);
        uint256 remainingValue = msg.value;

        for (uint256 i = 0; i < _registeredChains.length; i++) {
            // Get actual fee for this specific chain
            MessagingFee memory fee = _quote(_registeredChains[i], payload, options, false);

            if (remainingValue < fee.nativeFee) revert InsufficientFee();

            _lzSend(
                _registeredChains[i],
                payload,
                options,
                MessagingFee(fee.nativeFee, 0),
                payable(msg.sender)
            );

            remainingValue -= fee.nativeFee;
        }

        // Refund excess
        if (remainingValue > 0) {
            (bool success, ) = payable(msg.sender).call{value: remainingValue}("");
            if (!success) revert RefundFailed();
        }
    }

    // ============ Historical Sync Functions ============

    /**
     * @notice Batch emit historical signatures on this chain (owner only)
     * @dev Owner fetches historical data from The Graph subgraph and calls this locally on each chain.
     *      This is cheaper than cross-chain sync via LayerZero.
     *      WARNING: Gas cost scales linearly with array length. Large batches may hit block gas limit.
     * @param signatures Array of signature data to emit as events
     */
    function batchEmitSignatures(SignatureData[] calldata signatures) external onlyOwner {
        if (signatures.length == 0) revert NoSignaturesToEmit();

        for (uint256 i = 0; i < signatures.length; i++) {
            _createSignature(
                signatures[i].signer,
                signatures[i].sourceChainId,
                signatures[i].name,
                signatures[i].message,
                signatures[i].timestamp
            );
        }
    }

    // ============ LayerZero Message Handling ============

    /**
     * @notice Receive and process cross-chain messages from LayerZero
     * @dev Decodes and emits a single signature received from another chain
     * @param _message The encoded message payload containing a single SignatureData struct
     */
    function _lzReceive(
        Origin calldata,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        SignatureData memory sig = abi.decode(_message, (SignatureData));

        _createSignature(
            sig.signer,
            sig.sourceChainId,
            sig.name,
            sig.message,
            sig.timestamp
        );
    }
}
