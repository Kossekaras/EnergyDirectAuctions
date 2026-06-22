// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";

/// @notice Local stand-in for a real Chainlink ETH/USD Data Feed. Deployed with
///         (decimals, initialAnswer); the keeper writes the live Kraken price into
///         it each cycle. Concrete subclass so Hardhat emits a deployable artifact
///         for it (imported-only contracts are not emitted).
contract MockPriceFeed is MockV3Aggregator {
    constructor(uint8 _decimals, int256 _initialAnswer)
        MockV3Aggregator(_decimals, _initialAnswer)
    {}
}
