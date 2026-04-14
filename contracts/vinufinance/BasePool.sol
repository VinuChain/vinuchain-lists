// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBasePool} from "./interfaces/IBasePool.sol";
import "./interfaces/IPausable.sol";
import "./interfaces/IController.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract BasePool is IBasePool, Pausable, IPausable {
    using SafeERC20 for IERC20;

    // Minimum period between adding liqudity and removing it, in seconds
    uint256 constant MIN_LPING_PERIOD = 120;

    // Minimum loan tenor, in seconds
    uint256 constant MIN_TENOR = 86400;
    uint256 constant BASE = 10 ** 18;

    // Maximum creator fee, denominated in BASE
    uint256 constant MAX_FEE = 300 * 10 ** 14; // 300bps

    // Minimum liquidity, denominated in loanCcy decimals
    uint256 public override minLiquidity;

    // Address of the controller contract
    IController public poolController;

    // Collateral token
    IERC20 collCcyToken;
    // Loan token
    IERC20 loanCcyToken;

    // Total LP shares. Denominated and discretized in 1/1000th of minLiquidity
    uint128 totalLpShares;

    // Loan duration, in seconds
    uint256 loanTenor;
    
    // Decimals of the collateral token
    uint256 public override collTokenDecimals;

    // Maximum loan per unit of collateral, denominated in loanCcy decimals
    uint256 maxLoanPerColl;

    // Creator fee, denominated in BASE
    uint256 creatorFee;

    // Total liquidity, denominated in loanCcy decimals
    uint256 totalLiquidity;

    // Current loan index
    uint256 loanIdx;

    // Interest rate parameters
    uint256 r1; // Denominated in BASE and w.r.t. tenor (i.e., not annualized)
    uint256 r2; // Denominated in BASE and w.r.t. tenor (i.e., not annualized)
    uint256 liquidityBnd1; // Denominated in loanCcy decimals
    uint256 liquidityBnd2; // Denominated in loanCcy decimals

    // Minimum loan, denominated in loanCcy decimals
    uint256 minLoan;

    // LP infos
    mapping(address => LpInfo) addrToLpInfo;

    // Used to prevent flash loans
    mapping(address => uint256) lastAddOfTxOrigin;

    // Loan infos
    mapping(uint256 => LoanInfo) public loanIdxToLoanInfo;

    // Borrower of a loan
    mapping(uint256 => address) public override loanIdxToBorrower;

    // Whether an address is approved to perform a certain action
    mapping(address => mapping(address => mapping(IBasePool.ApprovalTypes => bool)))
        public override isApproved;

    // Timestamp of the last reward of an address
    mapping(address => uint32) public lastRewardTimestamp;

    // Last tracked liquidity of an address
    mapping(address => uint128) public lastTrackedLiquidity;

    // Reward coefficient, denominated in BASE
    uint96 rewardCoefficient;

    /**
     * @notice Creates a new pool
     *
     * @dev Solidity has a stack limit which prevents having too many parameters.
     * As a workaround, we use two-element arrays when it's sufficiently intuitive
     *
     * @param _tokens [loanCcyToken, collCcyToken] Tokens used for the pool
     * @param _loanTenor Duration of a loan, in seconds
     * @param _maxLoanPerColl Maximum loan per unit of collateral, denominated in loanCcy decimals
     * @param _rs [r1, r2] Interest rate parameters, denominated in BASE and w.r.t. tenor (i.e., not annualized)
     * @param _liquidityBnds [liquidityBnd1, liquidityBnd2] Liqudity parameters, denominated in loanCcy decimals
     * @param _minLoan Minimum loan, denominated in loanCcy decimals
     * @param _creatorFee Creator fee, denominated in BASE
     * @param _minLiquidity Minimum liquidity, denominated in loanCcy decimals
     * @param _poolController Address of the controller contract
     * @param _rewardCoefficient Reward coefficient, denominated in BASE
    */
    constructor(
        IERC20[] memory _tokens,
        uint256 _collTokenDecimals,
        uint256 _loanTenor,
        uint256 _maxLoanPerColl,
        uint256[] memory _rs,
        uint256[] memory _liquidityBnds,
        uint256 _minLoan,
        uint256 _creatorFee,
        uint256 _minLiquidity,
        IController _poolController,
        uint96 _rewardCoefficient
    ) {
        require(_tokens.length == 2, "Tokens length must be 2.");
        require(_rs.length == 2, "Rs length must be 2.");
        require(_liquidityBnds.length == 2, "Liquidity bounds length must be 2.");

        require(_poolController.supportsInterface(type(IController).interfaceId), "Invalid Controller.");

        require(_tokens[0] != _tokens[1], "Loan and collateral must not be the same.");
        if (address(_tokens[0]) == address(0) || address(_tokens[1]) == address(0))
            revert("Loan and collateral tokens must not be 0.");
        require(_loanTenor >= MIN_TENOR, "Loam tenor must be at least MIN_TENOR.");
        require(_maxLoanPerColl > 0, "Max loan must not be 0.");
        if (_rs[0] <= _rs[1] || _rs[1] == 0) revert("Invalid rate parameters.");
        if (_liquidityBnds[1] <= _liquidityBnds[0] || _liquidityBnds[0] == 0)
            revert("Invalid liquidity bounds");
        // ensure LP shares can be minted based on 1/1000th of minLp discretization
        require(_minLiquidity >= 1000, "Min liquidity must be at least 1000.");
        require(_creatorFee <= MAX_FEE, "Creator fee too high.");
        loanCcyToken = _tokens[0];
        collCcyToken = _tokens[1];
        loanTenor = _loanTenor;
        maxLoanPerColl = _maxLoanPerColl;
        r1 = _rs[0];
        r2 = _rs[1];
        liquidityBnd1 = _liquidityBnds[0];
        liquidityBnd2 = _liquidityBnds[1];
        minLoan = _minLoan;
        loanIdx = 1;
        collTokenDecimals = _collTokenDecimals;
        creatorFee = _creatorFee;
        minLiquidity = _minLiquidity;
        poolController = _poolController;
        rewardCoefficient = _rewardCoefficient;

        emit NewSubPool(
            loanCcyToken,
            collCcyToken,
            _loanTenor,
            _maxLoanPerColl,
            r1,
            r2,
            liquidityBnd1,
            liquidityBnd2,
            _minLoan,
            _creatorFee,
            address(poolController),
            rewardCoefficient
        );
    }

    /**
     * @notice Adds liquidity to the pool
     *
     * @param _onBehalfOf Address to add liquidity on behalf of
     * @param _deadline Deadline for the transaction
     * @param _referralCode Referral code. Optional
     */
    function addLiquidity(
        address _onBehalfOf,
        uint128 _sendAmount,
        uint256 _deadline,
        uint256 _referralCode
    ) external override payable {
        // verify LP info and eligibility
        checkTimestamp(_deadline);
        checkSenderApproval(_onBehalfOf, IBasePool.ApprovalTypes.ADD_LIQUIDITY);

        (
            uint256 dust,
            uint256 newLpShares,
            uint32 earliestRemove
        ) = _addLiquidity(_onBehalfOf, _sendAmount);


        _updateRewardAndSend(_onBehalfOf, lastTrackedLiquidity[_onBehalfOf] + _sendAmount);

        loanCcyToken.safeTransferFrom(msg.sender, address(this), _sendAmount);

        // transfer dust to creator if any
        if (dust > 0) {
            _depositRevenue(loanCcyToken, dust);
        }
        // spawn event
        emit AddLiquidity(
            _onBehalfOf,
            _sendAmount,
            newLpShares,
            totalLiquidity,
            totalLpShares,
            earliestRemove,
            loanIdx,
            _referralCode
        );
    }

    /**
     * @notice Removes liquidity from the pool. The removed amount is
     * propositional to the number of shares
     * 
     * @param _onBehalfOf Address to remove liquidity on behalf of
     * @param numShares Number of shares to remove
     */
    function removeLiquidity(
        address _onBehalfOf,
        uint128 numShares
    ) external override {
        delete lastAddOfTxOrigin[_onBehalfOf];
        // verify LP info and eligibility
        checkSenderApproval(
            _onBehalfOf,
            IBasePool.ApprovalTypes.REMOVE_LIQUIDITY
        );

        LpInfo storage lpInfo = addrToLpInfo[_onBehalfOf];
        uint256 shareLength = lpInfo.sharesOverTime.length;
        if (
            shareLength * numShares == 0 ||
            lpInfo.sharesOverTime[shareLength - 1] < numShares
        ) revert("Invalid removal operation.");
        if (block.timestamp < lpInfo.earliestRemove)
            revert("Too early to remove.");
        uint256 _totalLiquidity = totalLiquidity;
        uint128 _totalLpShares = totalLpShares;
        // update state of pool
        uint256 liquidityRemoved = (numShares *
            (_totalLiquidity - minLiquidity)) / _totalLpShares;
        totalLpShares -= numShares;
        totalLiquidity = _totalLiquidity - liquidityRemoved;

        // update LP arrays and check for auto increment
        updateLpArrays(lpInfo, numShares, false);

        _updateRewardAndSend(_onBehalfOf, lastTrackedLiquidity[_onBehalfOf] - liquidityRemoved);

        // transfer liquidity
        loanCcyToken.safeTransfer(msg.sender, liquidityRemoved);
        // spawn event
        emit RemoveLiquidity(
            _onBehalfOf,
            liquidityRemoved,
            numShares,
            totalLiquidity,
            _totalLpShares - numShares,
            loanIdx
        );
    }

    /**
     * @notice Borrows funds from the pool
     * 
     * @dev It is possible to borrow funds on behalf of someone else; that
     * someone else will be the one to receive the funds Note that in such
     * case, the caller still needs to provide the collateral, so there is
     * no financial incentive to borrow funds on behalf of someone else for
     * malicious purposes.
     *
     * @dev When the contract is paused, this function cannot be called
     *
     * @param _onBehalfOf Address to borrow on behalf of
     * @param _sendAmount Amount of collateral to send
     * @param _minLoanLimit Minimum loan amount
     * @param _maxRepayLimit Maximum repayment amount
     * @param _deadline Deadline for the transaction
     * @param _referralCode Referral code. Optional
     */
    function borrow(
        address _onBehalfOf,
        uint128 _sendAmount,
        uint128 _minLoanLimit,
        uint128 _maxRepayLimit,
        uint256 _deadline,
        uint256 _referralCode
    ) external payable override whenNotPaused {
        uint256 _timestamp = checkTimestamp(_deadline);
        // check if atomic add and borrow as well as sanity check of onBehalf address
        if (
            lastAddOfTxOrigin[tx.origin] == _timestamp ||
            _onBehalfOf == address(0)
        ) revert("Invalid operation.");
        // get borrow terms and do checks
        (
            uint128 loanAmount,
            uint128 repaymentAmount,
            uint128 pledgeAmount,
            uint32 expiry,
            uint256 _creatorFee,
            uint256 _totalLiquidity
        ) = _borrow(
                _sendAmount,
                _minLoanLimit,
                _maxRepayLimit,
                _timestamp
            );
        {
            // update pool state
            totalLiquidity = _totalLiquidity - loanAmount;

            uint256 _loanIdx = loanIdx;
            uint128 _totalLpShares = totalLpShares;

            // update loan info
            loanIdxToBorrower[_loanIdx] = _onBehalfOf;
            LoanInfo memory loanInfo;
            loanInfo.repayment = repaymentAmount;
            loanInfo.totalLpShares = _totalLpShares;
            loanInfo.expiry = expiry;
            loanInfo.collateral = pledgeAmount;
            loanInfo.loanAmount = loanAmount;
            loanIdxToLoanInfo[_loanIdx] = loanInfo;

            // update loan idx counter
            loanIdx = _loanIdx + 1;
        }
        {
            // we first retrieve the tokens because we might not have enough balance
            // to pay the creator fee
            collCcyToken.safeTransferFrom(msg.sender, address(this), _sendAmount);

            // transfer creator fee to creator in collateral ccy
            _depositRevenue(collCcyToken, _creatorFee);

            // transfer loanAmount in loan ccy
            loanCcyToken.safeTransfer(msg.sender, loanAmount);
        }
        // spawn event
        emit Borrow(
            _onBehalfOf,
            loanIdx - 1,
            pledgeAmount,
            loanAmount,
            repaymentAmount,
            totalLpShares,
            expiry,
            _referralCode
        );
    }


    /**
     * @notice Repays a loan
     *
     * @dev Only senders approved by the borrower can repay the loan
     *
     * @param _loanIdx Index of the loan to repay
     * @param _recipient Address to receive the funds
     */
    function repay(
        uint256 _loanIdx,
        address _recipient
    ) external payable override {
        // verify loan info and eligibility
        if (_loanIdx == 0 || _loanIdx >= loanIdx) revert("Invalid loan index.");
        address _loanOwner = loanIdxToBorrower[_loanIdx];

        if (!(_loanOwner == _recipient || msg.sender == _recipient))
            revert("Invalid recipient.");
        checkSenderApproval(_loanOwner, IBasePool.ApprovalTypes.REPAY);

        LoanInfo storage loanInfo = loanIdxToLoanInfo[_loanIdx];
        uint256 timestamp = block.timestamp;
        if (timestamp > loanInfo.expiry) revert("Cannot repay after expiry.");
        if (loanInfo.repaid) revert("Already repaid.");
        if (timestamp == loanInfo.expiry - loanTenor)
            revert("Cannot repay in the same block.");
        // update loan info
        loanInfo.repaid = true;

        loanCcyToken.safeTransferFrom(msg.sender, address(this), loanInfo.repayment);
        // transfer collateral to _recipient (allows for possible
        // transfer directly to someone other than payer/sender)
        collCcyToken.safeTransfer(_recipient, loanInfo.collateral);
        // spawn event
        emit Repay(_loanOwner, _loanIdx, loanInfo.repayment);
    }

    /**
     * @notice Claims the rewards for a given loan
     *
     * @dev Only senders approved by the LP can claim the on the LP's
     * behalf
     *
     * @param _onBehalfOf Address to claim on behalf of
     * @param _loanIdxs Indices of the loans to claim for
     */
    function claim(
        address _onBehalfOf,
        uint256[] calldata _loanIdxs,
        bool _isReinvested,
        uint256 _deadline
    ) external override {
        // check if reinvested is chosen that deadline is valid and sender can add liquidity on behalf of
        if (_isReinvested) {
            claimReinvestmentCheck(_deadline, _onBehalfOf);
        }
        checkSenderApproval(_onBehalfOf, IBasePool.ApprovalTypes.CLAIM);
        LpInfo storage lpInfo = addrToLpInfo[_onBehalfOf];

        // verify LP info and eligibility
        if (_loanIdxs.length * lpInfo.sharesOverTime.length == 0) revert("Nothing to claim.");
        if (_loanIdxs[0] == 0) revert("Invalid loan index.");

        (
            uint256 sharesUnchangedUntilLoanIdx,
            uint256 applicableShares
        ) = claimsChecksAndSetters(
                _loanIdxs[0],
                _loanIdxs[_loanIdxs.length - 1],
                lpInfo
            );

        // iterate over loans to get claimable amounts
        ClaimInfo memory claimInfo = getClaimsFromList(
            _loanIdxs,
            _loanIdxs.length,
            applicableShares
        );
            
        (uint128 lastLiquidity, uint32 timeSinceLastReward) = _updateReward(_onBehalfOf, lastTrackedLiquidity[_onBehalfOf] - claimInfo.loanAmount);

        // update LP's from loan index to prevent double claiming and check share pointer
        checkSharePtrIncrement(
            lpInfo,
            _loanIdxs[_loanIdxs.length - 1],
            lpInfo.currSharePtr,
            sharesUnchangedUntilLoanIdx
        );

        if (claimInfo.repayments > 0 && _isReinvested) {
            // Note that 0 time has elapsed since the previous update, so no funds should be awarded
            _updateReward(_onBehalfOf, lastTrackedLiquidity[_onBehalfOf] + claimInfo.repayments);
        }

        _sendReward(_onBehalfOf, lastLiquidity, timeSinceLastReward);

        claimTransferAndReinvestment(
            _onBehalfOf,
            claimInfo.repayments,
            claimInfo.collateral,
            _isReinvested
        );

        // spawn event
        emit Claim(_onBehalfOf, _loanIdxs, claimInfo.repayments, claimInfo.collateral);
    }

    /**
     * @notice Sets the approvals for a given address
     *
     * @dev The approvals are packed into a single uint256, with the
     * least significant 5 bits representing the approvals for the
     * following ApprovalTypes (0 = least significant bit):
     * 0: REPAY
     * 1: ADD_LIQUIDITY
     * 2: REMOVE_LIQUIDITY
     * 3: CLAIM
     * 4: FORCE_REWARD_UPDATE
     * For example, 10100 would set the approvals for FORCE_REWARD_UPDATE and REMOVE_LIQUIDITY.
     * 
     * @param _approvee Address to set approvals for
     * @param _packedApprovals Packed approvals
     */
    function setApprovals(
        address _approvee,
        uint256 _packedApprovals
    ) external override {
        if (msg.sender == _approvee || _approvee == address(0))
            revert("Invalid approval address.");
        _packedApprovals &= 0x1f; // 0x1f is equivalent to 11111 in binary
        for (uint256 index = 0; index < 5; ) {
            bool approvalFlag = ((_packedApprovals >> index) & uint256(1)) == 1;
            if (
                isApproved[msg.sender][_approvee][
                    IBasePool.ApprovalTypes(index)
                ] != approvalFlag
            ) {
                isApproved[msg.sender][_approvee][
                    IBasePool.ApprovalTypes(index)
                ] = approvalFlag;
                _packedApprovals |= uint256(1) << 5;
            }
            unchecked {
                index++;
            }
        }
        if (((_packedApprovals >> 5) & uint256(1)) == 1) {
            emit ApprovalUpdate(msg.sender, _approvee, _packedApprovals & 0x1f);
        }
    }

    /**
     * @notice Returns the LP info for a given address
     *
     * @param _lpAddr Address to get LP info for
     *
     * @return fromLoanIdx Internal tracker for the earliest loan index
     * @return earliestRemove Earliest time the LP can remove liquidity
     * @return currSharePtr Current share pointer
     * @return sharesOverTime Array of shares over time
     * @return loanIdxsWhereSharesChanged Array of loan indices where shares changed
     */
    function getLpInfo(
        address _lpAddr
    )
        external
        view
        override
        returns (
            uint32 fromLoanIdx,
            uint32 earliestRemove,
            uint32 currSharePtr,
            uint256[] memory sharesOverTime,
            uint256[] memory loanIdxsWhereSharesChanged
        )
    {
        LpInfo memory lpInfo = addrToLpInfo[_lpAddr];
        fromLoanIdx = lpInfo.fromLoanIdx;
        earliestRemove = lpInfo.earliestRemove;
        currSharePtr = lpInfo.currSharePtr;
        sharesOverTime = lpInfo.sharesOverTime;
        loanIdxsWhereSharesChanged = lpInfo.loanIdxsWhereSharesChanged;
    }

    /**
     * @notice Returns the parameters used in the interest rate calculation
     *
     * @dev Refer to the whitepaper for an in-depth explanation
     * of the interest rate calculation
     *
     * @return _liquidityBnd1 First liquidity bound, denominated in loanCcy decimals
     * @return _liquidityBnd2 Second liquidity bound, denominated in loanCcy decimals
     * @return _r1 First interest rate, denominated in BASE
     * @return _r2 Second interest rate, denominated in BASE
     */
    function getRateParams()
        external
        view
        override
        returns (
            uint256 _liquidityBnd1,
            uint256 _liquidityBnd2,
            uint256 _r1,
            uint256 _r2
        )
    {
        _liquidityBnd1 = liquidityBnd1;
        _liquidityBnd2 = liquidityBnd2;
        _r1 = r1;
        _r2 = r2;
    }

    /**
     * @notice Returns the pool info
     * 
     * @return _loanCcyToken Loan currency token
     * @return _collCcyToken Collateral currency token
     * @return _maxLoanPerColl Maximum loan per collateral
     * @return _minLoan Minimum loan
     * @return _loanTenor Loan tenor (in seconds)
     * @return _totalLiquidity Total liquidity
     * @return _totalLpShares Total LP shares
     * @return _rewardCoefficient : Reward coefficient
     * @return _loanIdx Loan index
     */
    function getPoolInfo()
        external
        view
        override
        returns (
            IERC20 _loanCcyToken,
            IERC20 _collCcyToken,
            uint256 _maxLoanPerColl,
            uint256 _minLoan,
            uint256 _loanTenor,
            uint256 _totalLiquidity,
            uint256 _totalLpShares,
            uint96 _rewardCoefficient,
            uint256 _loanIdx
        )
    {
        _loanCcyToken = loanCcyToken;
        _collCcyToken = collCcyToken;
        _maxLoanPerColl = maxLoanPerColl;
        _minLoan = minLoan;
        _loanTenor = loanTenor;
        _totalLiquidity = totalLiquidity;
        _totalLpShares = totalLpShares;
        _rewardCoefficient = rewardCoefficient;
        _loanIdx = loanIdx;
    }

    /**
     * @notice Returns the terms for a hypothetical loan
     *
     * @dev Refer to the whitepaper for an in-depth explanation
     * of the interest rate calculation
     *
     * @param _inAmountAfterFees Amount of deposited collCcyToken, after transfer fees
     *
     * @return loanAmount Amount of loanCcyToken to borrow
     * @return repaymentAmount Amount of loanCcyToken to repay
     * @return pledgeAmount Amount of collCcyToken to pledge
     * @return _creatorFee Creator fee
     * @return _totalLiquidity Total liquidity
     */
    function loanTerms(
        uint128 _inAmountAfterFees
    )
        public
        view
        override
        returns (
            uint128 loanAmount,
            uint128 repaymentAmount,
            uint128 pledgeAmount,
            uint256 _creatorFee,
            uint256 _totalLiquidity
        )
    {
        // compute terms (as uint256)
        _creatorFee = (_inAmountAfterFees * creatorFee) / BASE;
        uint256 pledge = _inAmountAfterFees - _creatorFee;
        _totalLiquidity = totalLiquidity;
        if (_totalLiquidity <= minLiquidity) revert("Insufficient liquidity.");
        uint256 loan = (pledge *
            maxLoanPerColl *
            (_totalLiquidity - minLiquidity)) /
            (pledge *
                maxLoanPerColl +
                (_totalLiquidity - minLiquidity) *
                10 ** collTokenDecimals);
        if (loan < minLoan) revert("Loan too small.");
        uint256 postLiquidity = _totalLiquidity - loan;
        assert(postLiquidity >= minLiquidity);
        // we use the average rate to calculate the repayment amount
        uint256 avgRate = (getRate(_totalLiquidity - minLiquidity) + getRate(postLiquidity - minLiquidity)) /
            2;
        // if pre- and post-borrow liquidity are within target liquidity range
        // then the repayment amount exactly matches the amount of integrating the
        // loan size over the infinitesimal rate; else the repayment amount is
        // larger than the amount of integrating loan size over rate;
        uint256 repayment = (loan * (BASE + avgRate)) / BASE;
        // return terms (as uint128)
        assert(uint128(loan) == loan);
        loanAmount = uint128(loan);
        assert(uint128(repayment) == repayment);
        repaymentAmount = uint128(repayment);
        assert(uint128(pledge) == pledge);
        pledgeAmount = uint128(pledge);
        if (repaymentAmount <= loanAmount) revert("Erroneous loan terms.");
    }

    /**
     * @notice Function which updates from index and checks if share pointer should be incremented
     *
     * @dev This function will update new from index for LP to last claimed id + 1. If the current
     * share pointer is not at the end of the LP's shares over time array, and if the new from index
     * is equivalent to the index where shares were then added/removed by LP, then increment share pointer
     *
     * @param _lpInfo Storage struct of LpInfo passed into function
     * @param _lastIdxFromUserInput Last claimable index passed by user into claims
     * @param _currSharePtr Current pointer for shares over time array for LP
     * @param _sharesUnchangedUntilLoanIdx Loan index where the number of shares owned by LP changed.
     */
    function checkSharePtrIncrement(
        LpInfo storage _lpInfo,
        uint256 _lastIdxFromUserInput,
        uint256 _currSharePtr,
        uint256 _sharesUnchangedUntilLoanIdx
    ) internal {
        // update LPs from loan index
        _lpInfo.fromLoanIdx = uint32(_lastIdxFromUserInput) + 1;
        // if current share pointer is not already at end and
        // the last loan claimed was exactly one below the currentToLoanIdx
        // then increment the current share pointer
        if (
            _currSharePtr < _lpInfo.sharesOverTime.length - 1 &&
            _lastIdxFromUserInput + 1 == _sharesUnchangedUntilLoanIdx
        ) {
            unchecked {
                _lpInfo.currSharePtr++;
            }
        }
    }

    /**
     * @notice Function which performs check and possibly updates lpInfo when claiming
     *
     * @dev This function will update first check if the current share pointer for the LP
     * is pointing to a zero value. In that case, pointer will be incremented (since pointless to claim for
     * zero shares) and fromLoanIdx is then updated accordingly from LP's loanIdxWhereSharesChanged array.
     * Other checks are then performed to make sure that LP is entitled to claim from indices sent in
     *
     * @param _startIndex Start index sent in by user when claiming
     * @param _endIndex Last claimable index passed by user into claims
     * @param _lpInfo Current LpInfo struct passed in as storage
     *
     * @return _sharesUnchangedUntilLoanIdx Index up to which the LP did not change shares
     * @return _applicableShares Number of shares to use in the claiming calculation
     */
    function claimsChecksAndSetters(
        uint256 _startIndex,
        uint256 _endIndex,
        LpInfo storage _lpInfo
    )
        internal
        returns (
            uint256 _sharesUnchangedUntilLoanIdx,
            uint256 _applicableShares
        )
    {
        /*
         * check if reasonable to automatically increment share pointer for intermediate period with zero shares
         * and push fromLoanIdx forward
         * Note: Since there is an offset of length 1 for the sharesOverTime and loanIdxWhereSharesChanged
         * this is why the fromLoanIdx needs to be updated before the current share pointer increments
         **/
        uint256 currSharePtr = _lpInfo.currSharePtr;
        if (_lpInfo.sharesOverTime[currSharePtr] == 0) {
            // if share ptr at end of shares over time array, then LP still has 0 shares and should revert right away
            if (currSharePtr == _lpInfo.sharesOverTime.length - 1)
                revert("Zero-share claim.");
            _lpInfo.fromLoanIdx = uint32(
                _lpInfo.loanIdxsWhereSharesChanged[currSharePtr]
            );
            unchecked {
                currSharePtr = ++_lpInfo.currSharePtr;
            }
        }

        /*
         * first loan index (which is what _fromLoanIdx will become)
         * cannot be less than lpInfo.fromLoanIdx (double-claiming or not entitled since
         * wasn't invested during that time), unless special case of first loan globally
         * and LpInfo.fromLoanIdx is 1
         * Note: This still works for claim, since in that function startIndex !=0 is already
         * checked, so second part is always true in claim function
         **/
        if (
            _startIndex < _lpInfo.fromLoanIdx &&
            !(_startIndex == 0 && _lpInfo.fromLoanIdx == 1)
        ) revert("Unentitled from loan indices.");

        // infer applicable upper loan idx for which number of shares didn't change
        _sharesUnchangedUntilLoanIdx = currSharePtr ==
            _lpInfo.sharesOverTime.length - 1
            ? loanIdx
            : _lpInfo.loanIdxsWhereSharesChanged[currSharePtr];

        // check passed last loan idx is consistent with constant share interval
        if (_endIndex >= _sharesUnchangedUntilLoanIdx)
            revert("Loan indexes with changing shares.");

        // get applicable number of shares for pro-rata calculations (given current share pointer position)
        _applicableShares = _lpInfo.sharesOverTime[currSharePtr];
    }

    /**
     * @notice Function which transfers collateral and repayments of claims and reinvests
     *
     * @dev This function will reinvest the loan currency only (and only of course if _isReinvested is true)
     *
     * @param _onBehalfOf LP address which is owner or has approved sender to claim on their behalf (and possibly reinvest)
     * @param _repayments Total repayments (loan currency) after all claims processed
     * @param _collateral Total collateral (collateral currency) after all claims processed
     * @param _isReinvested Flag for if LP wants claimed loanCcy to be re-invested
     */
    function claimTransferAndReinvestment(
        address _onBehalfOf,
        uint256 _repayments,
        uint256 _collateral,
        bool _isReinvested
    ) internal {
        if (_repayments > 0) {
            if (_isReinvested) {
                // allows reinvestment and transfer of any dust from claim functions
                (
                    uint256 dust,
                    uint256 newLpShares,
                    uint32 earliestRemove
                ) = _addLiquidity(_onBehalfOf, _repayments);
                if (dust > 0) {
                    _depositRevenue(loanCcyToken, dust);
                }
                // spawn event
                emit Reinvest(
                    _onBehalfOf,
                    _repayments,
                    newLpShares,
                    earliestRemove,
                    loanIdx
                );
            } else {
                loanCcyToken.safeTransfer(msg.sender, _repayments);
            }
        }
        // transfer collateral
        if (_collateral > 0) {
            collCcyToken.safeTransfer(msg.sender, _collateral);
        }
    }

    /**
     * @notice Helper function when adding liquidity
     *
     * @dev This function is called by addLiquidity, but also
     * by claimants who would like to reinvest their loanCcy
     * portion of the claim
     *
     * @param _onBehalfOf Recipient of the LP shares
     * @param _inAmountAfterFees Net amount of what was sent by LP minus fees
     *
     * @return dust If no LP shares, dust is any remaining excess liquidity (i.e. minLiquidity and rounding)
     * @return newLpShares Amount of new LP shares to be credited to LP.
     * @return earliestRemove Earliest timestamp from which LP is allowed to remove liquidity
     */
    function _addLiquidity(
        address _onBehalfOf,
        uint256 _inAmountAfterFees
    )
        internal
        returns (uint256 dust, uint256 newLpShares, uint32 earliestRemove)
    {
        uint256 _totalLiquidity = totalLiquidity;
        if (_inAmountAfterFees < minLiquidity / 1000) revert("Invalid add amount.");
        // retrieve lpInfo of sender
        LpInfo storage lpInfo = addrToLpInfo[_onBehalfOf];

        // calculate new lp shares
        if (totalLpShares == 0) {
            dust = _totalLiquidity;
            _totalLiquidity = 0;
            newLpShares = (_inAmountAfterFees * 1000) / minLiquidity;
        } else {
            assert(_totalLiquidity > 0);
            newLpShares =
                (_inAmountAfterFees * totalLpShares) /
                _totalLiquidity;
        }
        if (newLpShares == 0 || uint128(newLpShares) != newLpShares)
            revert("Invalid add amount.");
        totalLpShares += uint128(newLpShares);

        require(totalLpShares < minLoan * BASE, "Cannot add liquidity.");

        totalLiquidity = _totalLiquidity + _inAmountAfterFees;
        // update LP info
        bool isFirstAddLiquidity = lpInfo.fromLoanIdx == 0;
        if (isFirstAddLiquidity) {
            lpInfo.fromLoanIdx = uint32(loanIdx);
            lpInfo.sharesOverTime.push(newLpShares);
        } else {
            // update both LP arrays and check for auto increment
            updateLpArrays(lpInfo, newLpShares, true);
        }
        earliestRemove = uint32(block.timestamp + MIN_LPING_PERIOD);
        lpInfo.earliestRemove = earliestRemove;
        // keep track of add timestamp per tx origin to check for atomic add and borrows/rollOvers
        lastAddOfTxOrigin[tx.origin] = block.timestamp;
    }

    /**
     * @notice Function which updates array (and possibly array pointer) info
     *
     * @dev There are many different cases depending on if shares over time is length 1,
     * if the LP fromLoanId = loanIdx, if last value of loanIdxsWhereSharesChanged = loanIdx,
     * and possibly on the value of the penultimate shares over time array = newShares...
     * further discussion of all cases is provided in the whitepaper
     *
     * @param _lpInfo Struct of the info for the current LP
     * @param _newLpShares Amount of new LP shares to add/remove from current LP position
     * @param _add Flag that allows for addition of shares for addLiquidity and subtraction for remove
     */
    function updateLpArrays(
        LpInfo storage _lpInfo,
        uint256 _newLpShares,
        bool _add
    ) internal {
        uint256 _loanIdx = loanIdx;
        uint256 _originalSharesLen = _lpInfo.sharesOverTime.length;
        uint256 _originalLoanIdxsLen = _originalSharesLen - 1;
        uint256 currShares = _lpInfo.sharesOverTime[_originalSharesLen - 1];
        uint256 newShares = _add
            ? currShares + _newLpShares
            : currShares - _newLpShares;
        bool loanCheck = (_originalLoanIdxsLen > 0 &&
            _lpInfo.loanIdxsWhereSharesChanged[_originalLoanIdxsLen - 1] ==
            _loanIdx);
        // if LP has claimed all possible loans that were taken out (fromLoanIdx = loanIdx)
        if (_lpInfo.fromLoanIdx == _loanIdx) {
            /**
                if shares length has one value, OR
                if loanIdxsWhereSharesChanged array is non empty
                and the last value of the array is equal to current loanId
                then we go ahead and overwrite the lastShares array.
                We do not have to worry about popping array in second case
                because since fromLoanIdx == loanIdx, we know currSharePtr is
                already at end of the array, and therefore can never get stuck
            */
            if (_originalSharesLen == 1 || loanCheck) {
                _lpInfo.sharesOverTime[_originalSharesLen - 1] = newShares;
            }
            /**
            if loanIdxsWhereSharesChanged array is non empty
            and the last value of the array is NOT equal to current loanId
            then we go ahead and push a new value onto both arrays and increment currSharePtr
            we can safely increment share pointer because we know if fromLoanIdx is == loanIdx
            then currSharePtr has to already be length of original shares over time array - 1 and
            we want to keep it at end of the array 
            */
            else {
                pushLpArrays(_lpInfo, newShares, _loanIdx);
                unchecked {
                    _lpInfo.currSharePtr++;
                }
            }
        }
        /**
            fromLoanIdx is NOT equal to loanIdx in this case, but
            loanIdxsWhereSharesChanged array is non empty
            and the last value of the array is equal to current loanId.        
        */
        else if (loanCheck) {
            /**
                The value in the shares array before the last array
                In this case we are going to pop off the last values.
                Since we know that if currSharePtr was at end of array and loan id is still equal to last value
                on the loanIdxsWhereSharesUnchanged array, this would have meant that fromLoanIdx == loanIdx
                and hence, no need to check if currSharePtr needs to decrement
            */
            if (_lpInfo.sharesOverTime[_originalSharesLen - 2] == newShares) {
                _lpInfo.sharesOverTime.pop();
                _lpInfo.loanIdxsWhereSharesChanged.pop();
            }
            // if next to last shares over time value is not same as newShares,
            // then just overwrite last share value
            else {
                _lpInfo.sharesOverTime[_originalSharesLen - 1] = newShares;
            }
        } else {
            // if the previous conditions are not met then push newShares onto shares over time array
            // and push global loan index onto loanIdxsWhereSharesChanged
            pushLpArrays(_lpInfo, newShares, _loanIdx);
        }
    }

    /**
     * @notice Helper function that pushes onto both LP Info arrays
     *
     * @dev This function is called by updateLpArrays function in two cases when both
     * LP Info arrays, sharesOverTime and loanIdxsWhereSharesChanged, are pushed onto
     *
     * @param _lpInfo Struct of the info for the current LP
     * @param _newShares New amount of LP shares pushed onto sharesOverTime array
     * @param _loanIdx Current global loanIdx pushed onto loanIdxsWhereSharesChanged array
     */
    function pushLpArrays(
        LpInfo storage _lpInfo,
        uint256 _newShares,
        uint256 _loanIdx
    ) internal {
        _lpInfo.sharesOverTime.push(_newShares);
        _lpInfo.loanIdxsWhereSharesChanged.push(_loanIdx);
    }

    /**
     * @notice Helper function when user is borrowing
     *
     * @dev This function is called by borrow
     *
     * @param _inAmountAfterFees Net amount of what was sent by borrower minus fees
     * @param _minLoanLimit Minimum loan currency amount acceptable to borrower
     * @param _maxRepayLimit Maximum allowable loan currency amount borrower is willing to repay
     * @param _timestamp Time that is used to set loan expiry
     *
     * @return loanAmount Amount of loan Ccy given to the borrower
     * @return repaymentAmount Amount of loan Ccy borrower needs to repay to claim collateral
     * @return pledgeAmount Amount of collCcy reclaimable upon repayment
     * @return expiry Timestamp after which loan expires
     * @return _creatorFee Per transaction fee which levied for using the protocol
     * @return _totalLiquidity Updated total liquidity (pre-borrow)
     */
    function _borrow(
        uint128 _inAmountAfterFees,
        uint128 _minLoanLimit,
        uint128 _maxRepayLimit,
        uint256 _timestamp
    )
        internal
        view
        returns (
            uint128 loanAmount,
            uint128 repaymentAmount,
            uint128 pledgeAmount,
            uint32 expiry,
            uint256 _creatorFee,
            uint256 _totalLiquidity
        )
    {
        // get and verify loan terms
        (
            loanAmount,
            repaymentAmount,
            pledgeAmount,
            _creatorFee,
            _totalLiquidity
        ) = loanTerms(_inAmountAfterFees);
        assert(_inAmountAfterFees != 0); // if 0 must have failed in loanTerms(...)
        if (loanAmount < _minLoanLimit) revert("Loan below limit.");
        if (repaymentAmount > _maxRepayLimit) revert("Repayment above limit.");
        expiry = uint32(_timestamp + loanTenor);
    }

    /**
     * @notice Helper function called whenever a function needs to check a deadline
     *
     * @dev This function is called by addLiquidity, borrow, and if reinvestment on claiming,
     * it will be called by claimReinvestmentCheck
     *
     * @param _deadline Last timestamp after which function will revert
     *
     * @return timestamp Current timestamp passed back to function
     */
    function checkTimestamp(
        uint256 _deadline
    ) internal view returns (uint256 timestamp) {
        timestamp = block.timestamp;
        if (timestamp > _deadline) revert("Past deadline.");
    }

    /**
     * @notice Helper function called whenever reinvestment is possible
     *
     * @dev This function is called by claim and claimFromAggregated if reinvestment is desired
     *
     * @param _deadline Last timestamp after which function will revert
     * @param _onBehalfOf Recipient of the reinvested LP shares
     */
    function claimReinvestmentCheck(
        uint256 _deadline,
        address _onBehalfOf
    ) internal view {
        checkTimestamp(_deadline);
        checkSenderApproval(_onBehalfOf, IBasePool.ApprovalTypes.ADD_LIQUIDITY);
    }

    /**
     * @notice Helper function checks if function caller is a valid sender
     *
     * @dev This function is called by addLiquidity, removeLiquidity, repay,
     * claim, claimFromAggregated, claimReinvestmentCheck (ADD_LIQUIDITY)
     *
     * @param _ownerOrBeneficiary Address which will be owner or beneficiary of transaction if approved
     * @param _approvalType Type of approval requested { REPAY, ADD_LIQUIDITY, REMOVE_LIQUIDITY, CLAIM }
     */
    function checkSenderApproval(
        address _ownerOrBeneficiary,
        IBasePool.ApprovalTypes _approvalType
    ) internal view {
        if (
            !(_ownerOrBeneficiary == msg.sender ||
                isApproved[_ownerOrBeneficiary][msg.sender][_approvalType])
        ) revert("Sender not approved.");
    }

    /**
     * @notice Helper function used by claim function
     *
     * @dev This function is called by claim to check the passed array
     * is valid and return the repayment and collateral amounts
     *
     * @param _loanIdxs Array of loan Idxs over which the LP would like to claim
     * @param arrayLen Length of the loanIdxs array
     * @param _shares LP shares owned by the LP during the period of the claims
     *
     * @return claimInfo struct containing repayments, collateral and loanAmount
     */
    function getClaimsFromList(
        uint256[] calldata _loanIdxs,
        uint256 arrayLen,
        uint256 _shares
    ) internal view returns (ClaimInfo memory claimInfo) {
        uint256 repayments;
        uint256 collateral;
        uint256 loanAmount;

        // aggregate claims from list
        for (uint256 i = 0; i < arrayLen; ) {
            LoanInfo memory loanInfo = loanIdxToLoanInfo[_loanIdxs[i]];
            if (i > 0) {
                if (_loanIdxs[i] <= _loanIdxs[i - 1])
                    revert("Non-ascending loan indices.");
            }
            if (loanInfo.repaid) {
                repayments +=
                    (loanInfo.repayment * BASE) /
                    loanInfo.totalLpShares;
            } else if (loanInfo.expiry < block.timestamp) {
                collateral +=
                    (loanInfo.collateral * BASE) /
                    loanInfo.totalLpShares;
            } else {
                revert("Cannot claim with unsettled loan.");
            }

            loanAmount += (loanInfo.loanAmount * BASE) / loanInfo.totalLpShares;

            unchecked {
                i++;
            }
        }
        // return claims
        claimInfo.repayments = (repayments * _shares) / BASE;
        claimInfo.collateral = (collateral * _shares) / BASE;
        claimInfo.loanAmount = (loanAmount * _shares) / BASE;
    }

    /**
     * @notice Returns the pool's rate given _liquidity to calculate a loan's
     * repayment amount
     *
     * @dev The rate is defined as a piecewise function with 3 ranges:
     * (1) low liquidity range: rate is defined as a reciprocal function
     * (2) target liquidity range: rate is linear
     * (3) high liquidity range: rate is constant
     * 
     * @param _liquidity Liquidity level for which the rate shall be calculated
     * 
     * @return rate Applicable rate
     */
    function getRate(uint256 _liquidity) internal view returns (uint256 rate) {
        if (_liquidity < liquidityBnd1) {
            rate = (r1 * liquidityBnd1) / _liquidity;
        } else if (_liquidity <= liquidityBnd2) {
            rate =
                r2 +
                ((r1 - r2) * (liquidityBnd2 - _liquidity)) /
                (liquidityBnd2 - liquidityBnd1);
        } else {
            rate = r2;
        }
    }

    /**
     * @notice Internal function to update the last reward timestamp
     * and last tracked liquidity
     *
     * @param _account Account for which the reward is being updated
     * @param _newLiquidity New liquidity for the account
     *
     * @return oldLiquidity Liquidity before the update
     * @return timeSinceLastReward Time since the last reward
     */
    function _updateReward(address _account, uint256 _newLiquidity) internal returns (uint128 oldLiquidity, uint32 timeSinceLastReward) {
        uint32 previousRewardTimestamp = lastRewardTimestamp[_account];
        assert(previousRewardTimestamp <= block.timestamp);
        assert(uint128(_newLiquidity) == _newLiquidity);

        oldLiquidity = lastTrackedLiquidity[_account];

        lastRewardTimestamp[_account] = uint32(block.timestamp);
        lastTrackedLiquidity[_account] = uint128(_newLiquidity);

        if(previousRewardTimestamp == 0) {
            return (0, 0);
        }

        uint256 _timeSinceLastReward = block.timestamp - previousRewardTimestamp;

        assert(uint128(oldLiquidity) == oldLiquidity);
        assert(uint32(_timeSinceLastReward) == _timeSinceLastReward);
        timeSinceLastReward = uint32(_timeSinceLastReward);

        assert(uint32(block.timestamp) == block.timestamp);
    }

    /**
     * @notice Helper function to send the reward to the pool controller
     *
     * @param _account Acount for which the reward is being sent
     * @param _liquidity Liquidity of the account
     * @param _timeSinceLastReward Time since the last reward was sent
     */
    function _sendReward(address _account, uint128 _liquidity, uint32 _timeSinceLastReward) internal {
        if (_liquidity > 0 && _timeSinceLastReward > 0) {
            try poolController.requestTokenDistribution(_account, _liquidity, _timeSinceLastReward, rewardCoefficient) {} catch {
                // Do nothing
            }
        }
    }

    /**
     * @notice Helper function to update the reward and send it to the pool controller
     *
     * @param _account Account for which the reward is being sent
     * @param _newLiquidity New liquidity of the account
     */
    function _updateRewardAndSend(address _account, uint256 _newLiquidity) internal {
        (uint128 oldLiquidity, uint32 timeSinceLastReward) = _updateReward(_account, _newLiquidity);
        _sendReward(_account, oldLiquidity, timeSinceLastReward);
    }

    /**
     * @notice Forces a reward update for a given account
     *
     * @param _onBehalfOf Account for which the reward is being updated
     */
    function forceRewardUpdate(address _onBehalfOf) external {
        checkSenderApproval(_onBehalfOf, IBasePool.ApprovalTypes.FORCE_REWARD_UPDATE);
        _updateRewardAndSend(_onBehalfOf, lastTrackedLiquidity[_onBehalfOf]);
    }

    function _depositRevenue(IERC20 _token, uint256 _amount) internal {
        _token.safeIncreaseAllowance(address(poolController), _amount);
        try poolController.depositRevenue(_token, _amount) {} catch {
            // Do nothing
        }
    }

    /**
     * @inheritdoc IPausable
     */
    function pause () external override {
        require(msg.sender == address(poolController), "Not the controller.");
        _pause();
    }

    /**
     * @inheritdoc IPausable
     */
    function unpause () external override {
        require(msg.sender == address(poolController), "Not the controller.");
        _unpause();
    }


    // The following is an instruction for the custom preprocessor implemented in unit tests
    // It adds two methods (getTime() and setTime(uint256)) which allow to manipulate the
    // block.timestamp value in tests

    // TMP-TIMESTAMP-METHODS
}
