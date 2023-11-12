// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "lib/forge-std/src/Test.sol";
// import "ds-test/test.sol";
import "fhevm/lib/TFHE.sol";
import "forge-std/console.sol";
import {Dealer} from "../contracts/Dealer.sol";

contract DealerTest is Test {
    Dealer dealer;

    address admin = address(this);

    function setUp() public {
        dealer = new Dealer();
    }

    function testDealCard() public {
        dealer.setDeal(9);
    }

}