// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IController.sol";

contract Controller is IController {
    using SafeERC20 for IERC20;

    // Threshold base value for voting
    uint256 constant THRESHOLD_BASE = 10000;

    // Coefficient used in complex timestamps
    uint256 constant COMPLEX_TIMESTAMP_COEFFICIENT = 1000000;

    // Reward base value
    uint256 constant REWARD_BASE = 10 ** 18;

    // Token to be used for voting
    IERC20 public voteToken;

    // Thresholds (denominated in THRESHOLD_BASE)
    uint256 public pauseThreshold;
    uint256 public unpauseThreshold;
    uint256 public whitelistThreshold;
    uint256 public dewhitelistThreshold;

    // How often (in seconds) to perform a token snapshot
    uint256 public snapshotTokenEvery;

    // How long (in seconds) a user must wait before withdrawing their vote token
    uint256 public lockPeriod;

    // Total supply of the vote tokens (not including locked reward tokens)
    uint256 public voteTokenTotalSupply;

    // Vote token balance of each user
    mapping(address => uint256) public voteTokenBalance;

    // Timestamp of the last deposit by a user
    mapping(address => uint256) public lastDepositTimestamp;

    // Number of active votings for each user
    mapping(address => uint256) public numVotings;

    // Number of proposals
    uint256 public numProposals;

    // Proposals
    mapping(uint256 => Proposal) proposals;

    // Token snapshots of each token
    mapping(IERC20 => mapping(uint256 => TokenSnapshot)) tokenSnapshots;
    
    // Number of token snapshots for a given token
    mapping(IERC20 => uint256) public numTokenSnapshots;

    // Current revenue of each token
    mapping(IERC20 => uint256) public currentRevenue;

    // Account snapshots
    mapping(address => mapping(uint256 => AccountSnapshot)) accountSnapshots;
    
    // Number of account snapshots
    mapping(address => uint256) public numAccountSnapshots;

    // timestamp => sub-timestamp counter mapping
    mapping(uint256 => uint256) public subTimestampCounter;

    // Total supply of the vote token for rewards
    uint256 public rewardSupply;

    // Reward balance of each user
    mapping(address => uint256) public rewardBalance;

    // Whether a pool is whitelisted
    mapping(address => bool) public poolWhitelisted;

    // Holder of the veto power for whitelisting proposals
    address public vetoHolder;

    /**
     * @notice Instantiates the Controller contract
     *
     * @param _voteToken Token id of the vote token
     * @param _pauseThreshold Threshold (out of THRESHOLD_BASE) for pausing a pool
     * @param _unpauseThreshold Threshold (out of THRESHOLD_BASE) for unpausing a pool
     * @param _whitelistThreshold Threshold (out of THRESHOLD_BASE) for whitelisting a pool
     * @param _dewhitelistThreshold Threshold (out of THRESHOLD_BASE) for de-whitelisting a pool
     * @param _snapshotEvery Number of seconds after which a new token snapshot is taken
     * @param _lockPeriod Number of seconds after which a user can withdraw their vote token
     * @param _vetoHolder Address of the veto holder
     */
    constructor (
        IERC20 _voteToken,
        uint256 _pauseThreshold,
        uint256 _unpauseThreshold,
        uint256 _whitelistThreshold,
        uint256 _dewhitelistThreshold,
        uint256 _snapshotEvery,
        uint256 _lockPeriod,
        address _vetoHolder
    ) {
        require(_pauseThreshold > 0 && _pauseThreshold <= THRESHOLD_BASE, "_pauseThreshold must be in (0, THRESHOLD_BASE].");
        require(_unpauseThreshold > 0 && _unpauseThreshold <= THRESHOLD_BASE, "_unpauseThreshold must be in (0, THRESHOLD_BASE].");
        require(_whitelistThreshold > 0 && _whitelistThreshold <= THRESHOLD_BASE, "_whitelistThreshold must be in (0, THRESHOLD_BASE].");
        require(_dewhitelistThreshold > 0 && _dewhitelistThreshold <= THRESHOLD_BASE, "_dewhitelistThreshold must be in (0, THRESHOLD_BASE].");
        require(_snapshotEvery > 0, "_snapshotEvery must be greater than 0.");

        voteToken = _voteToken;

        pauseThreshold = _pauseThreshold;
        unpauseThreshold = _unpauseThreshold;
        whitelistThreshold = _whitelistThreshold;
        dewhitelistThreshold = _dewhitelistThreshold;

        snapshotTokenEvery = _snapshotEvery;
        lockPeriod = _lockPeriod;
        vetoHolder = _vetoHolder;
    }

    function supportsInterface(bytes4 interfaceId) override external view returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IController).interfaceId;
    }

    /**
     * @inheritdoc IController
     */
    function depositRevenue(IERC20 _token, uint256 _amount) override external payable {
        currentRevenue[_token] += _amount;
        _checkTokenSnapshot(_token);

        _token.safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice Creates a proposal
     *
     * @param _target Target contract of the proposal
     * @param _action Action to be executed (see IController.Action enum)
     * @param _deadline Deadline of the proposal
     */
    function createProposal(IPausable _target, Action _action, uint256 _deadline) external {
        require(_deadline >= block.timestamp, "Deadline must not be before timestamp.");
        proposals[numProposals].target = _target;
        proposals[numProposals].action = _action;
        proposals[numProposals].deadline = _deadline;

        emit ProposalCreated(numProposals, msg.sender, _target, _action, _deadline);
        numProposals++;
    }

    /**
     * @notice Returns the information of a proposal
     *
     * @param _proposalIdx Index of the proposal
     *
     * @return _target Target contract of the proposal
     * @return _action Action to be executed (see IController.Action enum)
     * @return _totalVotes Total votes of the proposal
     * @return _vetoApprover Address of the veto approver
     * @return _executed Whether the proposal has been executed
     * @return _deadline Deadline of the proposal
     */
    function getProposal (uint256 _proposalIdx) external view returns (
        IPausable _target, Action _action, uint256 _totalVotes, address _vetoApprover, bool _executed, uint256 _deadline) {
        _target = proposals[_proposalIdx].target;
        _action = proposals[_proposalIdx].action;
        _totalVotes = proposals[_proposalIdx].totalVotes;
        _vetoApprover = proposals[_proposalIdx].vetoApprover;
        _executed = proposals[_proposalIdx].executed;
        _deadline = proposals[_proposalIdx].deadline;
    }

    /**
     * @notice Returns the votes of a proposal for a voter
     *
     * @dev A value of zero means that the voter has not voted
     * @dev Note that the votes cast by a user might be different from
     * the current voting power of the user
     *
     * @param _proposalIdx Index of the proposal
     * @param _voter Address of the voter
     *
     * @return Number of votes cast by the voter
     */
    function getProposalVotes (uint256 _proposalIdx, address _voter) external view returns (uint256) {
        return proposals[_proposalIdx].votesByAddress[_voter];
    }

    /**
     * @notice Votes for a proposal
     *
     * @dev The voting power of the user is the number of tokens. If the number
     * of tokens changes, it is possible to update the number of votes by removing
     * the vote and adding it again. Note that it is not possible to decrease the
     * vote token balance while some votes are cast
     *
     * @param _proposalIdx Index of the proposal
     */
    function vote(uint256 _proposalIdx) external {
        require(_proposalIdx < numProposals, "Invalid proposal idx.");

        uint256 votingPower = voteTokenBalance[msg.sender];

        require(votingPower > 0, "No voting power.");
        require(proposals[_proposalIdx].votesByAddress[msg.sender] == 0, "Already voted.");
        require(!proposals[_proposalIdx].executed, "Proposal already executed.");
        require(block.timestamp <= proposals[_proposalIdx].deadline, "Proposal expired.");

        proposals[_proposalIdx].totalVotes += votingPower;
        proposals[_proposalIdx].votesByAddress[msg.sender] = votingPower;
        numVotings[msg.sender]++;

        emit Voted(_proposalIdx, msg.sender, votingPower, proposals[_proposalIdx].totalVotes);

        _checkVote(_proposalIdx);
    }

    /**
     * @notice Cancels a vote
     *
     * @param _proposalIdx Index of the proposal
     */
    function removeVote(uint256 _proposalIdx) external {
        require(_proposalIdx < numProposals, "Invalid proposal idx.");

        uint256 castVotes = proposals[_proposalIdx].votesByAddress[msg.sender];
        require(castVotes > 0, "Did not vote.");
        
        proposals[_proposalIdx].totalVotes -= castVotes;
        proposals[_proposalIdx].votesByAddress[msg.sender] = 0;
        numVotings[msg.sender]--;
        
        emit Cancelled(_proposalIdx, msg.sender, castVotes, proposals[_proposalIdx].totalVotes);
    }

    /**
     * @notice Checks if it is possible to execute a proposal (and, if so,
       executes it)
     *
     * @param _proposalIdx Index of the proposal
     */
    function _checkVote(uint256 _proposalIdx) internal {
        if (voteTokenTotalSupply == 0) {
            // Avoids division-by-zero errors
            return;
        }

        uint256 referenceThreshold;

        if (proposals[_proposalIdx].action == Action.PAUSE) {
            referenceThreshold = pauseThreshold;
        } else if (proposals[_proposalIdx].action == Action.UNPAUSE) {
            referenceThreshold = unpauseThreshold;
        } else if (proposals[_proposalIdx].action == Action.WHITELIST) {
            referenceThreshold = whitelistThreshold;
        } else if (proposals[_proposalIdx].action == Action.DEWHITELIST) {
            referenceThreshold = dewhitelistThreshold;
        } else {
            revert("Unsupported action type.");
        }

        uint256 absoluteThreshold = voteTokenTotalSupply * referenceThreshold / THRESHOLD_BASE;
        if (proposals[_proposalIdx].totalVotes > absoluteThreshold) {
            if(
                proposals[_proposalIdx].action == Action.WHITELIST &&
                proposals[_proposalIdx].vetoApprover != vetoHolder
            ) {
                // Proposal hasn't been approved by the veto holder yet
                return;
            }

            // Proposal passed
            proposals[_proposalIdx].executed = true;

            if (proposals[_proposalIdx].action == Action.PAUSE) {
                proposals[_proposalIdx].target.pause();
            } else if (proposals[_proposalIdx].action == Action.UNPAUSE) {
                proposals[_proposalIdx].target.unpause();
            } else if (proposals[_proposalIdx].action == Action.WHITELIST) {
                poolWhitelisted[address(proposals[_proposalIdx].target)] = true;
            } else if (proposals[_proposalIdx].action == Action.DEWHITELIST) {
                poolWhitelisted[address(proposals[_proposalIdx].target)] = false;
            } else {
                revert("Unsupported action type.");
            }

            emit Executed(_proposalIdx, proposals[_proposalIdx].totalVotes, voteTokenTotalSupply);
        }
    }

    /**
     * @notice Internal method to deposit vote tokens
     *
     * @param _account Address of the account
     * @param _amount Amount of tokens to deposit
     */
    function _depositVoteToken(address _account, uint256 _amount) internal {
        voteTokenBalance[_account] += _amount;
        voteTokenTotalSupply += _amount;

        uint256 subTimestamp = _takeAccountSnapshot(_account);

        lastDepositTimestamp[_account] = block.timestamp;

        emit DepositedVoteToken(_account, _amount, voteTokenBalance[_account], voteTokenTotalSupply, subTimestamp);
    }

    /**
     * @notice Deposits vote tokens
     *
     * @param _amount Amount to deposit
     */
    function depositVoteToken(uint256 _amount) external payable {
        _depositVoteToken(msg.sender, _amount);

        voteToken.safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @notice Withdraws vote tokens
     *
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawVoteToken(uint256 _amount) external {
        require(_amount > 0, "Cannot make a zero-value withdraw.");
        require(numVotings[msg.sender] == 0, "Cannot withdraw when votes are active.");
        require(_amount <= voteTokenBalance[msg.sender], "Not enough tokens.");

        require(
            lastDepositTimestamp[msg.sender] == 0 ||
            block.timestamp >= lastDepositTimestamp[msg.sender] + lockPeriod,
        "Too early to withdraw.");
        
        voteTokenBalance[msg.sender] -= _amount;
        voteTokenTotalSupply -= _amount;

        uint256 subTimestamp = _takeAccountSnapshot(msg.sender);

        voteToken.safeTransfer(msg.sender, _amount);

        emit WithdrawnVoteToken(msg.sender, _amount, voteTokenBalance[msg.sender], voteTokenTotalSupply, subTimestamp);
    }

    /**
     * @notice Forces the contract to take a snapshot of a token balance
     *
     * @dev This can be useful when there have not been any token deposits
     * for a while, and the users want to still claim the revenue
     *
     * @param _token Token to take a snapshot of
     */
    function forceTokenSnapshotCheck(IERC20 _token) external {
        _checkTokenSnapshot(_token);
    }

    /**
     * @notice Checks if it is possible to perform a token snapshot, and if
     * so, performs it
     *
     * @param _token Token to check
     */
    function _checkTokenSnapshot (IERC20 _token) internal {
        uint256 newSnapshotIdx = numTokenSnapshots[_token];
        if (newSnapshotIdx == 0 || // First snapshot
            // Enough time has passed
            block.timestamp >= tokenSnapshots[_token][newSnapshotIdx - 1].timestamp + snapshotTokenEvery
        ) {
            // Take snapshot
            tokenSnapshots[_token][newSnapshotIdx].voteTokenTotalSupply = voteTokenTotalSupply;
            tokenSnapshots[_token][newSnapshotIdx].timestamp = block.timestamp;
            tokenSnapshots[_token][newSnapshotIdx].subTimestamp = subTimestampCounter[block.timestamp];

            // Transfer revenue from current to snapshot
            tokenSnapshots[_token][newSnapshotIdx].collectedRevenue = currentRevenue[_token];
            currentRevenue[_token] = 0;

            numTokenSnapshots[_token]++;

            emit TokenSnapshotPerformed(
                _token,
                newSnapshotIdx,
                tokenSnapshots[_token][newSnapshotIdx].voteTokenTotalSupply,
                tokenSnapshots[_token][newSnapshotIdx].collectedRevenue,
                tokenSnapshots[_token][newSnapshotIdx].subTimestamp
            );
        }

        subTimestampCounter[block.timestamp]++;
    }

    /**
     * @notice Internal method to take a snapshot of an account
     *
     * @param _account Account to take a snapshot of
     *
     * @return _snapshotSubTimestamp Sub-timestamp of the snapshot
     */
    function _takeAccountSnapshot(address _account) internal returns (uint256 _snapshotSubTimestamp) {
        uint256 newAccountSnapshotIdx = numAccountSnapshots[_account];

        accountSnapshots[_account][newAccountSnapshotIdx].voteTokenBalance = voteTokenBalance[_account];
        accountSnapshots[_account][newAccountSnapshotIdx].timestamp = block.timestamp;

        _snapshotSubTimestamp = subTimestampCounter[block.timestamp];
        accountSnapshots[_account][newAccountSnapshotIdx].subTimestamp = _snapshotSubTimestamp;

        numAccountSnapshots[_account]++;

        subTimestampCounter[block.timestamp]++;
    }

    /**
     * @notice Returns the information of an account snapshot
     *
     * @param _account Account to get the snapshot of
     * @param _accountSnapshotIdx Index of the snapshot
     *
     * @return _voteTokenBalance Vote token balance of the account
     * @return _timestamp Timestamp of the snapshot
     * @return _subTimestamp Sub-timestamp of the snapshot
     */
    function getAccountSnapshot(address _account, uint256 _accountSnapshotIdx) external view
        returns (uint256 _voteTokenBalance, uint256 _timestamp, uint256 _subTimestamp)
    {
        require(_accountSnapshotIdx < numAccountSnapshots[_account], "Invalid account snapshot idx.");
        _voteTokenBalance = accountSnapshots[_account][_accountSnapshotIdx].voteTokenBalance;
        _timestamp = accountSnapshots[_account][_accountSnapshotIdx].timestamp;
        _subTimestamp = accountSnapshots[_account][_accountSnapshotIdx].subTimestamp;
    }

    /**
     * @notice Returns the information of a token snapshot
     *
     * @param _token Token to get the snapshot of
     * @param _tokenSnapshotIdx Index of the snapshot
     *
     * @return _voteTokenTotalSupply Total supply of vote tokens
     * @return _collectedRevenue Revenue collected by the snapshot
     * @return _claimedRevenue Revenue claimed by the snapshot
     * @return _timestamp Timestamp of the snapshot
     * @return _subTimestamp Sub-timestamp of the snapshot
     */
    function getTokenSnapshot(IERC20 _token, uint256 _tokenSnapshotIdx) external view
        returns (uint256 _voteTokenTotalSupply, uint256 _collectedRevenue, uint256 _claimedRevenue, uint256 _timestamp, uint256 _subTimestamp)
    {
        require(_tokenSnapshotIdx < numTokenSnapshots[_token], "Invalid token snapshot idx.");

        _voteTokenTotalSupply = tokenSnapshots[_token][_tokenSnapshotIdx].voteTokenTotalSupply;
        _timestamp = tokenSnapshots[_token][_tokenSnapshotIdx].timestamp;
        _collectedRevenue = tokenSnapshots[_token][_tokenSnapshotIdx].collectedRevenue;
        _claimedRevenue = tokenSnapshots[_token][_tokenSnapshotIdx].claimedRevenue;
        _subTimestamp = tokenSnapshots[_token][_tokenSnapshotIdx].subTimestamp;
    }

    /**
     * @notice Returns true if the account has claimed the revenue from a token snapshot
     *
     * @param _token Token to get the snapshot of
     * @param _tokenSnapshotIdx Index of the snapshot
     * @param _account Account to check
     */
    function hasClaimedSnapshot(IERC20 _token, uint256 _tokenSnapshotIdx, address _account) external view returns (bool) {
        require(_tokenSnapshotIdx < numTokenSnapshots[_token], "Invalid token snapshot idx.");

        return tokenSnapshots[_token][_tokenSnapshotIdx].claimed[_account];
    }

    /**
     * @notice Internal method to encode a complex timestamp
     *
     * @dev The complex timestamp is the sum of the sub-timestamp and the timestamp
     * (multiplied by a coefficient). The complex timestamp is used to distinguish
     * between transactions in the same block
     *
     * @param _timestamp Timestamp
     * @param _subTimestamp Sub-timestamp
     *
     * @return _complexTimestamp Complex timestamp
     */
    function _encodeComplexTimestamp(uint256 _timestamp, uint256 _subTimestamp) internal pure returns (uint256) {
        return _timestamp * COMPLEX_TIMESTAMP_COEFFICIENT + _subTimestamp;
    }

    /**
     * @notice Claims the revenue from a token snapshot
     *
     * @dev _accountSnapshotIdx must be the last snapshot taken before the token snapshot
     *
     * @param _token Token to claim the revenue from
     * @param _tokenSnapshotIdx Index of the token snapshot
     * @param _accountSnapshotIdx Index of the account snapshot
     */
    function claimToken(IERC20 _token, uint256 _tokenSnapshotIdx, uint256 _accountSnapshotIdx) public {
        require(_accountSnapshotIdx < numAccountSnapshots[msg.sender], "Invalid account snapshot idx.");
        require(_tokenSnapshotIdx < numTokenSnapshots[_token], "Invalid token snapshot idx.");

        require(accountSnapshots[msg.sender][_accountSnapshotIdx].voteTokenBalance > 0, "No vote tokens at snapshot.");
        require(!tokenSnapshots[_token][_tokenSnapshotIdx].claimed[msg.sender], "Already claimed.");

        uint256 tokenSnapshotComplexTimestamp = _encodeComplexTimestamp(
            tokenSnapshots[_token][_tokenSnapshotIdx].timestamp,
            tokenSnapshots[_token][_tokenSnapshotIdx].subTimestamp
        );

        uint256 currentComplexTimestamp = _encodeComplexTimestamp(
            accountSnapshots[msg.sender][_accountSnapshotIdx].timestamp,
            accountSnapshots[msg.sender][_accountSnapshotIdx].subTimestamp
        );

        uint256 nextComplexTimestamp = _encodeComplexTimestamp(
            accountSnapshots[msg.sender][_accountSnapshotIdx + 1].timestamp,
            accountSnapshots[msg.sender][_accountSnapshotIdx + 1].subTimestamp
        );

        // You need an account snapshot X such that X happens before the token snapshot and X+1 happens after the token snapshot
        require(currentComplexTimestamp < tokenSnapshotComplexTimestamp &&
            (_accountSnapshotIdx == numAccountSnapshots[msg.sender] - 1 || nextComplexTimestamp > tokenSnapshotComplexTimestamp)
        , "Incorrect account snapshot idx.");

        // Valid, claim the tokens

        require(tokenSnapshots[_token][_tokenSnapshotIdx].voteTokenTotalSupply > 0, "No vote tokens during snapshot.");

        uint256 remainingRevenue = tokenSnapshots[_token][_tokenSnapshotIdx].collectedRevenue - tokenSnapshots[_token][_tokenSnapshotIdx].claimedRevenue;
        uint256 transferAmount = tokenSnapshots[_token][_tokenSnapshotIdx].collectedRevenue * accountSnapshots[msg.sender][_accountSnapshotIdx].voteTokenBalance / tokenSnapshots[_token][_tokenSnapshotIdx].voteTokenTotalSupply;
        
        if (transferAmount > remainingRevenue) {
            // Rounding errors can cause underflows, adjust the amount
            transferAmount = remainingRevenue;
        }

        tokenSnapshots[_token][_tokenSnapshotIdx].claimed[msg.sender] = true;
        tokenSnapshots[_token][_tokenSnapshotIdx].claimedRevenue += transferAmount;
        _token.safeTransfer(msg.sender, transferAmount);

        emit TokenClaimed(_token, msg.sender, _tokenSnapshotIdx, _accountSnapshotIdx, transferAmount, tokenSnapshots[_token][_tokenSnapshotIdx].claimedRevenue);
    }

    /**
     * @notice Claims the revenue from multiple token snapshots
     *
     * @dev All parameters must have the same length
     *
     * @param _tokens Tokens to claim the revenue from
     * @param _tokenSnapshotIdxs Indexes of the token snapshots
     * @param _accountSnapshotIdxs Indexes of the account snapshots
     */
    function claimMultiple(IERC20[] memory _tokens, uint256[] memory _tokenSnapshotIdxs, uint256[] memory _accountSnapshotIdxs) external {
        require(_tokens.length == _tokenSnapshotIdxs.length, "_tokens and _tokenSnapshotIdxs must have the same length.");
        require(_tokens.length == _accountSnapshotIdxs.length, "_tokens and _accountSnapshotIdxs must have the same length.");
        require(_tokens.length > 0, "Arrays must have at least one element.");

        for (uint256 i = 0; i < _tokens.length; i++) {
            claimToken(_tokens[i], _tokenSnapshotIdxs[i], _accountSnapshotIdxs[i]);
        }
    }

    /**
     * @notice Deposits the tokens that will be used as reward
     */
    function depositRewardSupply(uint256 _amount) payable external {
        rewardSupply += _amount;

        voteToken.safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
     * @inheritdoc IController
     */
    function requestTokenDistribution(address _account, uint128 _liquidity, uint32 _duration, uint96 _rewardCoefficient) external override {
        // This flag allows simulating a function call failure in the contract due to out-of-quota
        // TMP-MAYBE-DISABLE
        
        require(poolWhitelisted[msg.sender], "Pool is not whitelisted.");

        uint256 amount = uint256(_liquidity) * uint256(_duration) * uint256(_rewardCoefficient) / REWARD_BASE;

        // If the funds left are less than what is requested, distribute the ones we have, but don't revert
        if (amount > rewardSupply) {
            amount = rewardSupply;
        }

        unchecked {
            rewardSupply -= amount;
        }

        rewardBalance[_account] += amount;

        emit Reward(_account, _liquidity, _duration, _rewardCoefficient, amount);
    }

    // This flag adds methods to enable/disable function call failure due to out-of-quota
    // TMP-MAYBE-DISABLE-METHODS

    /**
     * @notice Collects the reward
     *
     * @param _deposit Whether to deposit the reward in the vote token balance
     *                 or to transfer it to the caller
     */
    function collectReward(bool _deposit) external {
        require(rewardBalance[msg.sender] > 0, "No reward to collect.");

        uint256 amount = rewardBalance[msg.sender];
        rewardBalance[msg.sender] = 0;

        if (_deposit) {
            _depositVoteToken(msg.sender, amount);
        } else {
            voteToken.safeTransfer(msg.sender, amount);
        }
    }

    /**
     * @notice Sets the approval of a proposal
     *
     * @dev Can only be called by the veto holder
     * @dev Can only be called for whitelist proposals
     * @dev Changing the veto holder invalidates all previous approvals
     *
     * @param _proposalIdx Index of the proposal
     * @param _approve Whether to approve or disapprove the proposal
     */
    function setVetoHolderApproval(uint256 _proposalIdx, bool _approve) external {
        require(msg.sender == vetoHolder, "Not the veto holder.");
        require(_proposalIdx < numProposals, "Invalid proposal idx.");
        require(proposals[_proposalIdx].action == Action.WHITELIST, "Not a whitelist proposal.");
        require(block.timestamp <= proposals[_proposalIdx].deadline, "Proposal expired.");
        require(!proposals[_proposalIdx].executed, "Proposal already executed.");

        if (_approve) {
            proposals[_proposalIdx].vetoApprover = vetoHolder;
        } else {
            proposals[_proposalIdx].vetoApprover = address(0);
        }

        emit VetoHolderApproval(_proposalIdx, _approve);

        _checkVote(_proposalIdx);
    }

    /**
     * @notice Transfers the veto power to a new address
     * 
     * @dev Can only be called by the veto holder
     * @dev Transferring the veto power immediately invalidates all previous approvals
     * @dev Transferring to the zero address makes the veto power unnecessary
     * @dev Transferring to a dead address (e.g. vite_ffff...) prevents any further approvals
     *
     * @param _newHolder Address of the new veto holder
     * @param transferToZero Safety check when transferring to the zero address
     */
    function transferVetoPower(address _newHolder, bool transferToZero) external {
        require(msg.sender == vetoHolder, "Not the veto holder.");
        require(_newHolder != vetoHolder, "Already the veto holder.");
        require(_newHolder != address(0) || transferToZero, "Transfer to the zero address.");
        
        address oldHolder = vetoHolder;

        vetoHolder = _newHolder;

        emit VetoPowerTransfer(oldHolder, _newHolder);
    }

    // The following is an instruction for the custom preprocessor implemented in unit tests
    // It adds two methods (getTime() and setTime(uint256)) which allow to manipulate the
    // block.timestamp value in tests

    // TMP-TIMESTAMP-METHODS

}