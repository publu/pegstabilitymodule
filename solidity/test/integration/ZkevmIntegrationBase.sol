// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'isolmate/interfaces/tokens/IERC20.sol';
import {USDCVaultPSM} from 'contracts/USDCVaultPSM/V1.sol';

contract ZkevmIntegrationBase is Test {
  address internal _user = makeAddr('user');
  address internal _owner = makeAddr('owner');
  IERC20 internal _usdcToken = IERC20(0x37eAA0eF3549a5Bb7D431be78a3D99BD360d19e5);
  IERC20 internal _maiToken = IERC20(0x615B25500403Eb688Be49221b303084D9Cf0E5B4);

  USDCVaultPSM internal _psm;

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl('zkevm'));
    vm.startPrank(_owner);
    deal(address(_usdcToken), _owner, 100_000_000 * 10 ** 6);
    deal(address(_usdcToken), _user, 100_000_000 * 10 ** 6);
    _psm = new USDCVaultPSM();
    deal(address(_maiToken), address(_psm), 100_000_000 * 10 ** 18);
    _psm.initialize(100, address(_maiToken), address(_usdcToken));
  }
}
