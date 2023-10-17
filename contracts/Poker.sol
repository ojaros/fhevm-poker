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

    event NewTableCreated(uint tableId, Table table);
    event NewBuyIn(uint tableId, address player, uint amount);
    event PlayerCardsDealt(PlayerCardsEncrypted[] PlayerCardsEncrypted, uint tableId);
    event RoundOver(uint tableId, uint round);
    event CommunityCardsDealt(uint tableId, uint roundId, uint8[] cards);
    event TableShowdown(uint tableId);
    // event DebugPlayerCards(uint256 indexed tableId, uint card1Encrypted, uint card2Encrypted);
    event DebugPlayerCards(uint256 indexed tableId, euint8 card1Encrypted, euint8 card2Encrypted);
    event DebugDeck(uint cardEncrypted);


    struct Table {
        TableState tableState;
        uint totalHands; //total hands till now
        uint currentRoundIndex; // index of curr round
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
    }
    struct PlayerCardsEncrypted {
        euint8 card1Encrypted;
        euint8 card2Encrypted;
    }
    // struct PlayerCardsEncrypted {
    //     uint card1Encrypted;
    //     uint card2Encrypted;
    // }
    struct PlayerCardsPlainText {
        uint8 card1;
        uint8 card2;
    }

    uint public totalTables = 0;

    // id => Table
    mapping(uint => Table) public tables;

    // each tableId maps to a deck
    // tableId => deck
    mapping(uint => euint8[]) public decks;
    // mapping(uint => uint[]) public decks;

    // mapping(address => euint8[]) players;

    //keeps track of remaining chips of a player in a table.... player => tableId => remainingChips
    mapping(address => mapping(uint => uint)) public playerChipsRemaining;

    // player => tableId => handNum => PlayerCards;
    mapping(address => mapping(uint => mapping(uint => PlayerCardsEncrypted))) public playerCardsEncryptedDuringHand;

    // maps roundNum to Round
    // tableId => roundNum => Round
    mapping(uint => mapping(uint => Round)) public rounds;

    // array of community cards
    // tableId => int[8] community cards
    mapping(uint => uint8[]) public communityCards;


    /// @dev Initialize the table, this should only be called once
    /// @param _buyInAmount The minimum amount of tokens required to enter the table
    /// @param _maxPlayers The maximum number of players allowed in this table
    /// @param _bigBlind The big blind amount for the table
    /// @param _token The token used to bet in this table
    function initializeTable(uint _buyInAmount, uint _maxPlayers, uint _bigBlind, address _token) external {

        address [] memory empty;

        tables[totalTables] = Table({
            tableState: TableState.Inactive,
            totalHands: 0,
            currentRoundIndex: 0,
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

        Round storage round = rounds[_tableId][table.totalHands];

        round.isActive = true;
        round.roundState = RoundState.Preflop;
        // TODO: Add logic to handle players at the table, but sitting out this round
        round.playersInRound = table.players;
        round.highestChip = table.bigBlindAmount;
        round.chipsPlayersHaveBet = new uint256[](numOfPlayers);  // Initialize chips array with zeros for each player
        round.turn = (getBBIndex(_tableId, table.totalHands) + 1) % numOfPlayers;

        PlayerCardsEncrypted[] memory playerCardsEncryptedArray = new PlayerCardsEncrypted[](numOfPlayers);

        for (uint i = 0; i < numOfPlayers; i++) {
            require(i < round.chipsPlayersHaveBet.length, "round.chips out of bounds");

            if (i == (getSBIndex(_tableId, table.totalHands))) { // last player, small blind
                // Ensure that the operation doesn't lead to underflows
                require(playerChipsRemaining[round.playersInRound[i]][_tableId] >= table.bigBlindAmount / 2, "Underflow for small blind");
                
                round.chipsPlayersHaveBet[i] = table.bigBlindAmount / 2;
                playerChipsRemaining[round.playersInRound[i]][_tableId] -= table.bigBlindAmount / 2;
                
            } else if (i == (getBBIndex(_tableId, table.totalHands))) { // second to last player, big blind
            
                // Ensure that the operation doesn't lead to underflows
                require(playerChipsRemaining[round.playersInRound[i]][_tableId] >= table.bigBlindAmount, "Underflow for big blind");
                
                round.chipsPlayersHaveBet[i] = table.bigBlindAmount;
                playerChipsRemaining[round.playersInRound[i]][_tableId] -= table.bigBlindAmount;
            }

            // Ensure decks[_tableId] has enough elements
            require(2 * i + 1 < decks[_tableId].length, "decks out of bounds");
            
            // Save the encrypted card for each player
            playerCardsEncryptedArray[i].card1Encrypted = decks[_tableId][2 * i];
            playerCardsEncryptedArray[i].card2Encrypted = decks[_tableId][2 * i + 1];

            emit DebugPlayerCards(_tableId, playerCardsEncryptedArray[i].card1Encrypted, playerCardsEncryptedArray[i].card2Encrypted);
            playerCardsEncryptedDuringHand[table.players[i]][_tableId][table.totalHands] = playerCardsEncryptedArray[i];

        }

        emit PlayerCardsDealt(playerCardsEncryptedArray, _tableId); // emit encrypted player cards for all players at once

        round.pot += table.bigBlindAmount + (table.bigBlindAmount / 2);

    }


    /// @param _raiseAmount only required in case of raise. Else put zero. This is the amount you are putting in addition to what you have already put in this round
    function playHand(uint _tableId, PlayerAction _action, uint _raiseAmount) external {
        Table storage table = tables[_tableId];
        Round storage round = rounds[_tableId][table.currentRoundIndex];

        require(table.tableState == TableState.Active, "Table is inactive");
        require(round.isActive, "No active round");
        require(round.playersInRound[round.turn] == msg.sender, "Not your turn");

        if (_action == PlayerAction.Call) {
            // in case of calling
            // deduct chips from user
            // add chips to pot
            // keep the player in the round

            uint callAmount = round.highestChip - round.chipsPlayersHaveBet[round.turn];

            playerChipsRemaining[msg.sender][_tableId] -= callAmount;
            round.pot += callAmount;

        } else if (_action == PlayerAction.Raise) {
            // in case of raising
            // deduct chips from the player's account
            // add those chips to the pot
            // update the highestChip for the round
            uint totalAmount = _raiseAmount + round.chipsPlayersHaveBet[round.turn];
            require(totalAmount > round.highestChip, "Raise amount not enough");
            require(playerChipsRemaining[msg.sender][_tableId] >= _raiseAmount, "Not enough chips to raise");
            playerChipsRemaining[msg.sender][_tableId] -= _raiseAmount;
            round.pot += _raiseAmount;
            round.highestChip = totalAmount;

        } else if (_action == PlayerAction.Check) {
            // you can only check if all the other values in the round.chips array is zero
            // i.e nobody has put any money till now
            for (uint i =0; i < round.playersInRound.length; i++) {
                if (round.chipsPlayersHaveBet[i] > 0) {
                    require(false, "Check not possible");
                }
            }

        } else if (_action == PlayerAction.Fold) {
            // in case of folding
            /// remove the player from the players & chips array for this round
            _remove(round.turn, round.playersInRound);
            _remove(round.turn, round.chipsPlayersHaveBet);
        }

        _advanceTurn(_tableId);
    }


    function _advanceTurn(uint _tableId) internal {
        Table storage table = tables[_tableId];
        require(table.tableState == TableState.Active, "No active round");
        Round storage round = rounds[_tableId][table.currentRoundIndex];
        // increment the turn index
        round.turn = (round.turn + 1) % round.playersInRound.length;
    }


    function showdown(PlayerCardsPlainText[] memory _cards) external {
        // figure out showdown logic
    }

    /// @dev method called to update the community cards for the next round
    /// @param _cards Code of each card(s)
    function dealCommunityCards(uint _tableId, uint _roundId, uint8[] memory _cards) external {
        for (uint i=0; i<_cards.length; i++) {
            communityCards[_tableId].push(_cards[i]);
        }
        emit CommunityCardsDealt(_tableId, _roundId, _cards);
    }

    function _reInitiateTable(Table storage _table, uint _tableId) internal {

        _table.tableState = TableState.Inactive;
        _table.totalHands += 1;
        _table.currentRoundIndex = 0;
        delete communityCards[_tableId]; // delete the community cards of the previous round

        // initiate the first round
        Round storage round = rounds[_tableId][0];
        round.isActive = true;
        round.playersInRound = _table.players;
        round.highestChip = _table.bigBlindAmount;
        round.roundState = RoundState.Preflop;
    } 

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

    function _remove(uint index, address[] storage arr) internal {
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function _remove(uint index, uint[] storage arr) internal {
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function getRoundPlayersInRound(uint _tableId, uint roundIndex) public view returns (address[] memory) {
        return rounds[_tableId][roundIndex].playersInRound;
    }

    function getChipsBetArray(uint _tableId, uint roundIndex) public view returns (uint256[] memory) {
        return rounds[_tableId][roundIndex].chipsPlayersHaveBet;
    }


    // ------------------------------ DEALING LOGIC ------------------------------------------
    function checkDuplication(euint8 _card, uint _tableId) internal view returns (euint8) {
        euint8 total;
        for (uint8 i = 0; i < decks[_tableId].length; i++) {
            ebool duplicate = TFHE.eq(decks[_tableId][i], _card);
            total = TFHE.add(total, TFHE.cmux(duplicate, TFHE.asEuint8(1), TFHE.asEuint8(0)));
        }
        return total;
    }

    function dealCard(uint _tableId) public {
        euint8 card = TFHE.randEuint8();
        require(TFHE.decrypt(card) >= 0 && TFHE.decrypt(card) <= 52, "Card not in valid range");
        // require(card == TFHE.randEuint8(), "Card does not exist");
        if (decks[_tableId].length == 0) {
            decks[_tableId].push(card);
        } else if (TFHE.decrypt(checkDuplication(card, _tableId)) == 0) {
            decks[_tableId].push(card);
        }

        require(decks[_tableId].length > 0, "No cards exist on deck");
    }

    function setDeal(uint _tableId, uint256 n) public { //this count is 2n + 5 
        for (uint256 i = 0; i < n; i++) {
            dealCard(_tableId);
        }
    }


    // function dealCard(uint _tableId) internal {
    //     uint card = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, _tableId, decks[_tableId].length))) % 52 + 1;
    //     decks[_tableId].push(card);
    // }
    
    // function setDeal(uint _tableId, uint256 n) public { 
    //     require(decks[_tableId].length + n <= 52, "Can't deal more cards than available in the deck");
        
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