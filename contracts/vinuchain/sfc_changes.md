# SFC Contract Changes: Old vs New

## Overview

The SFC (Special Fee Contract) is VinuChain's core staking contract. It manages validator creation, stake delegation, epoch reward distribution, lockup mechanics, and slashing. The contract is proxy-upgradeable (Solidity ^0.5.17) and is called by the node's EVM machinery to seal epochs and distribute rewards.

### Timelocked Governance Pattern

Multiple governance parameters now follow a queue/execute/cancel pattern with a 2-day timelock: base reward per second, offline penalty threshold, max correction delta, ownership transfer (7-day), NodeDriverAuth migration, and code copy. This gives stakeholders advance notice of governance changes so they can react before execution.

### Epoch Correction Lifecycle

Corrupted epoch data (where `accumulatedRewardPerToken` drops between consecutive epochs) is handled via a multi-step process:

1. **Detection**: Owner calls `checkAndLogEpochCorruption` to scan a range and flag corrupted epochs.
2. **Queueing**: Owner calls `queueCorruptedEpochCorrection` with the corrected rate. A 2-day timelock, delta cap (`maxCorrectionDelta`), and serialization guard (epoch N-1 must execute first) apply.
3. **Execution**: After the timelock, `executeCorrectionUpdate` re-validates all bounds against current state and applies the correction.
4. **Effect**: `_getEffectiveRewardRate` returns the corrected rate. `_safeCursorPosition` uses it for monotonicity scanning, allowing reward stashing to advance past the previously-corrupted boundary.

Revisions to already-corrected epochs follow the same pattern via `queueCorrectionUpdate` / `executeCorrectionUpdate`. A cancel-requeue cooldown of `CORRECTION_TIMELOCK` prevents the owner from substituting values after delegators have observed the queued correction.

---

## 1. Initializable Contract

- **Removed NatSpec comments** on `initialized`, `initializing`, `initializer()`, and `isConstructor()`.
- **Renamed storage gap** from `______gap` to `__gap`.
- **Added storage layout comment** documenting slot allocation (2 bools packed in slot 0 + 50 gap = 51 slots).

## 2. Ownable Contract

- **Added `using SafeMath for uint256`** to Ownable.
- **Removed all NatSpec comments** (`@dev` blocks on `initialize`, `owner`, `onlyOwner`, `isOwner`, `renounceOwnership`, `transferOwnership`).
- **Disabled `renounceOwnership`**: now reverts with `"renounce ownership is disabled"` instead of transferring ownership to `address(0)`.
- **Two-step ownership transfer**: replaced immediate `_transferOwnership` with a pending owner pattern:
  - New state variables: `_pendingOwner`, `_pendingOwnerDeadline`.
  - New constant: `OWNERSHIP_TRANSFER_WINDOW = 7 days`.
  - New event: `OwnershipTransferStarted`.
  - `transferOwnership` now sets a pending owner with a 7-day deadline. Includes an anti-overwrite guard: requires the current pending transfer to be expired or nonexistent, preventing the owner from front-running `acceptOwnership()` by overwriting the pending owner.
  - New function `acceptOwnership()`: pending owner must accept within the deadline.
  - New view functions: `pendingOwner()` (returns `address(0)` if deadline expired), `pendingOwnerDeadline()`.
  - Removed internal `_transferOwnership` function.
- **Reduced storage gap** from `______gap[50]` to `__gap[48]` (2 slots consumed by `_pendingOwner` + `_pendingOwnerDeadline`; total remains 51 slots).
- **Added storage layout comment** documenting slot allocation.

## 3. ReentrancyGuard

- **Added comment** explaining ReentrancyGuard is NOT a standalone contract but implemented inline within SFC to avoid inserting 50 storage slots into the inheritance chain (which would break proxy upgrades).

## 4. NodeDriverAuth Contract

- **Removed all NatSpec comments** throughout the contract.
- **Added constants**: `ADMIN_TIMELOCK = 2 days`, `MAX_ADVANCE_EPOCHS = 10`, `MAX_INC_NONCE = 256`.
- **Added timelock state variables**: `pendingMigration`, `pendingMigrationUnlockTime`, `pendingCopyCodeTarget`, `pendingCopyCodeSource`, `pendingCopyCodeUnlockTime`.
- **Added events**: `MigrationQueued`, `MigrationExecuted`, `MigrationCancelled`, `CopyCodeQueued`, `CopyCodeExecuted`, `CopyCodeCancelled`, `NonceIncremented`.
- **Added input validation** in `initialize`: requires `_sfc != address(0)` and `_driver != address(0)`.
- **Timelocked migration**: replaced `migrateTo` (immediate) with `queueMigration` / `executeMigration` / `cancelMigration` (2-day timelock). Added contract existence checks.
- **Timelocked code copy**: replaced `upgradeCode` and `copyCode` (immediate) with `queueCopyCode` / `executeCopyCode` / `cancelCopyCode` (2-day timelock). Added contract existence re-verification at execution.
- **Rate-limited nonce increment**: `incNonce` now requires `diff <= MAX_INC_NONCE (256)` and emits `NonceIncremented`.
- **Rate-limited epoch advance**: `advanceEpochs` now requires `num <= MAX_ADVANCE_EPOCHS (10)`.
- **Added storage gap**: `__gap[43]` (43 slots after 7 state variables = 50 slots for future upgrades).
- **Added storage layout comment**.

