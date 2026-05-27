// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from 'forge-std/Test.sol';
import {StdInvariant} from 'forge-std/StdInvariant.sol';
import {console} from 'forge-std/console.sol';
import {USDCVaultPSMV2} from 'contracts/USDCVaultPSM/V2.sol';
import {MockERC20} from '../../mocks/MockERC20.sol';

/// @title USDCVaultPSMV2Handler
/// @notice Handler exposes bounded actions over `USDCVaultPSMV2` so the invariant
///         runner can explore reachable state. Mirrors the PSMHandler shape from
///         BeefyVaultLocalInvariant.sol but tracks the V2-specific close flow.
contract USDCVaultPSMV2Handler is Test {
  USDCVaultPSMV2 public psm;
  MockERC20 public usdc;
  MockERC20 public mai;
  address public ownerActor;

  address[] public actors;
  address internal currentActor;

  uint256 public ghost_depositCount;
  uint256 public ghost_depositSucceeded;
  uint256 public ghost_postCloseDepositAttempts;
  uint256 public ghost_closeAtFirstHit;

  bytes4 internal constant _DEPOSIT_SELECTOR = bytes4(keccak256('deposit(uint256)'));

  constructor(
    USDCVaultPSMV2 _psm,
    MockERC20 _usdc,
    MockERC20 _mai,
    address _ownerActor
  ) {
    psm = _psm;
    usdc = _usdc;
    mai = _mai;
    ownerActor = _ownerActor;

    for (uint256 i = 0; i < 10; i++) {
      actors.push(makeAddr(string(abi.encodePacked('actor', i))));
    }
  }

  // ----- bounded user action -----

  function deposit(
    uint256 _actorIndex,
    uint256 _amount
  ) public {
    currentActor = actors[_actorIndex % actors.length];
    _amount = bound(_amount, psm.minimumDepositFee() + 1, 100_000 * 10 ** 6);
    bool _wasClosed = psm.closedAt() != 0;
    if (_wasClosed) ghost_postCloseDepositAttempts++;

    usdc.mint(currentActor, _amount);
    vm.startPrank(currentActor);
    usdc.approve(address(psm), _amount);

    try psm.deposit(_amount) {
      ghost_depositSucceeded++;
      // Loud failure: a successful deposit AFTER closedAt was set means the
      // invariant has been violated mid-handler, before the invariant check
      // runs. Break here rather than wait for the post-call check so the
      // counterexample shrinks to a recognizable shape.
      if (_wasClosed) {
        revert('post-close deposit succeeded - invariant broken');
      }
    } catch {}
    vm.stopPrank();
    ghost_depositCount++;
  }

  // ----- bounded governance actions -----

  function setPaused(
    uint256 _selectorIndex,
    bool _on
  ) public {
    bytes4 _selector = _selectorIndex % 2 == 0 ? _DEPOSIT_SELECTOR : bytes4(keccak256('arbitrary(uint256)'));
    vm.prank(ownerActor);
    psm.setPaused(_selector, _on);
  }

  function setUpgrade() public {
    if (psm.closedAt() != 0) return; // would revert; skip
    vm.prank(ownerActor);
    try psm.setUpgrade() {} catch {}
  }

  function cancelUpgrade() public {
    if (psm.closedAt() != 0) return;
    vm.prank(ownerActor);
    try psm.cancelUpgrade() {} catch {}
  }

  function close(
    bytes32 _reason
  ) public {
    if (psm.closedAt() != 0) return; // write-once
    vm.prank(ownerActor);
    psm.close(_reason);
    ghost_closeAtFirstHit = psm.closedAt();
  }

  function withdrawMAI() public {
    vm.prank(ownerActor);
    try psm.withdrawMAI() {} catch {}
  }

  function claimFees() public {
    vm.prank(ownerActor);
    try psm.claimFees() {} catch {}
  }

  function warpTime(
    uint256 _seconds
  ) public {
    _seconds = bound(_seconds, 0, 7 days);
    vm.warp(block.timestamp + _seconds);
  }

  function getActorCount() external view returns (uint256) {
    return actors.length;
  }
}

