// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IBasePool.sol";

/// @title EmergencyWithdrawal
/// @author Samuele Marro
/// @notice Allows an escrow to withdraw on behalf of a user in case of emergency
contract EmergencyWithdrawal is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Emitted when a user approves an escrow to withdraw on its behalf
    ///
    /// @param user User that approved the escrow
    /// @param pool Pool that the user approved the escrow for
    /// @param escrow Escrow that the user approved
    event Approved(
        address indexed user,
        address indexed pool,
        address indexed escrow
    );

    /// @notice Emitted when a user unapproves an escrow to withdraw on its behalf
    ///
    /// @param user User that unapproved the escrow
    /// @param pool Pool that the user unapproved the escrow for
    /// @param escrow Escrow that the user unapproved
    event Unapproved(
        address indexed user,
        address indexed pool,
        address indexed escrow
    );

    /// @notice Emitted when an escrow withdraws on behalf of a user
    ///
    /// @param user User that the escrow withdrew on behalf of
    /// @param pool Pool that the escrow withdrew from
    /// @param escrow Escrow that withdrew
    /// @param token Token that was withdrawn
    /// @param amount Amount of tokens withdrawn
    event Withdrawal(
        address indexed user,
        address indexed pool,
        address indexed escrow,
        IERC20 token,
        uint256 amount
    );

    // Mapping of user => pool => escrow => approved
    mapping(address => mapping(address => mapping(address => bool)))
        private approved;

    /// @notice Approve an escrow to withdraw on behalf of the user
    ///
    /// @param _pool Pool that the escrow is approved for
    /// @param _escrow Escrow that is approved
    function approve(address _pool, address _escrow) external {
        approved[msg.sender][_pool][_escrow] = true;
        emit Approved(msg.sender, _pool, _escrow);
    }

    /// @notice Unapprove an escrow to withdraw on behalf of the user
    ///
    /// @param _pool Pool that the escrow is unapproved for
    /// @param _escrow Escrow that is unapproved
    function unapprove(address _pool, address _escrow) external {
        approved[msg.sender][_pool][_escrow] = false;
        emit Unapproved(msg.sender, _pool, _escrow);
    }

    /// @notice Returns true if an escrow is approved to withdraw on behalf of the user from a given pool
    ///
    /// @param _user User to check
    /// @param _pool Pool to check
    /// @param _escrow Escrow to check
    function isApproved(
        address _user,
        address _pool,
        address _escrow
    ) public view returns (bool) {
        return approved[_user][_pool][_escrow];
    }

    /// @notice Withdraws all of a user's funds from a pool and returns them to the user
    ///
    /// @dev This function is only callable by an escrow that has been approved by the user
    ///      Note that this means that unless a user approves itself, it cannot withdraw its own funds
    ///      through this contract (which is intended behavior)
    /// @param _pool Pool to withdraw from
    /// @param _onBehalfOf User to withdraw for
    function collectEmergency(
        IBasePool _pool,
        address _onBehalfOf
    ) external nonReentrant {
        require(
            isApproved(_onBehalfOf, address(_pool), msg.sender),
            "Not approved"
        );

        (IERC20 token, , , , , , , , ) = _pool.getPoolInfo();

        // Store the amount of tokens before the withdraw
        uint256 amountBefore = token.balanceOf(address(this));

        (, , , uint256[] memory sharesOverTime, ) = _pool.getLpInfo(
            _onBehalfOf
        );

        // Get the last number of shares
        require(sharesOverTime.length > 0, "No shares");
        uint128 shares = uint128(sharesOverTime[sharesOverTime.length - 1]);
        require(shares > 0, "No shares");

        // Withdraw all shares
        _pool.removeLiquidity(_onBehalfOf, shares);

        // Store the amount of tokens after the withdrawal
        uint256 amountAfter = token.balanceOf(address(this));

        // Calculate the amount of tokens to transfer
        uint256 amount = amountAfter - amountBefore;

        // Transfer the tokens to the user
        token.safeTransfer(_onBehalfOf, amount);

        emit Withdrawal(_onBehalfOf, address(_pool), msg.sender, token, amount);
    }
}
