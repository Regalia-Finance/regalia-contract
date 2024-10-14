// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import "../src/PrincipleToken.sol";
import "../src/mocks/MockERC721.sol";
import "../src/mocks/MockERC20.sol";
import "../src/RoyaltyToken.sol";

contract RegaliaScript is Script {
    PrincipleToken principleToken;
    RoyaltyToken royaltyToken;
    MockERC721 mockERC721;
    MockERC20 mockERC20;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        mockERC721 = new MockERC721();
        console.log("mockERC721 deployed to: ", address(mockERC721));
        mockERC20 = new MockERC20();
        console.log("mockERC20 deployed to: ", address(mockERC20));
        royaltyToken = new RoyaltyToken();
        console.log("RoyaltyToken implementation deployed to: ", address(royaltyToken));
        principleToken = new PrincipleToken(address(royaltyToken), 10);
        console.log("PrincipleToken deployed to: ", address(principleToken));

        vm.stopBroadcast();
    }
}
