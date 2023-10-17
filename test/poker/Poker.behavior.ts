import { expect } from "chai";
import hre from "hardhat";
import { ethers } from "hardhat";

import { waitForBlock } from "../../utils/block";

// const emittedEvents: any = [];
// const saveEvents = async (tx: any) => {
//     const receipt = await tx.wait()
//     receipt.events.forEach((ev: any) => {
//         if (ev.event) {
//             emittedEvents.push({
//                 name: ev.event,
//                 args: ev.args
//             });
//         }
//     });
//     console.log(`emittedEvents: `, emittedEvents);
// }

enum PlayerAction {
    Call,
    Raise,
    Check,
    Fold
}

export function shouldBehaveLikePoker(): void {


    describe("Table Initialization and Player Operations", function () {
        beforeEach(async function () {
            // Set up initial state here. 
            const _buyInAmount = 1000;
            const _maxPlayers = 5;
            const _bigBlind = 10;
            const _token = this.pokerChip.target;
            await this.poker.connect(this.signers.admin).initializeTable(_buyInAmount, _maxPlayers, _bigBlind, _token);
            await waitForBlock(hre);

            const amountToTransferAndApprove = 10000;

            const adminBalance = await this.pokerChip.balanceOf(this.signers.admin.address);
            console.log('Admin balance: ', adminBalance.toString());

            // Transfer tokens from admin to player1 and player2
            await this.pokerChip.connect(this.signers.admin).transfer(this.signers.player1.address, amountToTransferAndApprove);
            await this.pokerChip.connect(this.signers.admin).transfer(this.signers.player2.address, amountToTransferAndApprove);
            await this.pokerChip.connect(this.signers.admin).transfer(this.signers.player3.address, amountToTransferAndApprove);
            await this.pokerChip.connect(this.signers.admin).transfer(this.signers.player4.address, amountToTransferAndApprove);
            await waitForBlock(hre);
            
            const player1Balance = await this.pokerChip.balanceOf(this.signers.player1.address);
            const player2Balance = await this.pokerChip.balanceOf(this.signers.player2.address);
            console.log("player 1 bal: ", player1Balance)
            expect(player1Balance, `Expected playerBalance to be ${amountToTransferAndApprove} but got ${player1Balance}`).to.equal(amountToTransferAndApprove);
            expect(player2Balance, `Expected playerBalance to be ${amountToTransferAndApprove} but got ${player2Balance}`).to.equal(amountToTransferAndApprove);

            // Approve the poker contract to spend tokens on behalf of player1 and player2
            await this.pokerChip.connect(this.signers.player1).approve(this.poker.target, amountToTransferAndApprove);
            await this.pokerChip.connect(this.signers.player2).approve(this.poker.target, amountToTransferAndApprove);
            await this.pokerChip.connect(this.signers.player3).approve(this.poker.target, amountToTransferAndApprove);
            await this.pokerChip.connect(this.signers.player4).approve(this.poker.target, amountToTransferAndApprove);
            await waitForBlock(hre);

            // Check the approved amount for the poker contract on behalf of player1 and player2
            expect(await this.pokerChip.allowance(this.signers.player1.address, this.poker.target)).to.equal(amountToTransferAndApprove);
            expect(await this.pokerChip.allowance(this.signers.player2.address, this.poker.target)).to.equal(amountToTransferAndApprove);
        });

        it("should initialize a table", async function () {
            const table = await this.poker.tables(0); 
            await waitForBlock(hre)
            expect(table.buyInAmount, `Expected value to be ${1000} but got ${table.buyInAmount}`).to.equal(1000);
        });

        it("should allow a player to buy in", async function () {
            // Assuming a basic ERC20 contract is already deployed and referenced as this.pokerChip
            const buyInAmount = 1000;
            
            const playerTokens = await this.pokerChip.balanceOf(this.signers.player1.address);
            console.log("Player tokens : ", playerTokens);
            expect(playerTokens, `Expected playerBalance to be greater than ${buyInAmount} but got ${playerTokens}`).to.be.greaterThan(buyInAmount);


            await this.poker.connect(this.signers.player1).buyIn(0, buyInAmount);
            await waitForBlock(hre);

            const playerBalance = await this.poker.playerChipsRemaining(this.signers.player1.address, 0);
            expect(playerBalance.toString(), `Expected playerBalance to be ${buyInAmount} but got ${playerBalance}`).to.equal(buyInAmount.toString());
        });

        it("should allow a player to withdraw chips", async function () {
            const amount = 100;
            await this.poker.connect(this.signers.player1).buyIn(0, 1000);  // Assuming the player needs to buy in first
            await waitForBlock(hre);

            await this.poker.connect(this.signers.player1).withdrawChips(0, amount);
            await waitForBlock(hre);

            const playerBalanceAfterWithdraw = await this.poker.playerChipsRemaining(this.signers.player1.address, 0);
            expect(playerBalanceAfterWithdraw.toString()).to.equal("900");
        });

        it("should allow cards to be dealt", async function () {
            const buyInAmount = 1000;
            
            const player1Tokens = await this.pokerChip.balanceOf(this.signers.player1.address);
            const player2Tokens = await this.pokerChip.balanceOf(this.signers.player2.address);
            expect(player1Tokens, `Expected playerBalance to be greater than ${buyInAmount} but got ${player1Tokens}`).to.be.greaterThan(buyInAmount);
            expect(player2Tokens, `Expected playerBalance to be greater than ${buyInAmount} but got ${player2Tokens}`).to.be.greaterThan(buyInAmount);

            await this.poker.connect(this.signers.player1).buyIn(0, buyInAmount);
            await this.poker.connect(this.signers.player2).buyIn(0, buyInAmount);
            await waitForBlock(hre);

            const tx = await this.poker.connect(this.signers.admin).dealCards(0);
            await waitForBlock(hre)

            const debugPlayerCardsLogs = await this.poker.queryFilter(this.poker.filters.DebugPlayerCards());
            console.log("debugPlayerCardsLogs", debugPlayerCardsLogs)
            
            const playerCardsDealtLogs = await this.poker.queryFilter(this.poker.filters.PlayerCardsDealt());
            console.log("playerCardsDealtLogs", playerCardsDealtLogs)

            if (playerCardsDealtLogs.length > 0) {
                console.log("\nPlayer Cards Dealt Event Details:");
                console.log(playerCardsDealtLogs)
            } else {
                console.log("No PlayerCardsDealt events found.");
            }
            expect(playerCardsDealtLogs).to.not.be.empty;  // Ensure the event was emitted 

            // Checking the encrypted cards for player1 and player2
            const tableId = 0;
            const totalHands = (await this.poker.tables(tableId)).totalHands;
            console.log(`Total hands played till now on tableId ${tableId}: ${totalHands}`);

            const player1EncryptedCards = await this.poker.playerCardsEncryptedDuringHand(this.signers.player1.address, tableId, totalHands);
            const player2EncryptedCards = await this.poker.playerCardsEncryptedDuringHand(this.signers.player2.address, tableId, totalHands);

            console.log("PLAYER 1 Encrypted cards: ", player1EncryptedCards)
            console.log("PLAYER 2 Encrypted cards: ", player2EncryptedCards)

            expect(player1EncryptedCards.card1Encrypted.toString()).to.not.be.empty; // Check player1's first card is present
            expect(player1EncryptedCards.card2Encrypted.toString()).to.not.be.empty; // Check player1's second card is present
            expect(player2EncryptedCards.card1Encrypted.toString()).to.not.be.empty; // Check player2's first card is present
            expect(player2EncryptedCards.card2Encrypted.toString()).to.not.be.empty; // Check player2's second card is present
        });



        it("should simulate preflop raise logic", async function() {
            const buyInAmount = 1000;
            const initialRaiseAmount = 30;
            const tableId = 0; // based on the above code
    
            // Players buy in
            await this.poker.connect(this.signers.player1).buyIn(0, buyInAmount);
            await this.poker.connect(this.signers.player2).buyIn(0, buyInAmount);
            await this.poker.connect(this.signers.player3).buyIn(0, buyInAmount);
            await this.poker.connect(this.signers.player4).buyIn(0, buyInAmount);
            await waitForBlock(hre);

            // Dealer deals initial cards to each player
            await this.poker.dealCards(0);
            await waitForBlock(hre);

            const table = await this.poker.tables(tableId);
            console.log("TABLE STATE AFTER DEAL: ", table);

            const totalHands = (await this.poker.tables(tableId)).totalHands;
            const player1EncryptedCards = await this.poker.playerCardsEncryptedDuringHand(this.signers.player1.address, tableId, totalHands);
            const player2EncryptedCards = await this.poker.playerCardsEncryptedDuringHand(this.signers.player2.address, tableId, totalHands);
            const player3EncryptedCards = await this.poker.playerCardsEncryptedDuringHand(this.signers.player3.address, tableId, totalHands);
            const player4EncryptedCards = await this.poker.playerCardsEncryptedDuringHand(this.signers.player4.address, tableId, totalHands);

            console.log("PLAYER 1 Encrypted cards: ", player1EncryptedCards)
            console.log("PLAYER 2 Encrypted cards: ", player2EncryptedCards)
            console.log("PLAYER 3 Encrypted cards: ", player3EncryptedCards)
            console.log("PLAYER 4 Encrypted cards: ", player4EncryptedCards)

            const round = await this.poker.rounds(tableId, 0)
            console.log("ROUND STATE AFTER DEALING CARDS: ", round)
            console.log("ALL PLAYERS : ", await this.poker.getRoundPlayersInRound(tableId, totalHands))
            console.log("CURRENT PLAYERS TURN : ", round.turn)
            console.log("CHIPS PLAYERS HAVE BET ARRAY : ", await this.poker.getChipsBetArray(tableId, totalHands))
            
            
            // Betting round 1 (pre-flop)
            await this.poker.connect(this.signers.player4).playHand(0, PlayerAction.Raise, initialRaiseAmount);  // Player4 raises
            await waitForBlock(hre);

            await this.poker.connect(this.signers.player1).playHand(0, PlayerAction.Call, 0);  // Player1 calls
            await waitForBlock(hre);

            // await this.poker.connect(this.signers.player2).playHand(0, PlayerAction.Fold, 0);  // Player2 folds
            // await waitForBlock(hre);

            // await this.poker.connect(this.signers.player3).playHand(0, PlayerAction.Call, 0);  // Player3 calls
            // await waitForBlock(hre);

            console.log("CHIPS PLAYERS HAVE BET AFTER PREFLOP : ", await this.poker.getChipsBetArray(tableId, totalHands))
            console.log("PLAYERS IN ROUND STILL : ", await this.poker.getRoundPlayersInRound(tableId, totalHands))

            // // Assuming dealCommunityCards deals 3 cards on the flop
            // await this.poker.dealCommunityCards(0);
            // await waitForBlock(hre);
    
            // // Betting round 2 (post-flop)
            // await this.poker.connect(this.signers.player1).playHand(0, PlayerAction.Check, 0);  // Player1 checks
            // await this.poker.connect(this.signers.player2).playHand(0, PlayerAction.Raise, initialRaiseAmount);  // Player2 raises
            // await this.poker.connect(this.signers.player1).playHand(0, PlayerAction.Call, 0);  // Player1 calls
    
            // // Assuming dealCommunityCards deals 1 card on the turn
            // await this.poker.dealCommunityCards(0);
            // await waitForBlock(hre);
    
            // // Betting round 3 (post-turn)
            // await this.poker.connect(this.signers.player1).playHand(0, PlayerAction.Raise, initialRaiseAmount);  // Player1 raises
            // await this.poker.connect(this.signers.player2).playHand(0, PlayerAction.Call, 0);  // Player2 calls
    
            // // Assuming dealCommunityCards deals 1 card on the river
            // await this.poker.dealCommunityCards(0);
            // await waitForBlock(hre);
    
            // // Betting round 4 (post-river)
            // await this.poker.connect(this.signers.player1).playHand(0, PlayerAction.Check, 0);  // Player1 checks
            // await this.poker.connect(this.signers.player2).playHand(0, PlayerAction.Check, 0);  // Player2 checks
    
            // // Here you would typically have some function to determine the winner and distribute the pot.
            // // We won't include that in this test since it's focused on the playHand function.
        });

    });
    

    };
