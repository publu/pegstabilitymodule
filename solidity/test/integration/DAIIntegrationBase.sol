// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {Test} from 'forge-std/Test.sol';

import {DAIVaultPSM} from 'contracts/DAIVaultDW.sol';
import {IL2DSR} from 'interfaces/IL2DSR.sol';
import {console} from 'forge-std/console.sol';

contract DAIIntegrationBase is Test {
  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');
  IERC20 internal _WDAIToken = IERC20(0x023617bAbEd6CeF5Da825BEa8363A5a9862E120F);
  IERC20 internal _maiToken = IERC20(0xf3B001D64C656e30a62fbaacA003B1336b4ce12A);
  IL2DSR internal _l2dsr = IL2DSR(0x30C724216b890c034e0a1C299Ae641565f85355e);

  DAIVaultPSM internal _psm;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('linea'));
    vm.startPrank(_owner);
    deal(address(_WDAIToken), _owner, 100_000_000 ether);
    deal(address(_WDAIToken), _user, 100_000_000 ether);
    _psm = new DAIVaultPSM();
    deal(address(_maiToken), address(_psm), 100_000_000 ether);
    // console.log('BeefyVaultWithdrawal address:', address(psm));
    // console.log('owner:', psm.owner());
    // console.log('prank:', _owner);
    _psm.initialize(address(_l2dsr), 100, 100);
    _psm.approveGem();
  }
}
