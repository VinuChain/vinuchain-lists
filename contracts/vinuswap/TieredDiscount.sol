// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../core/interfaces/IFeeManager.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

/// @title Tiered Discount Fee Manager
/// @notice Provides swap fee discounts depending on the token balance of the user
contract TieredDiscount is IFeeManager, Ownable {
    uint256 public constant DENOMINATOR = 10000;

    /// @notice The token to use for fee discounts
    address public token;
    /// @notice The thresholds for the discounts
    uint256[] public thresholds;
    /// @notice The discounts for the thresholds (in bips)
    uint16[] public discounts;

    /// @notice Contract constructor
    /// @param _token The token to use for fee discounts
    /// @param _thresholds The thresholds for the discounts
    /// @param _discounts The discounts for the thresholds (in bips)
    constructor (address _token, uint256[] memory _thresholds, uint16[] memory _discounts) {
        updateInfo(_token, _thresholds, _discounts);
    }
    /// @notice Contract constructor
    /// @param _token The token to use for fee discounts
    /// @param _thresholds The thresholds for the discounts
    /// @param _discounts The discounts for the thresholds (in bips)
    function updateInfo(address _token, uint256[] memory _thresholds, uint16[] memory _discounts) public onlyOwner() {
        require(_thresholds.length > 0, "Thresholds must not be empty");
        require(_thresholds.length == _discounts.length, "Thresholds and discounts must have the same length");

        for (uint256 i = 0; i < _thresholds.length; i++) {
            require(_thresholds[i] > 0, "Thresholds must be positive");
            require(_discounts[i] <= DENOMINATOR, "Discounts must not be higher than 100%");

            if (i > 0) {
                require(_thresholds[i] > _thresholds[i - 1], "Thresholds must be strictly increasing");
                require(_discounts[i] > _discounts[i - 1], "Discounts must be strictly increasing");
            }
        }

        token = _token;
        thresholds = _thresholds;
        discounts = _discounts;
    }

    /// @inheritdoc IFeeManager
    function computeFee(uint24 fee) external view override returns (uint24) {
        // Note the usage of tx.origin instead of msg.sender
        return computeFeeFor(fee, tx.origin);
    }

    /// @notice Computes the fee for an arbitrary address
    /// @param fee The original fee (in hundredths of a bip), as computed by the pool
    /// @param recipient The address for which the fee is computed
    /// @return uint24 The fee to be charged to recipient
    function computeFeeFor(
        uint24 fee,
        address recipient
    ) public view returns (uint24) {
        uint256 balance = IERC20(token).balanceOf(recipient);

        uint16 bestDiscount = 0;

        for (uint256 i = 0; i < thresholds.length; i++) {
            if (balance >= thresholds[i]) {
                bestDiscount = discounts[i];
            } else {
                break;
            }
        }

        // Never underflows, since bestDiscount <= DENOMINATOR
        uint256 coefficient = DENOMINATOR - bestDiscount;

        // Never overflows, since coefficient is in [0, 10000] and DENOMINATOR = 10000
        return uint24(uint256(fee) * coefficient / DENOMINATOR);
    }
}