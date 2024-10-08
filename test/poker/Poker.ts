import { ethers } from "hardhat";
import hre from "hardhat";

import { getTokensFromFaucet, deployPokerFixture } from "./Poker.fixture";
import { shouldBehaveLikePoker } from "./Poker.behavior";
import { Signers } from "../types";
import { createFheInstance } from "../../utils/instance";
import { waitForBlock } from "../../utils/block";

describe("Unit tests", function () {
    beforeEach(async function () {
        this.timeout(60000); // Set timeout to 60 seconds
        this.signers = {} as Signers;

        // get tokens from faucet if we're on localfhenix and don't have a balance
        await getTokensFromFaucet();

        // deploy test contract
        const { poker, pokerChip, address } = await deployPokerFixture();
        this.poker = poker;
        this.pokerChip = pokerChip


        // initiate fhevmjs
        this.instance = await createFheInstance(hre, address);

        // set admin account/signer
        const signers = await ethers.getSigners();
        this.signers.admin = signers[0];
        this.signers.player1 = signers[1];
        this.signers.player2 = signers[2];
        this.signers.player3 = signers[3];
        this.signers.player4 = signers[4];
        this.signers.player5 = signers[5];
        this.signers.player6 = signers[6];

        // wait for deployment block to finish
        await waitForBlock(hre);
    });

    describe("Poker", function () {
        shouldBehaveLikePoker();
    });

});