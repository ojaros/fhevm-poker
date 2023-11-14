// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "lib/forge-std/src/Test.sol";
// import "ds-test/test.sol";
import "fhevm/lib/TFHE.sol";
import "forge-std/console.sol";
import {Poker} from "../contracts/Poker.sol";
import {Dealer} from "../contracts/Dealer.sol";
import {PokerChip} from "../contracts/PokerChip.sol";

contract PokerTest is Test {
    Poker poker;
    PokerChip pokerChip;

    address admin = address(this);
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address oliver = makeAddr("oliver");
    address sam = makeAddr("sam");
    address ian = makeAddr("ian");
    address milton = makeAddr("milton");

    function setUp() public {
        pokerChip = new PokerChip();
        Dealer dealer = new Dealer();
        poker = new Poker(address(dealer));

        uint amountToTransfer = 10000;
        uint _buyInAmount = 500;
        uint _maxPlayers = 6;
        uint _bigBlind = 10;
        address _token = address(pokerChip);

        vm.startPrank(admin);
        poker.initializeTable(_buyInAmount, _maxPlayers, _bigBlind, _token);

        pokerChip.transfer(alice, amountToTransfer);
        pokerChip.transfer(bob, amountToTransfer);
        pokerChip.transfer(oliver, amountToTransfer);
        pokerChip.transfer(sam, amountToTransfer);
        pokerChip.transfer(ian, amountToTransfer);
        pokerChip.transfer(milton, amountToTransfer);
        vm.stopPrank();

        vm.prank(alice);
        pokerChip.approve(address(poker),  amountToTransfer);
        vm.prank(bob);
        pokerChip.approve(address(poker),  amountToTransfer);
        vm.prank(oliver);
        pokerChip.approve(address(poker),  amountToTransfer);
        vm.prank(sam);
        pokerChip.approve(address(poker),  amountToTransfer);
        vm.prank(ian);
        pokerChip.approve(address(poker),  amountToTransfer);
        vm.prank(milton);
        pokerChip.approve(address(poker),  amountToTransfer);

    }

    function testBuyInLogic() public {
        uint tableId = 0;
        uint numOfPlayers = 4;
        uint buyInAmount = 500;

        vm.startPrank(admin);
        uint aliceBal = pokerChip.balanceOf(alice);
        console.log("PLAYER 1 BAL : ", aliceBal);
        assertTrue(aliceBal > buyInAmount, "Player does not have enough chips to buy in");
        vm.stopPrank();

        uint maxPlayers = poker.getMaxPlayers(tableId);
        console.log("Maximum number of players: ", maxPlayers);

        buyInPlayers(tableId, numOfPlayers, buyInAmount);

        vm.prank(admin);
        uint playerBalance = poker.playerChipsRemaining(alice, 0);
        assertEq(playerBalance, buyInAmount, "Player 1 balance after buy-in is incorrect");
    }

    function testDealCard() public {
        uint tableId = 0;
        uint numOfPlayers = 6;
        uint buyInAmount = 500;

        // Check player balances
        uint aliceTokens = pokerChip.balanceOf(alice);
        uint bobTokens = pokerChip.balanceOf(bob);
        assertTrue(aliceTokens > buyInAmount, "alice does not have enough tokens");
        assertTrue(bobTokens > buyInAmount, "bob does not have enough tokens");

        // Players buy in
        buyInPlayers(tableId, numOfPlayers, buyInAmount);

        // Admin deals cards
        vm.prank(admin);

        Poker.Table memory currentTableb4 = poker.getCurrentTableState(tableId);
        console.log("table b4", currentTableb4.totalHandsTillNow);
        assertEq(uint(currentTableb4.tableState), uint(Poker.TableState.Inactive), "Table state should be Inactive before dealing");


        poker.dealCards(tableId);

        // Verify the table state has changed to Active
        Poker.Table memory currentTable = poker.getCurrentTableState(tableId);
        console.log(currentTable.totalHandsTillNow);
        assertEq(uint(currentTable.tableState), uint(Poker.TableState.Active), "Table state should be Active after dealing cards");

        // Verify that the number of cards dealt is correct
        // Assuming 2 cards per player and 5 community cards
        uint expectedCardsDealt = 2 * numOfPlayers + 5;
        // euint8[] memory actualCardsDealt = poker.getDeck(tableId);
        uint[] memory actualCardsDealt = poker.getDeck(tableId);
        // for (uint i = 0; i < actualCardsDealt.length; i++) {
        //     console.log("Card ", i+1, ": ", actualCardsDealt[i]);
        // }
        assertEq(actualCardsDealt.length, expectedCardsDealt, "Incorrect number of cards dealt");

        // Add more assertions here based on the expected behavior of the dealCards function
    }

    // function testPreFlop() public {
    //     uint tableId = 0;
    //     uint numOfPlayers = 6;
    //     uint buyInAmount = 500;
    //     uint raiseAmount = 30;

    //     // Players buy in
    //     buyInPlayers(tableId, numOfPlayers, buyInAmount);

    //     // Admin deals cards
    //     vm.prank(admin);
    //     poker.dealCards(tableId);

    //     uint roundNum = poker.getCurrentTableState(tableId).totalHandsTillNow;
    //     uint currentTurn = poker.getRound(tableId, roundNum).turn;
    //     uint bbIndex = poker.getBBIndex(tableId, roundNum);
    //     assertEq(currentTurn, ((bbIndex + 1) % numOfPlayers), "Current turn should be player to the right of big blind");

    //     address[] memory players = poker.getCurrentPlayers(tableId);

    //     uint expectedPotSize = setupPreflop(tableId, raiseAmount, players);

    //     Poker.Round memory roundAfterPreflop = poker.getRound(tableId, roundNum);
    //     uint actualPotSize = roundAfterPreflop.pot;
    //     assertEq(actualPotSize, expectedPotSize, "Pot size after preflop is incorrect");
    // }

    function testFullGame() public {
        uint tableId = 0;
        uint numOfPlayers = 6;
        uint buyInAmount = 1000;
        uint raiseAmount = 30;

        // Players buy in
        buyInPlayers(tableId, numOfPlayers, buyInAmount);

        // Admin deals cards
        vm.prank(admin);
        poker.dealCards(tableId);

        address[] memory playersAtPreflop = poker.getCurrentPlayers(tableId);

        // ------------------ PRE-FLOP -------------------------------
        Poker.Table memory tableAtPreflop = poker.getCurrentTableState(tableId);
        Poker.Round memory roundAtPreflop = poker.getRound(0, tableAtPreflop.totalHandsTillNow);
        uint currentTurnAtPreflop = poker.getRound(tableId, tableAtPreflop.totalHandsTillNow).turn;
        console.log("FIRST TURN AT PREFLOP : ", currentTurnAtPreflop);
        uint bbIndex = poker.getBBIndex(tableId, tableAtPreflop.totalHandsTillNow);
        console.log("BB INDEX : ", bbIndex);
        assertEq(currentTurnAtPreflop, ((bbIndex + 1) % numOfPlayers), "Current turn should be player to the right of big blind");

        uint expectedPotSizeAtFlop = setupPreflop(tableId, raiseAmount, playersAtPreflop);
        uint actualPotSizeAtFlop = roundAtPreflop.pot;
        assertEq(actualPotSizeAtFlop, expectedPotSizeAtFlop, "Pot size after pre-flop is incorrect");
        // ------------------ PRE-FLOP -------------------------------


        // ------------------ FLOP -------------------------------
        uint raiseAmountAtFlop = 60;
        uint reRaiseAmountAtFlop = 120;

        console.log("\nPLAYERS AT START OF FLOP: ");
        logActivePlayers(tableId);
        console.log("POT AT START OF FLOP");
        console.log(expectedPotSizeAtFlop);

        Poker.Table memory tableAtFlop = poker.getCurrentTableState(tableId);
        Poker.Round memory roundAtFlop = poker.getRound(0, tableAtFlop.totalHandsTillNow);

        console.log("SB INDEX : ", poker.getSBIndex(0, tableAtFlop.totalHandsTillNow));
        console.log("\nINITIAL FIRST TO ACT AT FLOP (should be sb, or bb if sb folded): ", poker.getCurrentPlayers(0)[roundAtFlop.turn]);
        console.log("INITIAL LAST TO ACT (button or player right of sb): ",roundAtFlop.lastToAct, "\n");

        uint expectedPotSizeAtTurn = setupFlop(0, raiseAmountAtFlop, reRaiseAmountAtFlop);
        console.log("END OF FLOP... CHECK POT SIZE IS ACCURATE ");
        
        Poker.Table memory tableAtTurn = poker.getCurrentTableState(0);
        Poker.Round memory roundAtTurn = poker.getRound(0, tableAtTurn.totalHandsTillNow);
        uint actualPotSizeAtTurn = roundAtTurn.pot;
        assertEq(actualPotSizeAtTurn, expectedPotSizeAtTurn, "Pot size after flop is incorrect");
        // -------------------------------------------------------




        // ------------------ Turn -------------------------------\
        uint raiseAmountAtTurn = 10;
        uint reRaiseAmountAtTurn = 200;

        console.log("PLAYERS AT START OF TURN: ");
        logActivePlayers(0);

        uint expectedPotSizeAtRiver = setupTurn(0, raiseAmountAtTurn, reRaiseAmountAtTurn);
        console.log("END OF Turn... CHECK POT SIZE IS ACCURATE ");
        
        Poker.Table memory tableAtRiver = poker.getCurrentTableState(0);
        Poker.Round memory roundAtRiver = poker.getRound(0, tableAtRiver.totalHandsTillNow);
        uint actualPotSizeAtRiver = roundAtRiver.pot;
        assertEq(actualPotSizeAtRiver, expectedPotSizeAtRiver, "Pot size after turn is incorrect");
        // -------------------------------------------------------



        // ------------------ River -------------------------------\
        uint raiseAmountAtRiver = 100;

        console.log("PLAYERS AT START OF River: ");
        logActivePlayers(0);

        uint expectedPotSizeAtShowdown = setUpRiver(0, raiseAmountAtRiver, poker.getCurrentPlayers(0));
        console.log("END OF RIVER... CHECK POT SIZE IS ACCURATE ");
        
        // Poker.Table memory tableAtShowdown = poker.getCurrentTableState(0);
        // Poker.Round memory roundAtShowdown = poker.getRound(0, tableAtShowdown.totalHandsTillNow);
        // uint actualPotSizeAtShowdown = roundAtShowdown.pot;
        // console.log("ACTUAL POT : ", actualPotSizeAtShowdown);
        // console.log("expected POT : ", expectedPotSizeAtShowdown);
        // assertEq(actualPotSizeAtShowdown, expectedPotSizeAtShowdown, "Pot size after river is incorrect"); 
        // -------------------------------------------------------
        

    }



    // ----------------------------- HELPER FUNCTIONS ------------------------------
    function buyInPlayers(uint tableId, uint numberOfPlayers, uint buyInAmount) public {
        require(numberOfPlayers <= 6, "Maximum 6 players allowed");

        address[] memory players = new address[](6);
        players[0] = alice;
        players[1] = bob;
        players[2] = oliver;
        players[3] = sam;
        players[4] = ian;
        players[5] = milton;

        for (uint i = 0; i < numberOfPlayers; i++) {
            vm.prank(players[i]);
            poker.buyIn(tableId, buyInAmount);
        }
    }

    function setupPreflop(uint tableId, uint raiseAmount, address[] memory players) internal returns (uint) {
        Poker.Table memory table = poker.getCurrentTableState(tableId);
        uint expectedPotSize = table.bigBlindAmount + (table.bigBlindAmount / 2);

        uint updatedCurrentTurn = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn]);
        poker.playHand(tableId, Poker.PlayerAction.Raise, raiseAmount);
        expectedPotSize += raiseAmount;
        console.log("\nPlayer Address: ", players[updatedCurrentTurn], " | Raises: ", raiseAmount);
        console.log("LST TO ACT: ", poker.getRound(0, table.totalHandsTillNow).lastToAct);
        console.log("HIGHEST CHIP: ", poker.getRound(tableId, table.totalHandsTillNow).highestChip, "POT SIZE : ", expectedPotSize);
        console.log("\n");

        uint updatedCurrentTurn1 = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn1]);
        poker.playHand(tableId, Poker.PlayerAction.Call, 0); // 0 for _raiseAmount since we're just calling
        expectedPotSize += raiseAmount;
        console.log("Player Address: ", players[updatedCurrentTurn1], " | Calls: ", raiseAmount);
        console.log("LST TO ACT: ", poker.getRound(0, table.totalHandsTillNow).lastToAct);
        console.log("HIGHEST CHIP: ", poker.getRound(tableId, table.totalHandsTillNow).highestChip, "POT SIZE : ", expectedPotSize);
        console.log("\n");

        uint updatedCurrentTurn2 = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn2]);
        poker.playHand(tableId, Poker.PlayerAction.Fold, 0); // 0 for _raiseAmount since we're folding
        console.log("Player Address: ", players[updatedCurrentTurn2], " | Folds ");
        console.log("LST TO ACT: ", poker.getRound(0, table.totalHandsTillNow).lastToAct);
        console.log("HIGHEST CHIP: ", poker.getRound(tableId, table.totalHandsTillNow).highestChip, "POT SIZE : ", expectedPotSize);
        console.log("\n");

        uint updatedCurrentTurn3 = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn3]);
        poker.playHand(tableId, Poker.PlayerAction.Call, 0); // 0 for _raiseAmount since we're just calling
        expectedPotSize += raiseAmount;
        console.log("Player Address: ", players[updatedCurrentTurn3], " | Calls: ", raiseAmount);
        console.log("LST TO ACT: ", poker.getRound(0, table.totalHandsTillNow).lastToAct);
        console.log("HIGHEST CHIP: ", poker.getRound(tableId, table.totalHandsTillNow).highestChip, "POT SIZE : ", expectedPotSize);
        console.log("\n");


        // (small blind) and (big blind).
        uint updatedCurrentTurn4 = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn4]);
        poker.playHand(tableId, Poker.PlayerAction.Call, 0);
        expectedPotSize += (raiseAmount - (table.bigBlindAmount / 2));
        console.log("Player Address at small blind: ", players[updatedCurrentTurn4], " | Calls: ", raiseAmount - (table.bigBlindAmount / 2));
        console.log("LST TO ACT: ", poker.getRound(0, table.totalHandsTillNow).lastToAct);
        console.log("HIGHEST CHIP: ", poker.getRound(tableId, table.totalHandsTillNow).highestChip, "POT SIZE : ", expectedPotSize);
        console.log("\n");

        uint updatedCurrentTurn5 = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn5]);
        poker.playHand(tableId, Poker.PlayerAction.Call, 0);
        expectedPotSize += (raiseAmount - (table.bigBlindAmount));
        console.log("Player Address at big blind: ", players[updatedCurrentTurn5], " | Calls: ", raiseAmount - (table.bigBlindAmount));

        console.log("next round starting...");


        return expectedPotSize;
    }

    function setupFlop(uint tableId, uint raiseAmount, uint reRaiseAmount) internal returns (uint) {
        Poker.Table memory table = poker.getCurrentTableState(tableId);
        Poker.Round memory currentRound = poker.getRound(tableId, table.totalHandsTillNow);
        uint expectedPotSize = currentRound.pot; // Starting with the pot size at the end of preflop

        address currentPlayer = poker.getCurrentPlayers(tableId)[currentRound.turn];

        bool shouldContinue = true;
        
        for (uint i = 0; shouldContinue; i++) {
            uint updatedCurrentTurn = poker.getRound(tableId, table.totalHandsTillNow).turn;
            currentPlayer = poker.getCurrentPlayers(tableId)[updatedCurrentTurn];

            if (currentPlayer == poker.getRound(tableId, table.totalHandsTillNow).lastToAct) {
                // This was the last to act player, so set shouldContinue to false
                // This will allow the loop to finish its current iteration but not start a new one
                console.log("CURRENT PLAYER IS LAST TO ACT, FINISHING THIS ITERATION THEN TERMINATING LOOP");
                shouldContinue = false;
            }

            if (i == 0) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Raise, raiseAmount);
                expectedPotSize += raiseAmount;
                console.log("\nPlayer Address: ", currentPlayer, " | Raise: ", raiseAmount);
            }
            else if (i == 1) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Call, 0);
                expectedPotSize += raiseAmount;
                console.log("Player Address: ", currentPlayer, " | Calls", raiseAmount);
            } else if (i == 2) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Raise, reRaiseAmount);
                expectedPotSize += reRaiseAmount;
                console.log("Player Address: ", currentPlayer, " | Raises: ", reRaiseAmount);
            } else if (i > 2) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Call, 0);
                if (i == 5 || i == 6) {
                    expectedPotSize += (reRaiseAmount - raiseAmount);
                } else {
                    expectedPotSize += reRaiseAmount;
                }
                console.log("Player Address: ", currentPlayer, " | Called: ", reRaiseAmount);
            } 
           
            console.log("LST TO ACT: ", poker.getRound(0, table.totalHandsTillNow).lastToAct);
            console.log("HIGHEST CHIP: ", poker.getRound(tableId, table.totalHandsTillNow).highestChip, "POT SIZE : ", expectedPotSize);
            console.log("\n");

        } 


        return expectedPotSize;
    }


    function setupTurn(uint tableId, uint raiseAmount, uint reRaiseAmount) internal returns (uint) {
        Poker.Table memory table = poker.getCurrentTableState(tableId);
        Poker.Round memory currentRound = poker.getRound(tableId, table.totalHandsTillNow);
        uint expectedPotSize = currentRound.pot; // Starting with the pot size at the end of flop

        address currentPlayer = poker.getCurrentPlayers(tableId)[currentRound.turn];

        bool shouldContinue = true;
        
        for (uint i = 0; shouldContinue; i++) {
            uint updatedCurrentTurn = poker.getRound(tableId, table.totalHandsTillNow).turn;
            currentPlayer = poker.getCurrentPlayers(tableId)[updatedCurrentTurn];

            if (currentPlayer == poker.getRound(tableId, table.totalHandsTillNow).lastToAct) {
                // This was the last to act player, so set shouldContinue to false
                // This will allow the loop to finish its current iteration but not start a new one
                console.log("CURRENT PLAYER IS LAST TO ACT, FINISHING THIS ITERATION THEN TERMINATING LOOP");
                shouldContinue = false;
            }

            if (i == 0) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Raise, raiseAmount);
                expectedPotSize += raiseAmount;
                console.log("\nPlayer Address: ", currentPlayer, " | Raise: ", raiseAmount);
            }
            else if (i == 1) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Fold, 0);
                console.log("Player Address: ", currentPlayer, " | Folds");
            } else if (i == 2) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Raise, reRaiseAmount);
                expectedPotSize += reRaiseAmount;
                console.log("Player Address: ", currentPlayer, " | Raises: ", reRaiseAmount);
            } else if (i == 3) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Call, 0);
                console.log("Player Address: ", currentPlayer, " | Calls: ", reRaiseAmount);
            } else if (i == 4) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Fold, 0);
                console.log("Player Address: ", currentPlayer, " | Folds: ");
            }
             else if (i > 4) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Fold, 0);
                expectedPotSize += reRaiseAmount;
                console.log("Player Address: ", currentPlayer, " | Folded: ");
            } 
           
            console.log("LST TO ACT: ", poker.getRound(0, table.totalHandsTillNow).lastToAct);
            console.log("HIGHEST CHIP: ", poker.getRound(tableId, table.totalHandsTillNow).highestChip, "POT SIZE : ", expectedPotSize);
            console.log("\n");

        } 


        return expectedPotSize;
    }


    function setUpRiver(uint tableId, uint raiseAmount, address[] memory players) internal returns (uint) {
        Poker.Table memory table = poker.getCurrentTableState(tableId);
        Poker.Round memory currentRound = poker.getRound(tableId, table.totalHandsTillNow);
        uint expectedPotSize = currentRound.pot; // Starting with the pot size at the end of turn

        uint updatedCurrentTurn = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn]);
        poker.playHand(tableId, Poker.PlayerAction.Raise, raiseAmount);
        expectedPotSize += raiseAmount;
        console.log("\nPlayer Address: ", players[updatedCurrentTurn], " | Raises: ", raiseAmount);
        console.log("LST TO ACT: ", poker.getRound(0, table.totalHandsTillNow).lastToAct);
        console.log("HIGHEST CHIP: ", poker.getRound(tableId, table.totalHandsTillNow).highestChip, "POT SIZE : ", expectedPotSize);
        console.log("\n");

        uint updatedCurrentTurn1 = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn1]);
        poker.playHand(tableId, Poker.PlayerAction.Call, 0); // 0 for _raiseAmount since we're just calling
        expectedPotSize += raiseAmount;
        console.log("Player Address: ", players[updatedCurrentTurn1], " | Calls: ", raiseAmount);
        console.log("LST TO ACT: ", poker.getRound(0, table.totalHandsTillNow).lastToAct);
        console.log("HIGHEST CHIP: ", poker.getRound(tableId, table.totalHandsTillNow).highestChip, "POT SIZE : ", expectedPotSize);
        console.log("\n");

        return expectedPotSize;
    }


    function logActivePlayers(uint tableId) internal view {
        Poker.Table memory table = poker.getCurrentTableState(tableId);
        Poker.Round memory round = poker.getRound(tableId, table.totalHandsTillNow);

        for (uint i = 0; i < round.playersInRound.length; i++) {
            Poker.PlayerState playerState = poker.getPlayerState(0, table.totalHandsTillNow, round.playersInRound[i]);
            console.log("Player Address: ", round.playersInRound[i], " | Player State: ", uint(playerState));
        }
    }

    // function logPlayerStatus(uint tableId) public {
    //     Poker.Table memory table = poker.getCurrentTableState(tableId);
    //     uint totalHands = table.totalHandsTillNow;
    //     Poker.Round memory round = poker.getRound(tableId, totalHands);

    //     for (uint i = 0; i < table.players.length; i++) {
    //         Poker.PlayerState state = poker.playerStates[tableId][totalHands][round.playersInRound[i]][]; // If using a mapping
    //         // PlayerState state = playerStates[i]; // If using an array

    //         if (state == Poker.PlayerState.Folded) {
    //             console.log("Player %s has folded", round.playersInRound[i]);
    //         } else if (state == Poker.PlayerState.Active) {
    //             console.log("Player %s is still in", round.playersInRound[i]);
    //         }
    //         // ... handle other states as needed
    //     }
    // }

}