## 5. NodeDriver Contract

- **Removed all NatSpec comments** throughout the contract.
- **Deprecated SFC slot**: `SFC internal sfc` replaced with `uint256 internal _deprecated_sfc_slot` to preserve storage layout.
- **Added input validation** in `setBackend`: requires `_backend != address(0)`.
- **Added input validation** in `initialize`: requires `_backend != address(0)` and `_evmWriterAddress != address(0)`.

## 6. StakersConstants Contract

- **Removed all NatSpec comments** throughout the contract.
- **Clarified comments** on `contractCommission` ("protocol fee on tx rewards, independent of unlockedRewardRatio") and `unlockedRewardRatio` ("portion of base reward paid to unlocked stake, independent of contractCommission").
- **Added `minDelegation()`**: new function returning `1e16` (0.01 VC minimum delegation).

## 7. Version Contract

- No changes.

## 8. SFC Contract

### 8.1 Storage Layout & Proxy Safety

- **Added extensive storage layout comment** at the top of SFC documenting inherited slot ranges, proxy upgrade compatibility notes, and how new variables are appended safely.
- **Added constants**:
  - `MAX_BASE_REWARD_PER_SECOND = 32967977168935185184` (replaces inline magic number `32.967977168935185184 * 1e18`).
  - `MIN_OFFLINE_PENALTY_THRESHOLD_TIME = 20 minutes` — enforced by `queueOfflinePenaltyThreshold`.
  - `MIN_OFFLINE_PENALTY_THRESHOLD_BLOCKS_NUM = 20` — enforced by `queueOfflinePenaltyThreshold`.
  - `MAX_CORRUPTION_CHECK_EPOCHS = 100` — caps per-call gas in corruption detection and safe cursor scanning.
- **Renamed `genesisValidator`** (public address) to `_legacyGenesisValidator` (internal). Added a `genesisValidator()` view function to preserve the ABI. Added comments explaining the slot must remain an address for proxy safety.
- **Changed visibility** of `offlinePenaltyThresholdBlocksNum` and `offlinePenaltyThresholdTime` from internal/default to `public`.
- **Added EpochSnapshot fields**: `selfStake`, `lockedSelfStake`, `lockedSelfStakeDuration` mappings (used for snapshot-based commission calculation).

### 8.2 New Structs, State Variables & Internal State (appended after original storage)

**New structs:**

- `StakeWithoutAmount` — `(address delegator, uint256 validatorId, uint96 timestamp)` — compact stake record for the paginated `getStakes` getter.
- `Stake` — `(address delegator, uint96 timestamp, uint256 validatorId, uint256 amount)` — returned by `getStakes`.
- `PendingCorrection` — `(uint256 correctedAccumulatedRewardPerToken, string reason, uint256 unlockTime)` — queued epoch corrections.
- `_SealEpochRewardsCtx` — internal struct used to avoid stack-too-deep in `_sealEpoch_rewards` (holds `epochDuration`, `epochFee`, `totalBaseRewardWeight`, `totalTxRewardWeight`, and per-validator weight arrays).

**New state variables:**

- `stakes` — `StakeWithoutAmount[]` internal — backing array for `getStakes` paginated getter. A sentinel entry at index 0 is pushed during `initialize`.
- `stakePosition` — `mapping(address => mapping(uint256 => uint256))` internal — maps `(delegator, validatorID)` to index in `stakes`.
- `corruptedEpochs` — `mapping(uint256 => mapping(uint256 => bool))` — marks corrupted epoch/validator pairs.
- `correctedEpochRewardRate` — `mapping(uint256 => mapping(uint256 => uint256))` — stores corrected accumulated reward per token.
- `isEpochCorrected` — `mapping(uint256 => mapping(uint256 => bool))` — tracks whether an epoch has been corrected.
- `correctionReasonHash` — `mapping(uint256 => mapping(uint256 => bytes32))` — stores `keccak256(reason)` for corrections.
- `CORRECTION_TIMELOCK = 2 days` (constant).
- `maxCorrectionDelta` — bounds correction magnitude.
- `PendingCorrection` struct and `pendingCorrections` mapping.
- `pendingMaxCorrectionDelta`, `pendingMaxCorrectionDeltaUnlockTime` — timelocked max delta updates.
- `pendingBaseRewardPerSecond`, `pendingBaseRewardPerSecondUnlockTime` — timelocked base reward updates.
- `pendingOfflinePenaltyBlocksNum`, `pendingOfflinePenaltyTime`, `pendingOfflinePenaltyUnlockTime` — timelocked offline penalty updates.
- `usedPubkeyHash` — `mapping(bytes32 => bool)` — prevents pubkey reuse.
- `isGenesisValidator` — `mapping(address => bool)` — tracks all genesis validators (replaces single-address approach).
- `_reentrancyGuardCounter` — inline reentrancy guard (not inherited).
- `correctionCancelTime` — `mapping(uint256 => mapping(uint256 => uint256))` — records the timestamp of the last `cancelCorrectionUpdate` call per `(epoch, validatorID)`. Enforces a `CORRECTION_TIMELOCK` cooldown before re-queuing, preventing the owner from substituting the queued correction value after delegators have observed and planned around the original.
- `__gap[48]` — storage gap for future upgrades.

