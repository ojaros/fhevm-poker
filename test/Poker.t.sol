// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "lib/forge-std/src/Test.sol";
// import "ds-test/test.sol";
import "forge-std/console.sol";
import {Poker} from "../contracts/Poker.sol";
import {PokerChip} from "../contracts/PokerChip.sol";
import {IERC20} from "../interfaces/IERC20.sol";
    // enum TableState {
    //     Active,
    //     Inactive
    // }
    // enum RoundState {
    //     Preflop,
    //     Flop,
    //     Turn,
    //     River,
    //     Showdown
    // }  
    // enum PlayerAction {
    //     Call,
    //     Raise,
    //     Check,
    //     Fold
    // }
    // enum PlayerState { 
    //     Active,
    //     Folded,
    //     AllIn
    // }

    // struct PlayerCardsEncrypted {
    //     uint card1Encrypted;
    //     uint card2Encrypted;
    // }
    // struct Table {
    //     Poker.TableState tableState;
    //     uint totalHandsTillNow; //total hands till now
    //     uint buyInAmount;
    //     uint maxPlayers;
    //     address[] players;
    //     uint bigBlindAmount;
    //     IERC20 token; // token used to bet and play
    // }
    // struct Round {
    //     Poker.RoundState roundState;
    //     bool isActive;
    //     uint turn; // index of the players array, who has the current turn
    //     address [] playersInRound; // players still in the round (not folded)
    //     uint highestChip; // current highest chip to be called
    //     uint[] chipsPlayersHaveBet; // array of chips each player has put in, compared with highestChip to see if player has to call again
    //     uint pot; // total chips in the current round
    //     uint buttonIndex; // Index for the Button (Dealer) in the players array
    //     address lastToAct; // Index of last player to act
    // }

