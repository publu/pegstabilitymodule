// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {console} from 'forge-std/console.sol';
import {Test} from 'forge-std/Test.sol';

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';

import {USDCVaultDDW} from 'contracts/USDCVaultDDW.sol';

contract MetisIntegrationBase is Test {
  uint256 internal constant _FORK_BLOCK = 20_694_285;

  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');
  IERC20 internal _usdcToken = IERC20(0xEA32A96608495e54156Ae48931A7c20f0dcc1a21);
  IERC20 internal _maiToken = IERC20(0xdFA46478F9e5EA86d57387849598dbFB2e964b02);

  USDCVaultDDW internal _psm;

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl('metis'), _FORK_BLOCK);
    vm.startPrank(_owner);
    deal(address(_usdcToken), _owner, 100_000_000 * 10 ** 6);
    deal(address(_usdcToken), _user, 100_000_000 * 10 ** 6);
    _psm = new USDCVaultDDW();
    deal(address(_maiToken), address(_psm), 100_000_000 * 10 ** 18);
    // console.log('BeefyVaultWithdrawal address:', address(psm));
    // console.log('owner:', psm.owner());
    // console.log('prank:', _owner);
    _psm.initialize(100, 100, address(_maiToken), address(_usdcToken));
  }
}