### 8.3 New Events

- `PenaltyApplied(delegator, validatorID, penalty)`
- `PenaltyUndelegated(delegator, toValidatorID, amount)`
- `EpochDataCorrupted(validatorID, fromEpoch, toEpoch, stashedRate, currentRate)`
- `CorrectionUpdateQueued(epoch, validatorID, correctedAccumulatedRewardPerToken, unlockTime, reason)`
- `CorrectionUpdateExecuted(epoch, validatorID, correctedAccumulatedRewardPerToken, reason)`
- `CorrectionUpdateCancelled(epoch, validatorID)`
- `MaxCorrectionDeltaUpdated(oldValue, newValue)`
- `MaxCorrectionDeltaQueued(newValue, unlockTime)`
- `MaxCorrectionDeltaCancelled()`
- `ReactivatedValidator(validatorID)`
- `BaseRewardPerSecQueued(newValue, unlockTime)`
- `BaseRewardPerSecExecuted(oldValue, newValue)`
- `BaseRewardPerSecCancelled()`
- `OfflinePenaltyThresholdQueued(blocksNum, time, unlockTime)`
- `OfflinePenaltyThresholdCancelled()`
- `EpochSealed(epoch, endTime, baseRewardPerSecond, totalSupply)` — emitted at the end of `sealEpoch` to allow off-chain indexers (subgraphs, explorers, staking dashboards) to detect epoch boundaries without polling `currentSealedEpoch`.
- `RewardsStashed(delegator, validatorID, epoch)` — emitted by the external `stashRewards` function to provide an audit trail when a third party advances a delegator's stash cursor.
- `EpochUncorrupted(epoch, validatorID)` — emitted when `uncorruptEpoch` clears a false-positive corruption flag.
- **Changed** `UpdatedBaseRewardPerSec` from `(uint256 value)` to `(uint256 oldValue, uint256 newValue)`.

### 8.4 New Functions

- **`constructor()`** — locks the bare implementation contract against direct initialization. Uses the `initializer` modifier, which sets `initialized = true` in the implementation's own storage during deployment (when `extcodesize == 0`). Any subsequent call to `initialize()` on the implementation address reverts. Proxy deployments are unaffected because each proxy has independent storage where `initialized` starts as false.
- **`genesisValidator()`** — view function preserving the original ABI for `_legacyGenesisValidator`.
- **`getStakes(offset, limit)`** — paginated getter returning a `Stake[]` array (delegator, timestamp, validatorId, amount) with a max limit of 1000 entries. New; did not exist in old SFC.
- **`getWrRequests(delegator, validatorID, offset, limit)`** — paginated getter returning `WithdrawalRequest[]` capped to `wrIdCount` entries. New; did not exist in old SFC.
- **`getEpochCorrectionInfo(epoch, validatorID)`** — returns whether an epoch is corrected and the corrected rate.
- **`getEffectiveRewardRate(epoch, validatorID)`** — returns the effective (corrected or original) reward rate.
- **`getCorrectionReasonHash(epoch, validatorID)`** — returns the correction reason hash.
- **`getPendingCorrection(epoch, validatorID)`** — returns pending correction details.
- **`checkAndLogEpochCorruption(validatorID, fromEpoch, toEpoch)`** — owner-only function to scan and mark corrupted epochs (capped at `MAX_CORRUPTION_CHECK_EPOCHS = 100` epochs per call).
- **`_checkAndLogEpochCorruptionRange()`** — internal implementation.
- **`_getEffectiveRewardRate(epoch, validatorID)`** — internal helper; returns corrected rate if available, otherwise snapshot rate.
- **`_newRewardsUpTo(delegator, validatorID, payableUntil)`** — internal function for computing rewards up to a specific epoch (extracted from `_newRewards`).
- **`_safeCursorPosition(delegator, validatorID, payableEpoch)`** — internal helper; finds the highest safe epoch for reward stashing, stopping at corrupted data boundaries.
- **`queueCorruptedEpochCorrection(epoch, validatorID, correctedRate, reason)`** — owner-only; queues a correction for a corrupted epoch with 2-day timelock and delta bounds.
- **`queueCorrectionUpdate(epoch, validatorID, correctedRate, reason)`** — owner-only; queues an update to an already-corrected epoch.
- **`executeCorrectionUpdate(epoch, validatorID)`** — owner-only; executes a pending correction after timelock expires (re-validates bounds at execution time).
- **`cancelCorrectionUpdate(epoch, validatorID)`** — owner-only; cancels a pending correction.
- **`queueMaxCorrectionDelta(maxDelta)`** — owner-only; queues a max correction delta update (capped at `MAX_CORRECTION_DELTA_CAP = 1e16`).
- **`executeMaxCorrectionDelta()`** — owner-only; executes pending max delta update.
- **`cancelMaxCorrectionDelta()`** — owner-only; cancels pending max delta update.
- **`queueBaseRewardPerSecond(value)`** — owner-only; replaces `updateBaseRewardPerSecond` with timelocked version.
- **`executeBaseRewardPerSecond()`** — owner-only; executes pending base reward update.
- **`cancelBaseRewardPerSecond()`** — owner-only; cancels pending base reward update.
- **`queueOfflinePenaltyThreshold(blocksNum, time)`** — owner-only; replaces `updateOfflinePenaltyThreshold` with timelocked version.
- **`executeOfflinePenaltyThreshold()`** — owner-only; executes pending offline penalty update. Unlike `executeBaseRewardPerSecond` (which emits `BaseRewardPerSecExecuted`), this reuses the existing `UpdatedOfflinePenaltyThreshold` event rather than introducing a dedicated "executed" event.
- **`cancelOfflinePenaltyThreshold()`** — owner-only; cancels pending offline penalty update.
- **`uncorruptEpoch(epoch, validatorID)`** — owner-only; removes a `corruptedEpochs` flag for falsely-flagged epochs. Cannot be called once a correction has been executed or while a pending correction exists. Note: this only clears the flag — `_safeCursorPosition` scans rate monotonicity directly, so clearing the flag without applying a correction does not unblock reward stashing for true rate inversions.
- **`_stashValidatorCommission(snapshot, validatorID, commissionRewardFull)`** — extracted commission stashing logic using snapshot-based self-stake. Only accumulates `lockupBaseReward` and `lockupExtraReward` into `getStashedLockupRewards` when the validator is locked up (`isLockedUp` guard), preserving the invariant that `unlockedReward` is never written to the stash.
- **`_checkWithdrawalEligibility(delegator, validatorID, request)`** — extracted from `withdraw` to avoid stack-too-deep.
- **`_calculateAndApplyWithdrawalPenalty(validatorID, amount)`** — extracted from `withdraw`.
- **`reactivateValidator(validatorID)`** — owner-only; reactivates deactivated validators (not cheaters) if self-stake meets minimum. Requires the validator was previously deactivated (`deactivatedEpoch != 0`), is not already active, has no cheater flag, and that the delegated stake limit is not exceeded after reactivation. Resets `deactivatedEpoch` and `deactivatedTime` to 0, calls `_syncValidator(validatorID, true)` (with pubkey sync), and emits `ReactivatedValidator`.
- **`rewardsBlockedByCorruption(delegator, validatorID)`** — view function returning `(bool blocked, uint256 blockedAtEpoch)`; returns `blocked = true` and the safe cursor epoch if rewards are blocked by corrupted data, otherwise `(false, 0)`.
- **`nonReentrant` modifier** — inline reentrancy guard using `_reentrancyGuardCounter`.

