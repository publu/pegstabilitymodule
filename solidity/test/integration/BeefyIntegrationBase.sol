// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';

import {BeefyVaultPSM} from 'contracts/BeefyVaultDDW.sol';
import {IBeefy} from '../../interfaces/IBeefy.sol';
import {console} from 'forge-std/console.sol';

contract BeefyIntegrationBase is Test {
  uint256 internal constant _FORK_BLOCK = 8_420_622;

  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');
  address internal _beefyWhale = 0x008a74d96d799b0fcfae8462BfFF8C37C7ccc611;
  IERC20 internal _mooToken = IERC20(0xD7803d3Bf95517D204CFc6211678cAb223aC4c48);
  IERC20 internal _usdbcToken = IERC20(0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA);
  IERC20 internal _maiToken = IERC20(0xbf1aeA8670D2528E08334083616dD9C5F3B087aE);

  IBeefy internal _beefyVault;
  BeefyVaultPSM internal _psm;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('base'), _FORK_BLOCK);
    vm.startPrank(_owner);
    deal(address(_usdbcToken), _owner, 100_000_000 * 10 ** 6);
    deal(address(_usdbcToken), _user, 100_000_000 * 10 ** 6);
    _beefyVault = IBeefy(address(_mooToken));
    _psm = new BeefyVaultPSM();
    deal(address(_maiToken), address(_psm), 100_000_000 * 10 ** 18);
    // console.log('BeefyVaultWithdrawal address:', address(psm));
    // console.log('owner:', psm.owner());
    // console.log('prank:', _owner);
    _psm.initialize(address(_mooToken), 100, 100);
    _psm.approveBeef();
  }
}
