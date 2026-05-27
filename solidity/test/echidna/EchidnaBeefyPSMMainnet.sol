// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {BeefyVaultPSMV2} from 'contracts/BeefyVaultPSM/V2.sol';
import {MockERC20Echidna, MockBeefyVault} from './EchidnaBeefyPSM.sol';

/// @title EchidnaBeefyPSMMainnet
/// @notice Echidna property test harness for BeefyVaultPSMV2 (Ethereum version)
/// @dev Uses hevm.prank for multi-actor testing and hevm.warp for time advancement.
///      MAI_ADDRESS is configurable on mainnet, so no hevm.etch needed.
contract EchidnaBeefyPSMMainnet {
  // HEVM cheatcode interface (Echidna 2.x)
  address internal constant HEVM = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

  BeefyVaultPSMV2 internal psm;
  MockERC20Echidna internal usdc;
  MockERC20Echidna internal mai;
  MockBeefyVault internal vault;

  // Privileged actors must be part of echidna.yaml's sender set so owner-only
  // and guardian-only paths remain reachable during fuzzing.
  address internal constant OWNER = address(0x20000);
  address internal constant GUARDIAN = address(0x30000);

  // Ghost variables (public for post-run inspection)
  uint256 public ghost_totalDeposited;
  uint256 public ghost_totalScheduledMAI;
  uint256 public ghost_totalWithdrawnMAI;
  uint256 public ghost_totalRefundedMAI;
  uint256 public ghost_totalSwept;
  uint256 public ghost_depositCount;
  uint256 public ghost_scheduleCount;
  uint256 public ghost_withdrawCount;
  uint256 public ghost_evacuateCount;
  uint256 public ghost_refundCount;

  constructor() {
    usdc = new MockERC20Echidna('USDC', 'USDC', 6);
    mai = new MockERC20Echidna('MAI', 'MAI', 18);
    vault = new MockBeefyVault(usdc);

    psm = new BeefyVaultPSMV2();
    psm.initialize(address(vault), 0, 30, address(mai));
    psm.setGuardian(GUARDIAN, true);
    psm.transferOwnership(OWNER);
    require(psm.guardians(GUARDIAN), 'guardian handoff failed');
    require(psm.owner() == OWNER, 'owner handoff failed');

    // Fund PSM with MAI so deposits can succeed
    mai.mint(address(psm), 100_000_000 * 10 ** 18);
  }

  // ═══════════════════════════════════════════════════════════
  //  HEVM helpers
  // ═══════════════════════════════════════════════════════════

  function _prank(
    address actor
  ) internal {
    (bool ok,) = HEVM.call(abi.encodeWithSignature('prank(address)', actor));
    require(ok, 'prank failed');
  }

  function _warp(
    uint256 timestamp
  ) internal {
    (bool ok,) = HEVM.call(abi.encodeWithSignature('warp(uint256)', timestamp));
    require(ok, 'warp failed');
  }

  // ═══════════════════════════════════════════════════════════
  //  Actions (msg.sender = fuzz sender, hevm.prank for PSM calls)
  // ═══════════════════════════════════════════════════════════

  function deposit(
    uint256 amount
  ) public {
    if (psm.evacuated()) return;
    amount = _clamp(amount, 2 * 10 ** 6, 100_000 * 10 ** 6);

    address actor = msg.sender;

    usdc.mint(actor, amount);
    _prank(actor);
    usdc.approve(address(psm), amount);

    _prank(actor);
    try psm.deposit(amount) {
      ghost_totalDeposited += amount;
      ghost_depositCount++;
    } catch {}
  }

  function scheduleWithdraw(
    uint256 amount
  ) public {
    if (psm.evacuated()) return;

    address actor = msg.sender;
    if (psm.withdrawalEpoch(actor) != 0) return;

    uint256 totalStable = psm.totalStableLiquidity();
    uint256 totalQueued = psm.totalQueuedLiquidity();
    if (totalStable <= totalQueued) return;

    uint256 availableUsdc = totalStable - totalQueued;
    uint256 availableMai = availableUsdc * 10 ** 12;
    if (availableMai < 2 * 10 ** 18) return;

    amount = _clamp(amount, 2 * 10 ** 18, availableMai);

    mai.mint(actor, amount);
    _prank(actor);
    mai.approve(address(psm), amount);

    _prank(actor);
    try psm.scheduleWithdraw(amount) {
      ghost_totalScheduledMAI += amount;
      ghost_scheduleCount++;
    } catch {}
  }

  function withdraw() public {
    address actor = msg.sender;
    if (psm.withdrawalEpoch(actor) == 0) return;
    if (psm.evacuated()) return; // withdraw blocked post-evacuation

    uint256 epoch = psm.withdrawalEpoch(actor);
    if (block.timestamp < epoch) {
      _warp(epoch);
    }

    uint256 scheduled = psm.scheduledWithdrawalAmount(actor);

    _prank(actor);
    try psm.withdraw() {
      ghost_totalWithdrawnMAI += scheduled;
      ghost_withdrawCount++;
    } catch {}
  }

  function evacuateVault() public {
    address actor = msg.sender;
    if (actor != GUARDIAN && actor != OWNER) return;
    if (psm.evacuated()) return;

    _prank(actor);
    try psm.evacuateVault() {
      ghost_evacuateCount++;
    } catch {}
  }

  function claimRefund() public {
    if (!psm.evacuated()) return;

    address actor = msg.sender;
    if (psm.scheduledWithdrawalAmount(actor) == 0) return;

    uint256 scheduled = psm.scheduledWithdrawalAmount(actor);

    _prank(actor);
    try psm.claimRefund() {
      ghost_totalRefundedMAI += scheduled;
      ghost_refundCount++;
    } catch {}
  }

  function forceSettle(
    address target
  ) public {
    if (msg.sender != OWNER) return;
    if (!psm.evacuated()) return;
    if (block.timestamp < psm.evacuationTime() + psm.SETTLEMENT_TIMEOUT()) return;
    if (psm.scheduledWithdrawalAmount(target) == 0) return;

    uint256 scheduled = psm.scheduledWithdrawalAmount(target);

    _prank(OWNER);
    try psm.forceSettle(target) {
      ghost_totalRefundedMAI += scheduled;
      ghost_refundCount++;
    } catch {}
  }

  function sweep(
    uint256 amount
  ) public {
    if (psm.evacuated()) return;
    if (msg.sender != OWNER) return;

    amount = _clamp(amount, 1 * 10 ** 6, 50_000 * 10 ** 6);
    usdc.mint(address(psm), amount);

    _prank(OWNER);
    try psm.sweep() {
      ghost_totalSwept += amount;
    } catch {}
  }

  function ownerWithdrawMAI() public {
    if (msg.sender != OWNER) return;
    _prank(OWNER);
    try psm.withdrawMAI() {} catch {}
  }

  function ownerTransferMAI(
    uint256 amount
  ) public {
    if (msg.sender != OWNER) return;

    uint256 maiBalance = mai.balanceOf(address(psm));
    if (maiBalance == 0) return;
    amount = _clamp(amount, 1, maiBalance);

    _prank(OWNER);
    try psm.transferToken(address(mai), OWNER, amount) {} catch {}
  }

  // ═══════════════════════════════════════════════════════════
  //  Properties
  // ═══════════════════════════════════════════════════════════

  function echidna_queued_never_exceeds_stable() public view returns (bool) {
    return psm.totalStableLiquidity() >= psm.totalQueuedLiquidity();
  }

  function echidna_backing_sufficient() public view returns (bool) {
    uint256 vaultBacking = vault.balanceOf(address(psm));
    uint256 idleUsdc = usdc.balanceOf(address(psm));
    return (vaultBacking + idleUsdc) >= psm.totalStableLiquidity();
  }

  function echidna_evacuated_mai_covers_refunds() public view returns (bool) {
    if (!psm.evacuated()) return true;
    if (psm.totalQueuedMAI() == 0) return true;
    return mai.balanceOf(address(psm)) >= psm.totalQueuedMAI();
  }

  function echidna_evacuation_implies_stopped() public view returns (bool) {
    if (psm.evacuated()) {
      return psm.stopped();
    }
    return true;
  }

  function echidna_totalQueuedMAI_bounded() public view returns (bool) {
    return psm.totalQueuedMAI() <= 100_000_000 * 10 ** 18;
  }

  function echidna_available_survives_fees() public view returns (bool) {
    uint256 available = psm.availableForWithdrawal();
    if (available == 0) return true;
    uint256 fee = psm.calculateFee(available, false);
    return available > fee;
  }

  // ═══════════════════════════════════════════════════════════
  //  Helpers
  // ═══════════════════════════════════════════════════════════

  function _clamp(
    uint256 value,
    uint256 low,
    uint256 high
  ) internal pure returns (uint256) {
    if (value < low) return low;
    if (value > high) return high;
    return value;
  }
}