### 8.5 Removed Functions

- **`updateBaseRewardPerSecond(value)`** — replaced by queue/execute/cancel pattern.
- **`updateOfflinePenaltyThreshold(blocksNum, time)`** — replaced by queue/execute/cancel pattern.

Note: `_transferOwnership(newOwner)` was removed from the inherited `Ownable` contract (see Section 2), not from SFC directly.

### 8.6 Modified Functions

#### `initialize()`

- Added `require(nodeDriver != address(0))` and `require(_totalSupply > 0)`.
- Initializes `_reentrancyGuardCounter = 1`.
- Added `require(baseRewardPerSecond <= MAX_BASE_REWARD_PER_SECOND)`.
- Emits `UpdatedBaseRewardPerSec(0, baseRewardPerSecond)` (with old/new values).
- Emits `UpdatedOfflinePenaltyThreshold`.
- Initializes `maxCorrectionDelta = 1e14` and emits `MaxCorrectionDeltaUpdated`.
- Pushes a sentinel `StakeWithoutAmount` entry at index 0 of the `stakes` array (delegator=0, validatorId=0, timestamp=0). This ensures position 0 is never assigned to a real stake, simplifying the swap-and-pop logic in `_removeStake`.

#### `setGenesisValidator()`

- Replaced `genesisValidator = auth` with `isGenesisValidator[auth] = true` (tracks all genesis validators via mapping, not just the last one).

#### `setGenesisDelegation()`

- Added `require(_validatorExists(toValidatorID))`.

#### `createValidator()`

- Added `nonReentrant` modifier.
- Changed pubkey validation from `require(pubkey.length > 0)` to `require(pubkey.length == 33 || pubkey.length == 65)`.

#### `_createValidator()`

- Changed `++lastValidatorID` to `lastValidatorID = lastValidatorID.add(1)` (SafeMath).

#### `_rawCreateValidator()`

- Added `require(auth != address(0))`.
- Added `require(pubkey.length == 33 || pubkey.length == 65)`.
- Added `require(getValidator[validatorID].createdTime == 0)` (prevents validator ID reuse).
- Added pubkey uniqueness check via `usedPubkeyHash` mapping.

#### `delegate()`

- Added `nonReentrant` modifier.

#### `_rawDelegate()`

- Added `require(delegator != address(0))`.
- Added `require(block.timestamp <= 2**96 - 1)` (timestamp overflow check for uint96 storage).
- Note: `minDelegation()` check is in `_delegate`, not `_rawDelegate` — see Section 8.9 "Genesis Delegation Minimum".

