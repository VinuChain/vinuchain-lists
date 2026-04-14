// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IVinuSwapFactory.sol';

import './VinuSwapPoolDeployer.sol';
import './NoDelegateCall.sol';

import './VinuSwapPool.sol';

/// @title Canonical VinuSwap factory
/// @notice Deploys VinuSwap pools and manages ownership and control over pool protocol fees
contract VinuSwapFactory is IVinuSwapFactory, VinuSwapPoolDeployer, NoDelegateCall {
    /// @inheritdoc IVinuSwapFactory
    address public override owner;

    /// @inheritdoc IVinuSwapFactory
    mapping(address => mapping(address => mapping(uint24 => address))) public override getPool;

    constructor() {
        owner = msg.sender;
        emit OwnerChanged(address(0), msg.sender);
    }

    /// @inheritdoc IVinuSwapFactory
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickSpacing,
        address feeManager
    ) external override noDelegateCall returns (address pool) {
        require(msg.sender == owner);

        require(tokenA != tokenB);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));

        require(fee < 1000000);

        // tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
        // TickBitmap#nextInitializedTickWithinOneWord overflows int24 container from a valid tick
        // 16384 ticks represents a >5x price change with ticks of 1 bips
        require(tickSpacing > 0 && tickSpacing < 16384);

        require(getPool[token0][token1][fee] == address(0));
        pool = deploy(address(this), token0, token1, fee, tickSpacing, feeManager);

        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;

        emit PoolCreated(token0, token1, fee, tickSpacing, feeManager, pool);
    }

    /// @inheritdoc IVinuSwapFactory
    function setOwner(address _owner) external override {
        require(msg.sender == owner);
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }
}