contract PokerTest is Test {

    Poker poker;
    PokerChip pokerChip;

    address admin = address(this);
    address player1 = vm.addr(0x1);
    address player2 = vm.addr(0x2);
    address player3 = vm.addr(0x3);
    address player4 = vm.addr(0x4);
    address player5 = vm.addr(0x50);
    address player6 = vm.addr(0x6);

    function setUp() public {
        pokerChip = new PokerChip();
        poker = new Poker();

        uint amountToTransfer = 10000;
        uint _buyInAmount = 500;
        uint _maxPlayers = 6;
        uint _bigBlind = 10;
        address _token = address(pokerChip);

        vm.startPrank(admin);
        poker.initializeTable(_buyInAmount, _maxPlayers, _bigBlind, _token);

        pokerChip.transfer(player1, amountToTransfer);
        pokerChip.transfer(player2, amountToTransfer);
        pokerChip.transfer(player3, amountToTransfer);
        pokerChip.transfer(player4, amountToTransfer);
        pokerChip.transfer(player5, amountToTransfer);
        pokerChip.transfer(player6, amountToTransfer);
        vm.stopPrank();

        vm.prank(player1);
        pokerChip.approve(address(poker),  amountToTransfer);
        vm.prank(player2);
        pokerChip.approve(address(poker),  amountToTransfer);
        vm.prank(player3);
        pokerChip.approve(address(poker),  amountToTransfer);
        vm.prank(player4);
        pokerChip.approve(address(poker),  amountToTransfer);
        vm.prank(player5);
        pokerChip.approve(address(poker),  amountToTransfer);
        vm.prank(player6);
        pokerChip.approve(address(poker),  amountToTransfer);

    }

    function testBuyInLogic() public {
        uint tableId = 0;
        uint numOfPlayers = 4;
        uint buyInAmount = 500;

        vm.startPrank(admin);
        uint player1Bal = pokerChip.balanceOf(player1);
        console.log("PLAYER 1 BAL : ", player1Bal);
        assertTrue(player1Bal > buyInAmount, "Player does not have enough chips to buy in");
        vm.stopPrank();

        uint maxPlayers = poker.getMaxPlayers(tableId);
        console.log("Maximum number of players: ", maxPlayers);

        buyInPlayers(tableId, numOfPlayers, buyInAmount);

        vm.prank(admin);
        uint playerBalance = poker.playerChipsRemaining(player1, 0);
        assertEq(playerBalance, buyInAmount, "Player 1 balance after buy-in is incorrect");
    }

    function testDealCard() public {
        uint tableId = 0;
        uint numOfPlayers = 6;
        uint buyInAmount = 500;

        // Check player balances
        uint player1Tokens = pokerChip.balanceOf(player1);
        uint player2Tokens = pokerChip.balanceOf(player2);
        assertTrue(player1Tokens > buyInAmount, "Player1 does not have enough tokens");
        assertTrue(player2Tokens > buyInAmount, "Player2 does not have enough tokens");

        // Players buy in
        buyInPlayers(tableId, numOfPlayers, buyInAmount);

        // Admin deals cards
        vm.prank(admin);
        poker.dealCards(tableId);

        // Verify the table state has changed to Active
        Poker.Table memory currentTable = poker.getCurrentTableState(tableId);
        console.log(currentTable.totalHandsTillNow);
        assertEq(uint(currentTable.tableState), uint(Poker.TableState.Active), "Table state should be Active after dealing cards");

        // Verify that the number of cards dealt is correct
        // Assuming 2 cards per player and 5 community cards
        uint expectedCardsDealt = 2 * numOfPlayers + 5;
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
        Poker.Table memory tableAtPreflop = poker.getCurrentTableState(tableId);
        uint currentTurnAtPreflop = poker.getRound(tableId, tableAtPreflop.totalHandsTillNow).turn;
        uint bbIndex = poker.getBBIndex(tableId, tableAtPreflop.totalHandsTillNow);

        for (uint i = 0; i < playersAtPreflop.length; i++) {
            Poker.PlayerState playerState = poker.getPlayerState(tableId, tableAtPreflop.totalHandsTillNow, playersAtPreflop[i]);
            console.log("Player Address: ", playersAtPreflop[i], "Player State: ", uint(playerState));
        }

        assertEq(currentTurnAtPreflop, ((bbIndex + 1) % numOfPlayers), "Current turn should be player to the right of big blind");

        uint expectedPotSizeAtFlop = setupPreflop(tableId, raiseAmount, playersAtPreflop);




        // ------------------ FLOP -------------------------------
        uint raiseAmountAtFlop = 60;
        uint reRaiseAmountAtFlop = 100;

        console.log("PLAYERS AT START OF FLOP: ");
        logActivePlayers(tableId);

        uint expectedPotSizeAtTurn = setupFlop(0, raiseAmountAtFlop, reRaiseAmountAtFlop);
        
        Poker.Table memory tableAtTurn = poker.getCurrentTableState(0);
        Poker.Round memory roundAtTurn = poker.getRound(0, tableAtTurn.totalHandsTillNow);
        uint actualPotSizeAtTurn = roundAtTurn.pot;
        assertEq(actualPotSizeAtTurn, expectedPotSizeAtTurn, "Pot size after flop is incorrect");
        // -------------------------------------------------------




        // // ------------------ Turn -------------------------------\
        // uint raiseAmountAtTurn = 500;
        // uint reRaiseAmountAtTurn = 1000;

        // console.log("PLAYERS AT START OF TURN: ");
        // logActivePlayers(0);

        // uint expectedPotSizeAtRiver = setupTurn(0, raiseAmountAtTurn, reRaiseAmountAtTurn);
        // // -------------------------------------------------------
        

    }



    // ----------------------------- HELPER FUNCTIONS ------------------------------
    function buyInPlayers(uint tableId, uint numberOfPlayers, uint buyInAmount) public {
        require(numberOfPlayers <= 6, "Maximum 6 players allowed");

        address[] memory players = new address[](6);
        players[0] = player1;
        players[1] = player2;
        players[2] = player3;
        players[3] = player4;
        players[4] = player5;
        players[5] = player6;

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

        uint updatedCurrentTurn1 = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn1]);
        poker.playHand(tableId, Poker.PlayerAction.Call, 0); // 0 for _raiseAmount since we're just calling
        expectedPotSize += raiseAmount;

        uint updatedCurrentTurn2 = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn2]);
        poker.playHand(tableId, Poker.PlayerAction.Fold, 0); // 0 for _raiseAmount since we're folding

        uint updatedCurrentTurn3 = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn3]);
        poker.playHand(tableId, Poker.PlayerAction.Call, 0); // 0 for _raiseAmount since we're just calling
        expectedPotSize += raiseAmount;


        // (small blind) and (big blind).
        uint updatedCurrentTurn4 = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn4]);
        poker.playHand(tableId, Poker.PlayerAction.Call, 0);
        expectedPotSize += (raiseAmount - (table.bigBlindAmount / 2));

        uint updatedCurrentTurn5 = poker.getRound(tableId, table.totalHandsTillNow).turn;
        vm.prank(players[updatedCurrentTurn5]);
        poker.playHand(tableId, Poker.PlayerAction.Call, 0);
        expectedPotSize += (raiseAmount - (table.bigBlindAmount));

        return expectedPotSize;
    }

    function setupFlop(uint tableId, uint raiseAmount, uint reRaiseAmount) internal returns (uint) {
        Poker.Table memory table = poker.getCurrentTableState(tableId);
        Poker.Round memory currentRound = poker.getRound(tableId, table.totalHandsTillNow);
        uint expectedPotSize = currentRound.pot; // Starting with the pot size at the end of preflop

        address currentPlayer = poker.getCurrentPlayers(tableId)[currentRound.turn];

        for (uint i = 0; currentPlayer != poker.getRound(tableId, table.totalHandsTillNow).lastToAct; i++) {
            uint updatedCurrentTurn = poker.getRound(tableId, table.totalHandsTillNow).turn;
            currentPlayer = poker.getCurrentPlayers(tableId)[updatedCurrentTurn];

            if (i == 0) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Raise, raiseAmount);
                expectedPotSize += raiseAmount;
                console.log("\nPlayer Address: ", currentPlayer, " | Raise: ", raiseAmount);
            }
            else if (i == 1) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Fold, 0);
                console.log("Player Address: ", currentPlayer, " | Folds: ");
            } else if (i == 2) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Raise, reRaiseAmount);
                expectedPotSize += reRaiseAmount;
                console.log("Player Address: ", currentPlayer, " | ReRaises: ", reRaiseAmount);
            } else if (i > 2) {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Call, 0);
                expectedPotSize += reRaiseAmount;
                console.log("Player Address: ", currentPlayer, " | Called: ", reRaiseAmount);
            } else {
                vm.prank(currentPlayer);
                poker.playHand(tableId, Poker.PlayerAction.Call, 0);
                expectedPotSize += raiseAmount;
                console.log("Player Address: ", currentPlayer, " | Called: ", raiseAmount);
            }
           
            console.log("HIGHEST CHIP: ", poker.getRound(tableId, table.totalHandsTillNow).highestChip, "POT SIZE : ", expectedPotSize);
            console.log("LST TO ACT: ", poker.getRound(0, table.totalHandsTillNow).lastToAct, "CURR TURN : ", currentPlayer);
            console.log("\n");

        } 

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