#### `_delegate()`

- Added `require(amount >= minDelegation())` (0.01 VC minimum). Placed here (not in `_rawDelegate`) so that `setGenesisDelegation` (which calls `_rawDelegate` directly) bypasses the minimum.

#### `_removeStake()`

- Changed `assert(position < stakesLength)` to `require(position < stakesLength, "invalid stake position")`.
- Added `require(position != 0, "cannot remove sentinel stake entry")`.
- Fixed swap-and-pop: reads removed delegator/validatorId before swap, updates `stakePosition` for the moved entry using post-swap position, and zeroes out `stakePosition` for the removed entry.
- Removed `assert(stakesLength - 1 != 0)`.

#### `undelegate()`

- Added `nonReentrant` modifier.
- Added corruption-awareness: checks `_safeCursorPosition` and requires rewards are not blocked by corruption before allowing undelegation.
- Changed `wrIdCount[delegator][toValidatorID]++` to SafeMath `.add(1)`.

#### `getSlashingPenalty()`

- Changed penalty calculation from `amount.mul(Decimal.unit() - refundRatio).div(Decimal.unit()).add(1)` to a ceiling division: only adds 1 if there's a remainder. Prevents dust rounding on exact divisions.
- Added `if (penalty > amount) return amount` safety cap.

#### `withdraw()`

- Added `nonReentrant` modifier.
- Refactored into `_checkWithdrawalEligibility` + `_calculateAndApplyWithdrawalPenalty` to avoid stack-too-deep.
- Removed `require(amount > penalty, "stake is fully slashed")` — now allows full-slash withdrawals (withdrawable = 0).
- Added `if (withdrawable > 0)` guard before transfer.
- Comment: "Removed .gas(2300) — breaks smart contract wallets".
- Withdrawal period logic refactored into `_checkWithdrawalEligibility`: now checks `if (getValidator[toValidatorID].auth == delegator)` for the validator-length withdrawal period, else uses the standard period. The extended window applies only when withdrawing from your own validator.
- Uses SafeMath `.add()` instead of `+` for time/epoch comparisons.

#### `deactivateValidator()` (SFC)

- Added `require(_validatorExists(validatorID))`.

#### `_calcRawValidatorEpochBaseReward()`

- Added `|| totalBaseRewardWeight == 0` to the zero-check guard.

#### `_calcRawValidatorEpochTxReward()`

- Added `|| totalTxRewardWeight == 0` to the zero-check guard.
- Changed `Decimal.unit() - contractCommission()` to `Decimal.unit().sub(contractCommission())` (SafeMath).

#### `_highestLockupEpoch()`

- Changed `(l + r) / 2` to `l.add(r.sub(l).div(2))` (SafeMath, avoids overflow).
- Changed `l = m + 1` to `l = m.add(1)`.

#### `_scaleLockupReward()`

- Changed `Decimal.unit() - unlockedRewardRatio()` to `Decimal.unit().sub(unlockedRewardRatio())`.
- Changed `unlockedRewardRatio() + lockupExtraRatio` to `unlockedRewardRatio().add(lockupExtraRatio)`.
- Changed `totalScaledReward - reward.lockupBaseReward` to `totalScaledReward.sub(reward.lockupBaseReward)`.

#### `_newRewards()`

- Now delegates to `_newRewardsUpTo(delegator, toValidatorID, _highestPayableEpoch(toValidatorID))`.

#### `_newRewardsUpTo()` (extracted from old `_newRewards`)

- Added lockedStake capping: `effectiveLockedStake = min(ld.lockedStake, wholeStake)` to prevent underflow after partial slashing.

#### `_newRewardsOf()`

- Now uses `_getEffectiveRewardRate()` instead of reading raw snapshot rates directly.
- Returns 0 if `currentRate < stashedRate` (corrupted data protection) instead of causing an underflow revert.

#### `stashRewards()`

- Added `nonReentrant` modifier.
- Added `require(getStake[delegator][toValidatorID] > 0)` (prevents gas griefing).
- Emits `RewardsStashed(delegator, toValidatorID, stashedRewardsUntilEpoch)` after a successful stash.

#### `_stashRewards()`

- Now uses `_safeCursorPosition` to compute a safe stash boundary that stops at corrupted epoch data.
- Uses `_newRewardsUpTo(delegator, toValidatorID, safeCursor)` instead of `_newRewards`.

#### `claimRewards()`

- Added `nonReentrant` modifier.
- Comment: "Removed .gas(2300) — breaks smart contract wallets".

#### `restakeRewards()`

- Added `nonReentrant` modifier.
- Changed `getLockupInfo[delegator][toValidatorID].lockedStake += lockupReward` to use SafeMath `.add()`.
- Added lockup validation: now checks `isLockedUp`, requires lockup not expired, requires remaining duration >= `minLockupDuration()`.
- Resets `ld.fromEpoch = currentEpoch()` to prevent retroactive lockup reward gaming.
- Added proportional scaling of `getStashedLockupRewards` when increasing `lockedStake`: `lockupBaseReward` and `lockupExtraReward` are scaled by `newLockedStake / oldLockedStake` (guarded by `oldLockedStake > 0`) to preserve the per-unit early-exit penalty rate. Without this, repeated restaking would dilute the effective penalty.

