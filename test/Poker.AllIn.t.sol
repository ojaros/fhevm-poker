pragma solidity ^0.8.19;

// Import statements...
import "lib/forge-std/src/Test.sol";
import "fhevm/lib/TFHE.sol";
import "forge-std/console.sol";
import {Poker} from "../contracts/Poker.sol";
import {Dealer} from "../contracts/Dealer.sol";
import {PokerChip} from "../contracts/PokerChip.sol";

contract PokerAllInTest is Test {
    Poker poker;
    PokerChip pokerChip;
    
    // Define player addresses
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
        uint _buyInAmount = 300;
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

    function testAllInAsBet() public {
        uint tableId = 0;
        uint buyInAmount = 500;
        uint allInAmount = 495; // Assuming all-in amount equals buy-in amount

        vm.prank(alice);
        poker.buyIn(tableId, buyInAmount);

        vm.prank(bob);
        poker.buyIn(tableId, buyInAmount);

        vm.prank(admin);
        poker.dealCards(tableId);
       
       logPlayerBets(tableId);

        // Alice goes all-in as a bet
        vm.prank(bob);
        poker.playHand(tableId, Poker.PlayerAction.Bet, allInAmount);

        // Assert Alice's balance is 0 and she is marked as all-in
        assertEq(poker.playerChipsRemaining(bob, tableId), 0, "bob's balance should be 0");
        assertEq(uint(poker.getPlayerState(tableId, 0, bob)), uint(Poker.PlayerState.AllIn), "bob should be marked as All-In");
    }

    function testAllInOnRaise() public {
        uint tableId = 0;
        uint buyInAmount = 500;
        uint initialBetAmount = 100;
        uint allInAmountBob = 495; // Bob raises all-in at SB
        uint allInAmountOliver = 490; // Oliver raises all-in at BB

        // All players buy in for 500
        vm.prank(alice);
        poker.buyIn(tableId, buyInAmount);

        vm.prank(bob);
        poker.buyIn(tableId, buyInAmount);

        vm.prank(oliver);
        poker.buyIn(tableId, buyInAmount);

        // Admin deals cards
        vm.prank(admin);
        poker.dealCards(tableId);

        Poker.Table memory tableAtPreflop = poker.getCurrentTableState(tableId);
        uint bbIndex = poker.getBBIndex(tableId, tableAtPreflop.totalHandsTillNow);
        uint currentTurnAtPreflop = poker.getRound(tableId, tableAtPreflop.totalHandsTillNow).turn;
        assertEq(currentTurnAtPreflop, ((bbIndex + 1) % 3), "Current turn should be player to the right of big blind");

        logPlayerBets(tableId);

        // Alice bets  
        vm.prank(alice);
        poker.playHand(tableId, Poker.PlayerAction.Bet, initialBetAmount);

        // Bob raises all in 
        vm.prank(bob);
        poker.playHand(tableId, Poker.PlayerAction.Raise, allInAmountBob);

        // Oliver raises all in 
        vm.prank(oliver);
        poker.playHand(tableId, Poker.PlayerAction.Raise, allInAmountOliver);

        logPlayerBets(tableId);

        // Assert bob's balance is 0 and she is marked as all-in
        assertEq(poker.playerChipsRemaining(bob, tableId), 0, "bob's balance should be 0");
        assertEq(uint(poker.getPlayerState(tableId, 0, bob)), uint(Poker.PlayerState.AllIn), "bob should be marked as All-In");
        assertEq(poker.playerChipsRemaining(oliver, tableId), 0, "oliver's balance should be 0");
        assertEq(uint(poker.getPlayerState(tableId, 0, oliver)), uint(Poker.PlayerState.AllIn), "oliver should be marked as All-In");
    }



    function testAllInOnReRaiseAsBB() public {
        uint tableId = 0;
        uint buyInAmount = 500;
        uint initialBetAmount = 100;
        uint raiseAmount = 195;
        uint allInAmount = 490; // Oliver re-raises all-in as BB

        // All players buy in for 500
        vm.prank(alice);
        poker.buyIn(tableId, buyInAmount);

        vm.prank(bob);
        poker.buyIn(tableId, buyInAmount);

        vm.prank(oliver);
        poker.buyIn(tableId, buyInAmount);

        // Admin deals cards
        vm.prank(admin);
        poker.dealCards(tableId);

        Poker.Table memory tableAtPreflop = poker.getCurrentTableState(tableId);
        uint bbIndex = poker.getBBIndex(tableId, tableAtPreflop.totalHandsTillNow);
        uint currentTurnAtPreflop = poker.getRound(tableId, tableAtPreflop.totalHandsTillNow).turn;
        assertEq(currentTurnAtPreflop, ((bbIndex + 1) % 3), "Current turn should be player to the right of big blind");

        logPlayerBets(tableId);

        // Alice bets  
        vm.prank(alice);
        poker.playHand(tableId, Poker.PlayerAction.Bet, initialBetAmount);

        // Bob raises
        vm.prank(bob);
        poker.playHand(tableId, Poker.PlayerAction.Raise, raiseAmount);
        logPlayerBets(tableId);

        // Oliver re-raises all in
        vm.prank(oliver);
        poker.playHand(tableId, Poker.PlayerAction.Raise, allInAmount);

        logPlayerBets(tableId);

        // Assert Oliver's balance is 0 and he is marked as all-in
        assertEq(poker.playerChipsRemaining(oliver, tableId), 0, "oliver's balance should be 0");
        assertEq(uint(poker.getPlayerState(tableId, 0, oliver)), uint(Poker.PlayerState.AllIn), "oliver should be marked as All-In");
    }



    function testAllInOnCallAsSB() public {
        uint tableId = 0;
        uint numOfPlayers = 3;
        uint allInAmount = 500; // Player calls all-in

        vm.prank(alice);
        poker.buyIn(tableId, 1000);

        // Bob buys in for only 500
        vm.prank(bob);
        poker.buyIn(tableId, 500);

        vm.prank(oliver);
        poker.buyIn(tableId, 1000);

        // Admin deals cards
        vm.prank(admin);
        poker.dealCards(tableId);

        Poker.Table memory tableAtPreflop = poker.getCurrentTableState(tableId);
        uint bbIndex = poker.getBBIndex(tableId, tableAtPreflop.totalHandsTillNow);
        uint currentTurnAtPreflop = poker.getRound(tableId, tableAtPreflop.totalHandsTillNow).turn;
        assertEq(currentTurnAtPreflop, ((bbIndex + 1) % numOfPlayers), "Current turn should be player to the right of big blind");

        // Alice bets  
        vm.prank(alice);
        poker.playHand(tableId, Poker.PlayerAction.Bet, allInAmount);

        // Bob calls all-in
        vm.prank(bob);
        poker.playHand(tableId, Poker.PlayerAction.Call, 0);

        // Oliver folds
        vm.prank(oliver);
        poker.playHand(tableId, Poker.PlayerAction.Fold, 0);

        logPlayerStates(tableId);

        // Assert bob's balance is 0 and he is marked as all-in
        assertEq(poker.playerChipsRemaining(bob, tableId), 0, "bob's balance should be 0");
        assertEq(uint(poker.getPlayerState(tableId, 0, bob)), uint(Poker.PlayerState.AllIn), "bob should be marked as All-In");
    }


    function logPlayerStates(uint tableId) internal view {
        Poker.Table memory table = poker.getCurrentTableState(tableId);
        Poker.Round memory round = poker.getRound(tableId, table.totalHandsTillNow);

        for (uint i = 0; i < round.playersInRound.length; i++) {
            Poker.PlayerState playerState = poker.getPlayerState(0, table.totalHandsTillNow, round.playersInRound[i]);
            console.log("Player Address: ", round.playersInRound[i], " | Player State: ", uint(playerState));
        }
    }

    function logPlayerBets(uint tableId) internal view {
        Poker.Table memory table = poker.getCurrentTableState(tableId);
        Poker.Round memory round = poker.getRound(tableId, table.totalHandsTillNow);

        for (uint i = 0; i < round.playersInRound.length; i++) {
            uint chipsRemaining = poker.getPlayerChipsRemaining(tableId, round.playersInRound[i]);
            console.log("Player Address: ", round.playersInRound[i]);
            console.log("Chips bet: ", round.chipsPlayersHaveBet[i], " | Chips remaining: ", uint(chipsRemaining));
        }
    }
}

