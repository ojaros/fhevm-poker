import { ethers } from "hardhat";
import hre from "hardhat";

import { getTokensFromFaucet, deployPokerFixture } from "./Poker.fixture";
import { shouldBehaveLikePoker } from "./Poker.behavior";
import { Signers } from "../types";
import { createFheInstance } from "../../utils/instance";
import { waitForBlock } from "../../utils/block";

describe("Unit tests", function () {
    beforeEach(async function () {
        this.signers = {} as Signers;

        // get tokens from faucet if we're on localfhenix and don't have a balance
        await getTokensFromFaucet();

        // deploy test contract
        const { poker, address } = await deployPokerFixture();
        this.poker = poker;

        // initiate fhevmjs
        this.instance = await createFheInstance(hre, address);

        // set admin account/signer
        const signers = await ethers.getSigners();
        this.signers.admin = signers[0];
        this.signers.player1 = signers[0];
        this.signers.player2 = signers[1];

        // wait for deployment block to finish
        await waitForBlock(hre);
    });

    describe("Poker", function () {
        shouldBehaveLikePoker();
    });

});