#### `_syncValidator()`

- Changed visibility from `public` to `internal`.
- Removed comment "emit special log for node".

#### `_sealEpoch_offline()`

- Now returns `bool[] memory deactivated` array indicating which validators were deactivated.

#### `_sealEpoch_rewards()`

- Added `bool[] memory deactivated` parameter.
- Skips deactivated validators in base/tx reward weight calculations.
- Added uptime capping: `uptimes[i]` is capped to `epochDuration` in all three loops (tx reward weights, base reward weights, and the deactivated/active validator handler) to prevent over-rewarding validators whose reported uptime exceeds the actual epoch length.
- Deactivated validators get previous epoch's `accumulatedRewardPerToken` carried forward (no new rewards). Their `accumulatedUptime` and `accumulatedOriginatedTxsFee` are still written (with uptime capping applied).
- Validator commission extracted to `_stashValidatorCommission()` which uses **snapshot-based** self-stake (`snapshot.selfStake`, `snapshot.lockedSelfStake`, `snapshot.lockedSelfStakeDuration`) instead of live state.
- `delegatorsReward` uses `rawReward.sub(commissionRewardFull)` (SafeMath) instead of `-`.
- `rewardPerToken` calculation uses `snapshot.receivedStake[validatorID]` (snapshot) instead of `getValidator[validatorID].receivedStake` (live). Prevents manipulation between `sealEpochValidators` and `sealEpoch`.
- All arithmetic converted from raw operators (`-`, `*`, `/`, `+`) to SafeMath (`.sub()`, `.mul()`, `.div()`, `.add()`).

#### `sealEpoch()`

- Added `require(validatorIDs.length > 0, "validators not sealed yet")` ensuring `sealEpochValidators` was called first.
- Added array length mismatch checks for all four input arrays.
- Passes `deactivated` array from `_sealEpoch_offline` to `_sealEpoch_rewards`.
- Emits `EpochSealed(currentSealedEpoch, endTime, baseRewardPerSecond, totalSupply)` after writing the snapshot fields.

#### `sealEpochValidators()`

- Added `MAX_VALIDATORS = 200` constant and `require(nextValidatorIDs.length <= MAX_VALIDATORS)`.
- Added `require(snapshot.validatorIDs.length == 0)` — prevents double-sealing.
- Added per-validator checks: `_validatorExists`, `status == OK_STATUS`, `receivedStake > 0`, duplicate check via `snapshot.receivedStake[validatorID] == 0`.
- Now snapshots `selfStake`, `lockedSelfStake`, and `lockedSelfStakeDuration` per validator.

#### `getUnlockedStake()`

- Added underflow protection: caps `lockedStake` to actual `stake`, returns 0 if locked > stake (handles partial slashing).

#### `_lockStake()`

- Added `require(_validatorExists(toValidatorID))`.
- Changed delegator lockup duration check: instead of comparing absolute end times (`validatorEndTime >= delegatorEndTime`), now compares durations (`lockupDuration <= validatorRemainingTime`). Error message changed to "lockup duration exceeds validator's remaining lockup time".

#### `lockStake()`

- Added `nonReentrant` modifier.

#### `relockStake()`

- Added `nonReentrant` modifier.
- Added `require(amount > 0, "zero amount")`.

#### `_popDelegationUnlockPenalty()`

- Added `require(totalAmount > 0, "zero total locked amount")`.
- Changed `lockupExtraRewardShare + lockupBaseRewardShare / 2` to SafeMath `.add().div()`.
- Added proportional scale-back of reward deductions when penalty is capped at `unlockAmount` (prevents over-deduction of stashed rewards relative to actual penalty).

#### `unlockStake()`

- Added `nonReentrant` modifier.
- Added corruption guard: calls `_stashRewards`, then checks `_safeCursorPosition >= payableEpoch` before proceeding. Prevents unlocking while rewards are blocked by corruption (which would destroy the lockup penalty basis if `lockedStake` reaches zero and triggers cleanup).
- Changed `ld.lockedStake -= amount` to `ld.lockedStake = ld.lockedStake.sub(amount)` (SafeMath).
- Added lockedStake clamping after penalty: if `_rawUndelegate` penalty pushes `lockedStake > stake`, clamps it to current stake (prevents trapped funds). When the clamp fires, `getStashedLockupRewards` is also scaled proportionally by `currentStake / ld.lockedStake` to preserve the rewards-to-stake ratio; without this, future partial unlocks would see an inflated penalty basis.
- Added `PenaltyApplied` and `PenaltyUndelegated` event emissions.
- Added cleanup: deletes `getLockupInfo` and `getStashedLockupRewards` when `lockedStake == 0`.
- Added `_syncValidator(toValidatorID, false)` call.

#### `currentEpoch()`

- Changed `return currentSealedEpoch + 1` to `return currentSealedEpoch.add(1)` (SafeMath). The raw `+` was the only arithmetic on a storage variable not using SafeMath; an overflow would corrupt `getEpochSnapshot[0]` (genesis data).

#### `isSlashed()`

