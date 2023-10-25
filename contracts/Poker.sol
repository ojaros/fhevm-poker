// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity >=0.8.13 <0.9.0;

import "fhevm/abstracts/EIP712WithModifier.sol";
import "fhevm/lib/TFHE.sol";
import "hardhat/console.sol";
import {IERC20} from "../interfaces/IERC20.sol";


contract Poker is EIP712WithModifier {

    constructor() EIP712WithModifier("Authorization token", "1") {
        owner = msg.sender;
    }

    address public owner;


    enum TableState {
        Active,
        Inactive
    }

    enum RoundState {
        Preflop,
        Flop,
        Turn,
        River,
        Showdown
    }  

    enum PlayerAction {
        Call,
        Raise,
        Check,
        Fold
    }

    enum PlayerState { 
        Active,
        Folded,
        AllIn
    }

    event NewTableCreated(uint tableId, Table table);
    event NewBuyIn(uint tableId, address player, uint amount);
    event PlayerCardsDealt(PlayerCardsEncrypted[] PlayerCardsEncrypted, uint tableId);
    event RoundOver(uint tableId, uint round);
    event CommunityCardsDealt(uint tableId, uint roundId, uint[] cards);
    event TableShowdown(uint tableId);
    event DebugPlayerCards(uint256 indexed tableId, uint card1Encrypted, uint card2Encrypted);
    // event DebugPlayerCards(uint256 indexed tableId, euint8 card1Encrypted, euint8 card2Encrypted);
    event DebugDeck(uint cardEncrypted);
    event RoundStateAdvanced(uint tableId, RoundState roundState, uint pot);
    event ChipsIntoPot(uint tableId, uint chips);
    event PlayerCall(uint tableId, uint callAmount);
    event PlayerRaise(uint tableId, uint raiseAmount);


    struct Table {
        TableState tableState;
        uint totalHandsTillNow; //total hands till now
        uint buyInAmount;
        uint maxPlayers;
        address[] players;
        uint bigBlindAmount;
        IERC20 token; // token used to bet and play
    }
    struct Round {
        RoundState roundState;
        bool isActive;
        uint turn; // index of the players array, who has the current turn
        address [] playersInRound; // players still in the round (not folded)
        uint highestChip; // current highest chip to be called
        uint[] chipsPlayersHaveBet; // array of chips each player has put in, compared with highestChip to see if player has to call again
        uint pot; // total chips in the current round
        uint buttonIndex; // Index for the Button (Dealer) in the players array
        address lastToAct; // Index of last player to act
    }
    // struct PlayerCardsEncrypted {
    //     euint8 card1Encrypted;
    //     euint8 card2Encrypted;
    // }

    struct PlayerCardsEncrypted {
        uint card1Encrypted;
        uint card2Encrypted;
    }
    struct PlayerCardsPlainText {
        uint8 card1;
        uint8 card2;
    }

    uint public totalTables = 0;

    // id => Table
    mapping(uint => Table) public tables;

    // each tableId maps to a deck
    // tableId => totalHandsTillNow => deck
    // mapping(uint => euint8[]) public decks;
    mapping(uint => mapping(uint => uint[])) public decks;

    // array of community cards
    // tableId => totalHandsTillNow => int[8] community cards
    mapping(uint => mapping(uint => uint[])) public communityCards;

    //keeps track of remaining chips of a player in a table.... player => tableId => remainingChips
    mapping(address => mapping(uint => uint)) public playerChipsRemaining;

    // player => tableId => handNum => PlayerCards;
    mapping(address => mapping(uint => mapping(uint => PlayerCardsEncrypted))) public playerCardsEncryptedDuringHand;

    // maps roundNum to Round
    // tableId => totalHandsTillNow => Round
    mapping(uint => mapping(uint => Round)) public rounds;


    // player states
    // talbeId => totalHandsTillNow => player address => PlayerState
    mapping(uint => mapping(uint => mapping(address => PlayerState))) public playerStates;


    /// @dev Initialize the table, this should only be called once
    /// @param _buyInAmount The minimum amount of tokens required to enter the table
    /// @param _maxPlayers The maximum number of players allowed in this table
    /// @param _bigBlind The big blind amount for the table
    /// @param _token The token used to bet in this table
    function initializeTable(uint _buyInAmount, uint _maxPlayers, uint _bigBlind, address _token) external {

        address [] memory empty;

        tables[totalTables] = Table({
            tableState: TableState.Inactive,
            totalHandsTillNow: 0,
            buyInAmount: _buyInAmount, 
            maxPlayers: _maxPlayers,
            players: empty, // initializing with empty dynamic array
            bigBlindAmount: _bigBlind,
            token: IERC20(_token)
        });

        emit NewTableCreated(totalTables, tables[totalTables]);

        totalTables += 1;
    }

    /// @dev a player can call to withdraw their chips from the table
    /// @param _tableId the unique id of the table
    /// @param _amount The amount of tokens to withdraw from the table. (must be >= player's balance)
    function withdrawChips(uint _tableId, uint _amount) external {
        require(playerChipsRemaining[msg.sender][_tableId] >= _amount, "Not enough balance");
        playerChipsRemaining[msg.sender][_tableId] -= _amount;
        require(tables[_tableId].token.transfer(msg.sender, _amount));
    }


    /// @dev players have to call this to buy ina nd enter the table
    /// @param _tableId the unique id of the table
    /// @param _amount The amount of tokens to buy in the table. (must be >= min table buy in amount)
    /// TODO: add logic to allow existing player at table to re-buy in
    function buyIn(uint _tableId, uint _amount) public {
        Table storage table = tables[_tableId];

        require(_amount >= table.buyInAmount, "Not enough buyInAmount");
        require(table.players.length < table.maxPlayers, "Table is full");

        // transfer player's buy in to contract
        require(table.token.transferFrom(msg.sender, address(this), _amount), "Transfer player's buy in to contract");
        playerChipsRemaining[msg.sender][_tableId] += _amount;

        // add player to the table
        table.players.push(msg.sender);

        emit NewBuyIn(_tableId, msg.sender, _amount);
    }


    function dealCards(uint _tableId) public {
        Table storage table = tables[_tableId];
        require(table.tableState == TableState.Inactive, "Game already going on");
        uint numOfPlayers = table.players.length;
        require(numOfPlayers > 1, "ERROR : not enough players");
        table.tableState = TableState.Active;

        setDeal(_tableId, 2 * numOfPlayers + 5); // assuming 2 cards per player and 5 community cards

        Round storage round = rounds[_tableId][table.totalHandsTillNow];

        round.isActive = true;
        round.roundState = RoundState.Preflop;
        // TODO: Add logic to handle players at the table, but sitting out this round
        round.playersInRound = table.players;
        round.highestChip = table.bigBlindAmount;
        round.chipsPlayersHaveBet = new uint256[](numOfPlayers);  // Initialize chips array with zeros for each player
        round.turn = (getBBIndex(_tableId, table.totalHandsTillNow) + 1) % numOfPlayers;
        round.lastToAct = round.playersInRound[getBBIndex(_tableId, table.totalHandsTillNow)];

        PlayerCardsEncrypted[] memory playerCardsEncryptedArray = new PlayerCardsEncrypted[](numOfPlayers);

        for (uint i = 0; i < numOfPlayers; i++) {
            require(i < round.chipsPlayersHaveBet.length, "round.chips out of bounds");
            playerStates[_tableId][table.totalHandsTillNow][round.playersInRound[i]] = PlayerState.Active;

            if (i == (getSBIndex(_tableId, table.totalHandsTillNow))) { // last player, small blind
                // Ensure that the operation doesn't lead to underflows
                require(playerChipsRemaining[round.playersInRound[i]][_tableId] >= table.bigBlindAmount / 2, "Underflow for small blind");
                
                round.chipsPlayersHaveBet[i] = table.bigBlindAmount / 2;
                playerChipsRemaining[round.playersInRound[i]][_tableId] -= table.bigBlindAmount / 2;
                
            } else if (i == (getBBIndex(_tableId, table.totalHandsTillNow))) { // second to last player, big blind
            
                // Ensure that the operation doesn't lead to underflows
                require(playerChipsRemaining[round.playersInRound[i]][_tableId] >= table.bigBlindAmount, "Underflow for big blind");
                
                round.chipsPlayersHaveBet[i] = table.bigBlindAmount;
                playerChipsRemaining[round.playersInRound[i]][_tableId] -= table.bigBlindAmount;
            }

            // Ensure decks[_tableId] has enough elements
            require(2 * i + 1 < decks[_tableId][table.totalHandsTillNow].length, "decks out of bounds");
            
            // Save the encrypted card for each player
            playerCardsEncryptedArray[i].card1Encrypted = decks[_tableId][table.totalHandsTillNow][2 * i];
            playerCardsEncryptedArray[i].card2Encrypted = decks[_tableId][table.totalHandsTillNow][2 * i + 1];

            emit DebugPlayerCards(_tableId, playerCardsEncryptedArray[i].card1Encrypted, playerCardsEncryptedArray[i].card2Encrypted);
            playerCardsEncryptedDuringHand[round.playersInRound[i]][_tableId][table.totalHandsTillNow] = playerCardsEncryptedArray[i];

        }

        emit PlayerCardsDealt(playerCardsEncryptedArray, _tableId); // emit encrypted player cards for all players at once

        // round.pot += table.bigBlindAmount + (table.bigBlindAmount / 2);

    }


    /// @param _raiseAmount only required in case of raise. Else put zero. This is the amount you are putting in addition to what you have already put in this round
    function playHand(uint _tableId, PlayerAction _action, uint _raiseAmount) external {
        Table storage table = tables[_tableId];
        Round storage round = rounds[_tableId][table.totalHandsTillNow];

        require(table.tableState == TableState.Active, "Table is inactive");
        require(round.isActive, "No active round");
        require(round.playersInRound[round.turn] == msg.sender, "Not your turn");

        if (_action == PlayerAction.Call) {
            // in case of calling
            // deduct chips from user
            // add chips to pot
            // keep the player in the round

            uint callAmount = round.highestChip - round.chipsPlayersHaveBet[round.turn];
            emit PlayerCall(_tableId, callAmount);

            require(callAmount > 0, "Call amount is not positive");
            require(playerChipsRemaining[msg.sender][_tableId] >= callAmount, "Not enough chips to call");
            require(round.playersInRound[round.turn] == msg.sender, "Player not expected to act");
            require(round.chipsPlayersHaveBet[round.turn] <= round.highestChip, "Player has already bet more or equal to the highest bet");

            playerChipsRemaining[msg.sender][_tableId] -= callAmount;
            // round.pot += callAmount;
            round.chipsPlayersHaveBet[round.turn] += callAmount;

        } else if (_action == PlayerAction.Raise) {
            // in case of raising
            // deduct chips from the player's account
            // add those chips to the pot
            // update the highestChip for the round
            uint totalAmount = _raiseAmount + round.chipsPlayersHaveBet[round.turn];

            require(totalAmount > round.highestChip, "Raise amount not enough");
            require(playerChipsRemaining[msg.sender][_tableId] >= _raiseAmount, "Not enough chips to raise");
            emit PlayerRaise(_tableId, _raiseAmount);

            playerChipsRemaining[msg.sender][_tableId] -= _raiseAmount;
            round.highestChip = totalAmount;
            round.chipsPlayersHaveBet[round.turn] = totalAmount;

            // Set the initial next player to act after the raiser/re-raiser
            uint lastToActIndex = (round.turn - 1) % round.playersInRound.length;
            address lastToActPlayer = round.playersInRound[lastToActIndex];

            // Find next active player after the raiser/re-raiser
            while (playerStates[_tableId][table.totalHandsTillNow][lastToActPlayer] == PlayerState.Folded || playerStates[_tableId][table.totalHandsTillNow][lastToActPlayer] == PlayerState.AllIn) {
                lastToActIndex = (lastToActIndex - 1) % round.playersInRound.length;
                lastToActPlayer = round.playersInRound[lastToActIndex];
            }

            round.lastToAct = lastToActPlayer;

            // round.lastToAct = round.playersInRound[(round.turn - 1 + round.playersInRound.length) % round.playersInRound.length];

        } else if (_action == PlayerAction.Check) {
            // you can only check if all the other values in the round.chips array is zero
            // i.e nobody has put any money till now
            for (uint i =0; i < round.playersInRound.length; i++) {
                if (round.chipsPlayersHaveBet[i] > 0) {
                    require(round.chipsPlayersHaveBet[i] == 0, "Check not possible");
                }
            }

        } else if (_action == PlayerAction.Fold) {
            // in case of folding
            /// remove the player from the players & chips array for this round
            require(playerStates[_tableId][table.totalHandsTillNow][msg.sender] != PlayerState.Folded, "Player has already folded");
            playerStates[_tableId][table.totalHandsTillNow][msg.sender] = PlayerState.Folded;

            // _remove(round.turn, round.chipsPlayersHaveBet);
        }

        require(round.turn < round.playersInRound.length, "Invalid turn value before increment");
        require(round.turn < round.playersInRound.length, "Invalid turn value after increment");
        if (msg.sender == round.lastToAct) {
            advanceRoundState(_tableId);
        } else {
            _advanceTurn(_tableId);
        }
    }

    /// @dev method called to update the community cards for the next round
    function dealCommunityCards(uint _tableId, uint _roundId, uint8 _numCards) internal {
        Table storage table = tables[_tableId];
        Round storage round = rounds[_tableId][table.totalHandsTillNow];
        uint[] memory _cards = new uint[](_numCards);

        for (uint i=0; i<_numCards; i++) {
            _cards[i] = decks[_tableId][table.totalHandsTillNow][i + 2 * round.playersInRound.length + communityCards[_tableId][table.totalHandsTillNow].length];
            communityCards[_tableId][table.totalHandsTillNow].push(_cards[i]);
        }
        emit CommunityCardsDealt(_tableId, _roundId, _cards);
    }


    function _advanceTurn(uint _tableId) internal {
        Table storage table = tables[_tableId];
        Round storage round = rounds[_tableId][table.totalHandsTillNow];
        require(table.tableState == TableState.Active, "No active round");

        // Increment the turn index, skipping folded or all-in players
        do {
            round.turn = (round.turn + 1) % round.playersInRound.length;
        } while(playerStates[_tableId][table.totalHandsTillNow][round.playersInRound[round.turn]] == PlayerState.Folded || playerStates[_tableId][table.totalHandsTillNow][round.playersInRound[round.turn]] == PlayerState.AllIn);
    }

    function advanceRoundState(uint _tableId) internal {
        Table storage table = tables[_tableId];
        Round storage round = rounds[_tableId][table.totalHandsTillNow];
        require(round.isActive, "No active round");

        // Consolidate bets into the pot
        for (uint i = 0; i < round.playersInRound.length; i++) {
            emit ChipsIntoPot(_tableId, round.chipsPlayersHaveBet[i]);
            round.pot += round.chipsPlayersHaveBet[i];
            round.chipsPlayersHaveBet[i] = 0;
        }

        if(round.roundState == RoundState.Preflop) {
            round.roundState = RoundState.Flop;
            dealCommunityCards(_tableId, table.totalHandsTillNow, 3); // Deal 3 cards for the flop
        } 
        else if(round.roundState == RoundState.Flop) {
            round.roundState = RoundState.Turn;
            dealCommunityCards(_tableId, table.totalHandsTillNow, 1); // Deal 1 card for the turn
        } 
        else if(round.roundState == RoundState.Turn) {
            round.roundState = RoundState.River;
            dealCommunityCards(_tableId, table.totalHandsTillNow, 1); // Deal 1 card for the river
        }
        else if(round.roundState == RoundState.River) {
            round.roundState = RoundState.Showdown;
            // Trigger showdown logic
            // showdown();
            _reInitiateTable(table, _tableId);
        }

        emit RoundStateAdvanced(_tableId, round.roundState, round.pot);

        // Ensure there's more than one active or all-in player
        uint activePlayers = countActivePlayers(_tableId);
        require(activePlayers > 1, "Game should end as only one player remains");

        // Setting the next player to act and the last to act for postflop states (flop, turn, river):
        if (round.roundState != RoundState.Preflop) {
            _setCurrentTurnAndLastPlayerToAct(_tableId);
        }

        // Advance to the next player's turn
        round.highestChip = 0;
        _advanceTurn(_tableId);
    
        // You might also want to handle the transition from Showdown back to Preflop if another game begins.
    }


    function showdown(PlayerCardsPlainText[] memory _cards) external {
        // figure out showdown logic
    }


    function _setCurrentTurnAndLastPlayerToAct(uint _tableId) internal {
        Table storage table = tables[_tableId];
        Round storage round = rounds[_tableId][table.totalHandsTillNow];

        uint sbIndex = getSBIndex(_tableId, table.totalHandsTillNow);
        address smallBlindPlayer = round.playersInRound[sbIndex];

        uint lastToActIndex = (sbIndex == 0) ? round.playersInRound.length - 1 : sbIndex - 1;
        address lastToActPlayer = round.playersInRound[lastToActIndex];

        // Find first active player after the small blind for starting turn
        while (playerStates[_tableId][table.totalHandsTillNow][smallBlindPlayer] == PlayerState.Folded || playerStates[_tableId][table.totalHandsTillNow][smallBlindPlayer] == PlayerState.AllIn) {
            sbIndex = (sbIndex + 1) % round.playersInRound.length;
            smallBlindPlayer = round.playersInRound[sbIndex];
        }

        // Find last active player to the right of the small blind for lastToAct
        while (playerStates[_tableId][table.totalHandsTillNow][lastToActPlayer] == PlayerState.Folded || playerStates[_tableId][table.totalHandsTillNow][lastToActPlayer] == PlayerState.AllIn) {
            lastToActIndex = (lastToActIndex == 0) ? round.playersInRound.length - 1 : lastToActIndex - 1;
            lastToActPlayer = round.playersInRound[lastToActIndex];
        }

        round.lastToAct = lastToActPlayer;
        round.turn = sbIndex; // start the next round with this player
    }

    function _reInitiateTable(Table storage _table, uint _tableId) internal {

        _table.tableState = TableState.Inactive;
        _table.totalHandsTillNow += 1;
        delete communityCards[_tableId][_table.totalHandsTillNow]; // delete the community cards of the previous round
        delete decks[_tableId][_table.totalHandsTillNow];

        // initiate the first round
        Round storage round = rounds[_tableId][0];
        round.isActive = false;
        // TODO: Add logic to handle players that leave the round
        round.playersInRound = _table.players;
        round.highestChip = _table.bigBlindAmount;
        round.roundState = RoundState.Preflop;
    } 



    // ----------------------------------- HELPER FUNCTIONS ------------------------------------------

    function getSBIndex(uint tableId, uint roundIndex) public view returns(uint) {
        uint playersCount = tables[tableId].players.length;
        return (rounds[tableId][roundIndex].buttonIndex + 1) % playersCount;
    }

    function getBBIndex(uint tableId, uint roundIndex) public view returns(uint) {
        uint playersCount = tables[tableId].players.length;
        return (rounds[tableId][roundIndex].buttonIndex + 2) % playersCount;
    }

    function moveButton(uint tableId, uint roundIndex) internal {
        uint playersCount = tables[tableId].players.length;
        rounds[tableId][roundIndex].buttonIndex = (rounds[tableId][roundIndex].buttonIndex + 1) % playersCount;
    }

    // function _remove(uint index, address[] storage arr) internal {
    //     arr[index] = arr[arr.length - 1];
    //     arr.pop();
    // }

    function _remove(uint index, uint[] storage arr) internal {
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function countActivePlayers(uint _tableId) internal view returns(uint count) {
        Table storage table = tables[_tableId];
        Round storage round = rounds[_tableId][tables[_tableId].totalHandsTillNow];
        for (uint i = 0; i < round.playersInRound.length; i++) {
            if (playerStates[_tableId][table.totalHandsTillNow][round.playersInRound[i]] == PlayerState.Active || 
                playerStates[_tableId][table.totalHandsTillNow][round.playersInRound[i]] == PlayerState.AllIn) {
                count++;
            }
        }
        return count;
    }

    function getRound(uint _tableId, uint roundIndex) public view returns (Round memory) {
        return rounds[_tableId][roundIndex];
    }

    function getChipsBetArray(uint _tableId, uint roundIndex) public view returns (uint256[] memory) {
        return rounds[_tableId][roundIndex].chipsPlayersHaveBet;
    }

    // Helper function to get the current players of a table
    function getCurrentPlayers(uint _tableId) external view returns (address[] memory) {
        return tables[_tableId].players;
    }

    // Helper function to get the max number of players for a table
    function getMaxPlayers(uint _tableId) external view returns (uint) {
        return tables[_tableId].maxPlayers;
    }

    function getCurrentTableState(uint _tableId) public view returns (Table memory) {
        return tables[_tableId];
    }

    function getDeck(uint _tableId) public view returns (uint[] memory) {
        Table storage table = tables[_tableId];
        return decks[_tableId][table.totalHandsTillNow];
    }

    function getPlayerCardsEncrypted(address _player, uint _tableId, uint _handNum) public view returns (PlayerCardsEncrypted memory) {
        return playerCardsEncryptedDuringHand[_player][_tableId][_handNum];
    }

    function getPlayerState(uint tableId, uint totalHands, address playerAddress) public view returns (PlayerState) {
        return playerStates[tableId][totalHands][playerAddress];
    }



    // ----------------------------------- HELPER FUNCTIONS ------------------------------------------




    // ------------------------------ DEALING LOGIC ------------------------------------------

    function dealCard(uint _tableId) internal {
        Table storage table = tables[_tableId];
        uint card = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, _tableId, decks[_tableId][table.totalHandsTillNow].length))) % 52 + 1;
        decks[_tableId][table.totalHandsTillNow].push(card);
    }
    
    function setDeal(uint _tableId, uint256 n) public { 
        Table storage table = tables[_tableId];
        require(decks[_tableId][table.totalHandsTillNow].length + n <= 52, "Can't deal more cards than available in the deck");
        
        for (uint256 i = 0; i < n; i++) {
            dealCard(_tableId);
        }
    }
    
    // function checkDuplication(euint8 _card, uint _tableId) internal view returns (euint8) {
    //     euint8 total;
    //     for (uint8 i = 0; i < decks[_tableId].length; i++) {
    //         ebool duplicate = TFHE.eq(decks[_tableId][i], _card);
    //         total = TFHE.add(total, TFHE.cmux(duplicate, TFHE.asEuint8(1), TFHE.asEuint8(0)));
    //     }
    //     return total;
    // }

    // function dealCard(uint _tableId) public {
    //     euint8 card = TFHE.randEuint8();
    //     require(TFHE.decrypt(card) >= 0 && TFHE.decrypt(card) <= 52, "Card not in valid range");
    //     // require(card == TFHE.randEuint8(), "Card does not exist");
    //     if (decks[_tableId].length == 0) {
    //         decks[_tableId].push(card);
    //     } else if (TFHE.decrypt(checkDuplication(card, _tableId)) == 0) {
    //         decks[_tableId].push(card);
    //     }

    //     require(decks[_tableId].length > 0, "No cards exist on deck");
    // }

    // function setDeal(uint _tableId, uint256 n) public { //this count is 2n + 5 
    //     for (uint256 i = 0; i < n; i++) {
    //         dealCard(_tableId);
    //     }
    // }
    // ------------------------------ DEALING LOGIC ------------------------------------------




    // ----------------------------- TODO: ACTIVE PLAYER LOGIC -------------------------------
    // function addPlayer(uint tableId, address newPlayer) external {
    //     // Add to general list of players
    //     tables[tableId].players.push(newPlayer);

    //     // Add to list of active players for the current hand
    //     tables[tableId].activePlayers.push(newPlayer);
    // }

    // function removePlayer(uint tableId, address player) external {
    //     // Remove from general list of players (you might need a helper to find the index)
    //     uint index = findPlayerIndex(tableId, player);
    //     tables[tableId].players[index] = tables[tableId].players[tables[tableId].players.length - 1];
    //     tables[tableId].players.pop();

    //     // Remove from active players list
    //     uint activeIndex = findActivePlayerIndex(tableId, player);
    //     tables[tableId].activePlayers[activeIndex] = tables[tableId].activePlayers[tables[tableId].activePlayers.length - 1];
    //     tables[tableId].activePlayers.pop();

    //     // Handle button adjustment if the Button left
    //     if (tables[tableId].buttonIndex == activeIndex) {
    //         tables[tableId].buttonIndex = activeIndex % tables[tableId].activePlayers.length; // Move button to next player
    //     }
    // }

    // function findPlayerIndex(uint tableId, address player) internal view returns(uint) {
    //     for (uint i = 0; i < tables[tableId].players.length; i++) {
    //         if (tables[tableId].players[i] == player) {
    //             return i;
    //         }
    //     }
    //     revert("Player not found");
    // }

    // function findActivePlayerIndex(uint tableId, address player) internal view returns(uint) {
    //     for (uint i = 0; i < tables[tableId].activePlayers.length; i++) {
    //         if (tables[tableId].activePlayers[i] == player) {
    //             return i;
    //         }
    //     }
    //     revert("Active player not found");
    // }
    // ----------------------------- TODO: ACTIVE PLAYER LOGIC -------------------------------



    // /// @dev Starts a new round on a table
    // /// @param _tableId the unique id of the table
    // function startRound(uint _tableId) public {
    //     Table storage table = tables[_tableId];
    //     // require(table.state == TableState.Inactive, "Game already going on");
    //     // uint numOfPlayers = table.players.length;
    //     // require(numOfPlayers > 1, "ERROR : not enough players");
    //     table.state = TableState.Active;

    //     dealCards(_tableId);
    // }


    // function getDeck() public view returns (euint8[] memory) {
    //     return deck;
    // }

    // function getDeckLength() public view returns (uint) {
    //     return deck.length;
    // }

    // function joinGame() public {
    //     players[msg.sender].push(deck[deck.length - 2]);
    //     players[msg.sender].push(deck[deck.length - 1]);
    // }

    // function checkFirstCard(bytes32 publicKey, bytes calldata signature) public view onlySignedPublicKey(publicKey, signature) returns (bytes memory) {
    //     return  TFHE.reencrypt(players[msg.sender][0], publicKey, 0);
    // }
    // function checkSecondCard(bytes32 publicKey, bytes calldata signature) public view onlySignedPublicKey(publicKey, signature) returns (bytes memory) {
    //     return TFHE.reencrypt(players[msg.sender][1], publicKey, 0);
    // }

    // function test() public {
    //     euint8 card = TFHE.randEuint8();
    //     if (countPlain == 0) {
    //         deck[count] = card;
    //         count = TFHE.add(count, TFHE.asEuint8(1));
    //         countPlain += 1;
    //     } 
    //     euint8 total;
    //     for (uint8 i = 0; i < countPlain; i++) {
    //         ebool duplicate = TFHE.eq(deck[i], card);
    //         total = TFHE.add(total, TFHE.cmux(duplicate, TFHE.asEuint8(1), TFHE.asEuint8(0)));
    //     }
    //     count = TFHE.add(count, TFHE.asEuint8(1)); // add one
    // }

}   