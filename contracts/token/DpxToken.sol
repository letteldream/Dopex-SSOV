// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract DpxToken is ERC20PresetMinterPauser {
    constructor() ERC20PresetMinterPauser("Dopex Governance Token", "DPX") {
        revokeRole(PAUSER_ROLE, msg.sender);
        _mint(msg.sender, 500000 ether);
    }
}
