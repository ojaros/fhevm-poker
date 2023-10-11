import { expect } from "chai";
import hre from "hardhat";
import { ethers } from "hardhat";

import { waitForBlock } from "../../utils/block";
import { Poker } from "../../types";


export function shouldBehaveLikePoker(): void {

    it("should correctly initialize the Poker contract", async function () {
        expect(await this.poker.owner()).to.equal(this.signers.admin.address);
    });

    describe("Table Initialization", function () {
        it("should initialize a table", async function () {
            const _buyInAmount = 1000;
            const _maxPlayers = 5;
            const _bigBlind = 50;
            const _token = ethers.ZeroAddress; // Using Zero Address for this example

            await this.poker.connect(this.signers.admin).initializeTable(_buyInAmount, _maxPlayers, _bigBlind, _token);

            // TODO: Implement a method in the smart contract to get table details by tableId
            const table = await this.poker.tables(0); 
            expect(table.buyInAmount).to.equal(_buyInAmount);
        });
    });

    describe("Player operations", function () {
        it("should allow a player to buy in", async function () {
            // Assuming a basic ERC20 contract is already deployed and referenced as this.token
            const amount = 1000;

            // Approving the tokens for the contract to spend on behalf of the player
            await this.token.connect(this.signers.player1).approve(this.poker.address, amount);
            await this.poker.connect(this.signers.player1).buyIn(0, amount);

            const playerBalance = await this.poker.playerChipsRemaining(this.signers.player1.address, 0);
            expect(playerBalance).to.equal(amount);
        });

        it("should allow a player to withdraw chips", async function () {
            const amount = 500;
            await this.poker.connect(this.signers.player1).withdrawChips(0, amount);
            const playerBalanceAfterWithdraw = await this.poker.playerChipsRemaining(this.signers.player1.address, 0);
            expect(playerBalanceAfterWithdraw).to.equal(500); // assuming they had 1000 before
        });

        it("should allow cards to be dealt", async function () {
            // Assuming at least 2 players have bought in
            await this.poker.dealCards(0);
            // Further assertions can be added based on events or any other data changes
        });

        it("should allow players to play a hand", async function () {
            // Player1 decides to raise
            await this.poker.connect(this.signers.player1).playHand(0, 1, 50);
            // Add checks based on game state, chips, or emitted events
        });
    });
    

};
