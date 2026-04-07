// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';

import {BeefyVaultPSMV2} from 'contracts/BeefyVaultPSM/V2.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {console} from 'forge-std/console.sol';

/// @title MainnetIntegrationBase
/// @notice Base contract for Ethereum Mainnet fork tests
/// @dev Override _mooTokenAddress() to test with a different Beefy vault
contract MainnetIntegrationBase is Test {
  // Use latest block for public RPCs - set specific block for production testing
  // uint256 internal constant _FORK_BLOCK = 21_350_000;

  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');

  // Mainnet addresses
  IERC20 internal _mooToken;
  IERC20 internal _usdcToken = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC
  IERC20 internal _maiToken = IERC20(0x8D6CeBD76f18E1558D4DB88138e2DeFB3909fAD6); // MAI on mainnet

  IBeefy internal _beefyVault;
  BeefyVaultPSMV2 internal _psm;

  /// @notice Override to test with a different Beefy vault
  function _mooTokenAddress() internal pure virtual returns (address) {
    return 0x562Ea6FfFD1293b9433E7b81A2682C31892ea013; // Moo Morpho Smokehouse USDC (default)
  }

  // MAI whale address (owner with large balance)
  address internal constant _MAI_WHALE = 0x3182E6856c3B59C39114416075770Ec9DC9Ff436;

  /// @notice Helper to deal tokens by writing directly to storage or transferring from whale
  /// @dev USDC uses slot 9 for balances, MAI uses whale transfer due to non-standard storage
  /// @dev This function handles prank context - it stops any active prank, does the deal, and caller must restart prank if needed
  function _dealToken(
    address token,
    address to,
    uint256 amount
  ) internal {
    if (token == address(_maiToken)) {
      // MAI has non-standard storage layout, transfer from whale instead
      // Stop any active prank before starting a new one
      vm.stopPrank();
      vm.prank(_MAI_WHALE);
      IERC20(token).transfer(to, amount);
    } else {
      // USDC uses slot 9 for balances (vm.store doesn't need prank context)
      uint256 slot;
      if (token == address(_usdcToken)) {
        slot = 9; // USDC balance slot
      } else {
        slot = 0; // Standard ERC20 balance slot
      }
      bytes32 storageSlot = keccak256(abi.encode(to, slot));
      vm.store(token, storageSlot, bytes32(amount));
    }
  }

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl('mainnet'));

    _mooToken = IERC20(_mooTokenAddress());

    // Deal USDC tokens for testing using direct storage writes (no prank needed)
    _dealToken(address(_usdcToken), _owner, 100_000_000 * 10 ** 6);
    _dealToken(address(_usdcToken), _user, 100_000_000 * 10 ** 6);

    vm.startPrank(_owner);
    _beefyVault = IBeefy(address(_mooToken));
    _psm = new BeefyVaultPSMV2();
    vm.stopPrank();

    // Fund PSM with MAI for deposits (uses whale transfer, needs its own prank)
    // Note: Whale has ~7M MAI, so we use 5M to leave some buffer
    _dealToken(address(_maiToken), address(_psm), 5_000_000 * 10 ** 18);

    vm.startPrank(_owner);
    // Initialize with 1% deposit and withdrawal fees, mainnet MAI address
    _psm.initialize(address(_mooToken), 100, 100, address(_maiToken));
    _psm.approveBeef();
  }
}
