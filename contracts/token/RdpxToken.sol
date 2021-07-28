// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract RdpxToken is ERC20PresetMinterPauser {
    constructor() ERC20PresetMinterPauser("Dopex Rebate Token", "rDPX") {
        revokeRole(PAUSER_ROLE, msg.sender);
        // Initial supply set to 2.25 million
        // Breakdown:
        // 2 million for farming rewards
        // 200k for airdrops
        // 50k for initial uniswap liquidity
        _mint(msg.sender, 2250000 ether);
    }
}