- Fixed operator-precedence bug: changed `getValidator[validatorID].status & CHEATER_MASK != 0` to `(getValidator[validatorID].status & CHEATER_MASK) != 0`. In Solidity, `!=` binds tighter than `&`, so the unparenthesised form was evaluating `CHEATER_MASK != 0` (always `true`/`1`) and then testing bit 0 (WITHDRAWN_BIT) instead of bit 7 (DOUBLESIGN_BIT). Double-signers were never detected as slashed; withdrawn validators were wrongly penalised as cheaters.

#### `reactivateValidator()`

- Fixed operator-precedence bug in the cheater guard: changed `getValidator[validatorID].status & CHEATER_MASK == 0` to `(getValidator[validatorID].status & CHEATER_MASK) == 0`. The unparenthesised form evaluated `CHEATER_MASK == 0` (always `false`/`0`), making the `require` always pass and allowing any slashed validator to be reactivated.
- `_checkDelegatedStakeLimit` is called before state mutations (`totalActiveStake` update, `status = OK_STATUS`, deactivated fields reset).

#### `_checkWithdrawalEligibility()`

- Fixed withdrawal cooling-off period bypass: `wPeriodTime` and `wPeriodEpochs` are now computed before the validator-deactivation substitution block. The substitution only fires when `deactivatedTime.add(wPeriodTime) > requestTime` — i.e., the deactivation happened recently enough that some waiting time remains. Previously, a validator deactivated long before the undelegation would push the deadline into the past, allowing instant withdrawal.
- Restricted the extended 3-day/180-epoch withdrawal period to `getValidator[toValidatorID].auth == delegator` only (withdrawing your own validator's stake). The previous condition `|| getValidatorID[delegator] != 0` granted the extended window to any registered validator address withdrawing from any other validator — including fully deactivated ex-validators with no current validator responsibilities.

#### `cancelCorrectionUpdate()`

- Now records `correctionCancelTime[epoch][validatorID] = _now()` on cancellation. This timestamp is checked by `queueCorruptedEpochCorrection` and `queueCorrectionUpdate` to enforce a `CORRECTION_TIMELOCK` cooldown before re-queuing for the same `(epoch, validatorID)` pair.

#### `queueCorruptedEpochCorrection()`

- Added cancel-requeue cooldown guard: requires that `correctionCancelTime[epoch][validatorID] == 0` (never cancelled) or that `CORRECTION_TIMELOCK` has elapsed since the last cancellation. Prevents the owner from cancelling an observed queued value and immediately re-queuing a different value, which would substitute the correction after delegators have already planned around the original.

#### `queueCorrectionUpdate()`

- Added serialization guard matching `queueCorruptedEpochCorrection`: when `epoch > 1`, requires `pendingCorrections[epoch.sub(1)][validatorID].unlockTime == 0`. Prevents the delta-cap check from being evaluated against a stale `previousRate` when epoch N-1's pending correction has not yet executed.
- Added the same cancel-requeue cooldown guard as `queueCorruptedEpochCorrection`.

### 8.7 Removed NatSpec Comments

All `@dev`, `@param`, and `@return` NatSpec documentation blocks were removed throughout the SFC contract and replaced with inline comments where necessary.

### 8.8 SafeMath Migration

All raw arithmetic operators (`+`, `-`, `*`, `/`) were replaced with SafeMath equivalents (`.add()`, `.sub()`, `.mul()`, `.div()`) across the entire contract to prevent overflow/underflow vulnerabilities.

### 8.9 Security Fixes (Post-Audit)

#### Correction Deadlock Fix

- **`_checkAndLogEpochCorruptionRange()`** — changed `prevRate` from reading `getEpochSnapshot[epoch].accumulatedRewardPerToken` directly to using `_getEffectiveRewardRate(epoch, validatorID)`. Previously, after corrections were applied to epoch N, running the function again would still use the raw (corrupted) rate of epoch N as the baseline for checking epoch N+1. If epoch N+1's raw rate was above the corrupted rate but below the corrected rate, epoch N+1 would go undetected, and epoch N's correction would be blocked by the upper-bound check (`correctedRate <= nextRate`). This created an irresolvable deadlock permanently preventing affected delegators from undelegating.

#### Escape Hatch for Corrupted Epochs

- **Added `EpochUncorrupted(epoch, validatorID)` event**.
- **Added `uncorruptEpoch(epoch, validatorID)`** — owner-only; removes a `corruptedEpochs` flag. Provides an escape hatch for falsely-flagged epochs and for cases where the required correction delta would exceed `MAX_CORRECTION_DELTA_CAP` (which would otherwise permanently block delegators from undelegating). Cannot be called once a correction has already been executed; not callable while a pending correction exists.

#### Standard Reentrancy Guard

- **`nonReentrant` modifier** — replaced the inverted counter-based implementation with the standard OpenZeppelin pattern (`1 = not entered`, `2 = entered`). The previous implementation allowed reentrant calls to execute to completion (passing their own `require(counter==counter)` check) before the outer call reverted. While functionally safe due to EVM atomicity, it was non-standard, wasted gas on reentrancy attempts, and would be flagged by security auditors. The new implementation blocks the reentrant call upfront before any body executes.

#### Genesis Delegation Minimum

- **`minDelegation()` check moved from `_rawDelegate` to `_delegate`** — `setGenesisDelegation` calls `_rawDelegate` directly (bypassing `_delegate`), so genesis delegations are no longer subject to the 0.01 VC minimum. This prevents network bootstrap failures where genesis stakes might be smaller than the live minimum. All user-facing delegation paths still enforce the minimum via `_delegate`.

#### `getPendingCorrection` Reason Exposure

- **`getPendingCorrection(epoch, validatorID)`** — changed return type from `(uint256, uint256, bytes32 reasonHash)` to `(uint256, uint256, string memory reason)`. Previously only a keccak256 hash of the reason was returned, making on-chain verification of correction justifications impossible without event log access. **Note: this is an ABI-breaking change for callers of this view function.**

#### Pre-Initialization Reentrancy Guard Gap

- **`nonReentrant` modifier** — changed `require(_reentrancyGuardCounter != 2)` to `require(_reentrancyGuardCounter == 1)`. The `!= 2` form allowed calls while the counter was still at its Solidity-default value of `0` (before `initialize()` sets it to `1`), creating a window where reentrancy protection was absent. The `== 1` form blocks both the reentrant case (counter is `2`) and the pre-initialization case (counter is `0`).

#### Adjacent Correction Serialization

- **`queueCorruptedEpochCorrection()`** — added a serialization guard requiring that epoch N-1's pending correction has `unlockTime == 0` before epoch N's correction can be queued (when `epoch > 1`). Without this, two corrections queued back-to-back for epochs N and N+1 would both measure their delta against un-executed baselines, compounding the effective rate shift by `K × maxCorrectionDelta` for K consecutive corrections.
- **`queueCorrectionUpdate()`** — added the same serialization guard.

#### Withdrawal Cooling-off Period Bypass

- **`_checkWithdrawalEligibility()`** — the deactivation-time substitution previously fired whenever `deactivatedTime < requestTime`, which includes cases where the validator was deactivated days or weeks before the undelegation. In those cases, `deactivatedTime + wPeriodTime` was already in the past, making `_now() >= requestTime + wPeriodTime` trivially true and allowing instant withdrawal. Fixed by computing `wPeriodTime` before the substitution block and only substituting when `deactivatedTime.add(wPeriodTime) > requestTime`.

#### Operator Precedence Bugs in Bitwise Status Checks

- **`isSlashed()`** — `status & CHEATER_MASK != 0` was parsed as `status & (CHEATER_MASK != 0)` → `status & 1`, testing WITHDRAWN_BIT instead of DOUBLESIGN_BIT. Double-signers were never identified as slashed; withdrawn validators were wrongly penalised. Fixed with explicit parentheses: `(status & CHEATER_MASK) != 0`.
- **`reactivateValidator()`** — `status & CHEATER_MASK == 0` was parsed as `status & (CHEATER_MASK == 0)` → `status & 0`, always zero, making the cheater guard non-functional. Any slashed validator could be reactivated. Fixed with explicit parentheses: `(status & CHEATER_MASK) == 0`.

#### `currentEpoch()` Raw Arithmetic

- **`currentEpoch()`** — `return currentSealedEpoch + 1` used a raw addition, the only raw arithmetic on a storage variable in an otherwise fully SafeMath-migrated contract. An overflow (at `uint256.max`) would write into `getEpochSnapshot[0]`, corrupting genesis data. Changed to `currentSealedEpoch.add(1)`.

#### `lockedStake` Clamp Without Stash Scaling

- **`unlockStake()`** — when a penalty undelegation pushed `lockedStake` above the remaining total stake (possible if prior slashing had already reduced total stake without reducing `lockedStake`), the clamp to `currentStake` left `getStashedLockupRewards` with a disproportionately large value relative to the new locked amount. Subsequent partial unlock penalty calculations would use an inflated rewards-to-stake ratio. Fixed by scaling `lockupBaseReward` and `lockupExtraReward` proportionally by `currentStake / ld.lockedStake` before applying the clamp.

#### Cancel-Requeue Correction Bypass

- **`cancelCorrectionUpdate()` + `queueCorruptedEpochCorrection()` + `queueCorrectionUpdate()`** — the owner could cancel a queued correction immediately before execution and re-queue with a different value, giving delegators effectively zero advance notice of the actual correction. Added `correctionCancelTime` mapping and a `CORRECTION_TIMELOCK` cooldown between cancellation and re-queue for the same `(epoch, validatorID)` pair.

#### Extended Withdrawal Period Restriction

- **`_checkWithdrawalEligibility()`** — the condition `|| getValidatorID[delegator] != 0` granted the 3-day/180-epoch withdrawal period to any registered validator address for withdrawals from any validator — including fully deactivated ex-validators delegating to unrelated validators. Restricted to `getValidator[toValidatorID].auth == delegator` only (withdrawing your own validator's stake).

#### Implementation Contract Initialization Lock

- **`constructor()`** — added to `SFC` using the `initializer` modifier. This sets `initialized = true` in the implementation contract's own storage at deployment time, preventing anyone from calling `initialize()` directly on the bare implementation address (a classic proxy frontrun vector). Proxy deployments are unaffected: each proxy has independent storage where `initialized` starts at zero.
