// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';

import {BeefyVaultPSMPoly} from 'contracts/BeefyVaultDDWPoly.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {console} from 'forge-std/console.sol';

contract BeefyIntegrationPoly is Test {
  uint256 internal constant _FORK_BLOCK = 8_420_622;

  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');
  address internal _beefyWhale = 0xcFae084c26582c38c2e9Bfb92Da7d54f842A7A5f;

  IERC20 internal _mooToken = IERC20(0x86F371838A321F92237DaD7b8DA5c76d2c084934);

  IERC20 internal _usdbcToken = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
  IERC20 internal _maiToken = IERC20(0xa3Fa99A148fA48D14Ed51d610c367C61876997F1);

  IBeefy internal _beefyVault;
  BeefyVaultPSMPoly internal _psm;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('base'), _FORK_BLOCK);
    vm.startPrank(_owner);
    deal(address(_usdbcToken), _owner, 100_000_000 * 10 ** 6);
    deal(address(_usdbcToken), _user, 100_000_000 * 10 ** 6);
    _beefyVault = IBeefy(address(_mooToken));
    _psm = new BeefyVaultPSMPoly();
    deal(address(_maiToken), address(_psm), 100_000_000 * 10 ** 18);
    // console.log('BeefyVaultWithdrawal address:', address(psm));
    // console.log('owner:', psm.owner());
    // console.log('prank:', _owner);
    _psm.initialize(address(_mooToken), 100, 100);
    _psm.approveBeef();
  }
}