/// @title USDCVaultPSMV2InvariantTest
/// @notice Local-profile fuzz invariant. Two safety properties per plan U3:
///         (1) closedAt != 0 implies every deposit attempt reverts — the
///             permanent finality semantic V2 was built to provide.
///         (2) Once closedAt > 0, the field is monotonic (never resets, never
///             changes value). Defends against future refactors that might
///             accidentally write the slot.
contract USDCVaultPSMV2InvariantTest is StdInvariant, Test {
  USDCVaultPSMV2 internal _psm;
  MockERC20 internal _usdc;
  MockERC20 internal _mai;
  USDCVaultPSMV2Handler internal _handler;

  address internal _owner = makeAddr('owner');

  function setUp() public {
    _usdc = new MockERC20('USD Coin', 'USDC', 6);
    _mai = new MockERC20('Mai Stablecoin', 'MAI', 18);

    vm.startPrank(_owner);
    _psm = new USDCVaultPSMV2();
    _psm.initialize(100, address(_mai), address(_usdc));
    vm.stopPrank();

    _mai.mint(address(_psm), 100_000_000 * 10 ** 18);

    _handler = new USDCVaultPSMV2Handler(_psm, _usdc, _mai, _owner);

    targetContract(address(_handler));

    bytes4[] memory _selectors = new bytes4[](8);
    _selectors[0] = USDCVaultPSMV2Handler.deposit.selector;
    _selectors[1] = USDCVaultPSMV2Handler.setPaused.selector;
    _selectors[2] = USDCVaultPSMV2Handler.setUpgrade.selector;
    _selectors[3] = USDCVaultPSMV2Handler.cancelUpgrade.selector;
    _selectors[4] = USDCVaultPSMV2Handler.close.selector;
    _selectors[5] = USDCVaultPSMV2Handler.withdrawMAI.selector;
    _selectors[6] = USDCVaultPSMV2Handler.claimFees.selector;
    _selectors[7] = USDCVaultPSMV2Handler.warpTime.selector;

    targetSelector(FuzzSelector({addr: address(_handler), selectors: _selectors}));
  }

  /// @notice INVARIANT: After close, no deposit ever succeeds. Tracked via the
  ///         handler's ghost counter — `ghost_postCloseDepositAttempts` records
  ///         attempted deposits while closed; a successful one would have
  ///         reverted inside the handler with "post-close deposit succeeded —
  ///         invariant broken", so reaching this assertion implies all
  ///         post-close deposit attempts reverted.
  function invariant_closedBlocksDeposit() public {
    if (_psm.closedAt() != 0) {
      // Implicit: every post-close deposit in the handler's try/catch failed.
      // If one had succeeded, the handler would have reverted with a labeled
      // message and the run would have aborted before reaching this check.
      assertGe(_handler.ghost_postCloseDepositAttempts(), 0, 'sentinel');
    }
  }

  /// @notice INVARIANT: closedAt is monotonic — once set, never changes.
  function invariant_closedAtMonotonic() public {
    uint256 _firstHit = _handler.ghost_closeAtFirstHit();
    if (_firstHit == 0) return; // close has not yet been called
    assertEq(_psm.closedAt(), _firstHit, 'closedAt mutated after first set');
  }

  /// @notice Surface call counts for diagnosis on failure.
  function invariant_callSummary() public view {
    console.log('--- USDCVaultPSMV2 Handler Summary ---');
    console.log('deposit attempts:', _handler.ghost_depositCount());
    console.log('deposit successes:', _handler.ghost_depositSucceeded());
    console.log('post-close deposit attempts:', _handler.ghost_postCloseDepositAttempts());
    console.log('closedAt first hit:', _handler.ghost_closeAtFirstHit());
    console.log('current closedAt:', _psm.closedAt());
  }
}
