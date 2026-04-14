// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IBasePool} from "./interfaces/IBasePool.sol";

/// @title MultiClaim
/// @author Samuele Marro
/// @notice Allows a user to claim multiple non-consecutive loans in a single transaction
contract MultiClaim {
    using SafeERC20 for IERC20;

    /// @notice Claims multiple contracts 
    ///
    /// @dev Calling with [[1, 2], 3] and [1, 0] will claim loan indexes 1 and 2 (reinvesting)
    ///      and then claim loan index 3 (not reinvesting)
    ///
    /// @param _pool Pool for which to claim
    /// @param _loanIdxs Array of arrays of loan indexes to claim
    /// @param _isReinvested Whether, for each sub-array, the claim should be reinvested
    /// @param _deadline Deadline by which to execute the transaction
    function claimMultiple(
        IBasePool _pool,
        uint256[][] calldata _loanIdxs,
        bool[] calldata _isReinvested,
        uint256 _deadline
    ) external {
        require(_loanIdxs.length > 0, "MultiClaim: Empty loan index array.");
        require(
            _loanIdxs.length == _isReinvested.length,
            "MultiClaim: Inconsistent lengths."
        );
        (IERC20 loanCcyToken, IERC20 collCcyToken, , , , , , , ) = _pool.getPoolInfo();

        uint256 loanCcyBalanceBefore = loanCcyToken.balanceOf(address(this));
        uint256 collCcyBalanceBefore = collCcyToken.balanceOf(address(this));
        
        for (uint256 i = 0; i < _loanIdxs.length; i++) {
            require(
                _loanIdxs[i].length > 0,
                "MultiClaim: Empty loan index sub-array."
            );
            _pool.claim(
                msg.sender,
                _loanIdxs[i],
                _isReinvested[i],
                _deadline
            );
        }

        // Transfer the loan currency to the user
        uint256 loanCcyBalanceAfter = loanCcyToken.balanceOf(address(this));
        uint256 loanCcyBalanceDiff = loanCcyBalanceAfter - loanCcyBalanceBefore;

        // Transfer the collateral currency to the user
        uint256 collCcyBalanceAfter = collCcyToken.balanceOf(address(this));
        uint256 collCcyBalanceDiff = collCcyBalanceAfter - collCcyBalanceBefore;

        if (loanCcyBalanceDiff > 0) {
            loanCcyToken.safeTransfer(msg.sender, loanCcyBalanceDiff);
        }
        if (collCcyBalanceDiff > 0) {
            collCcyToken.safeTransfer(msg.sender, collCcyBalanceDiff);
        }
    }
}