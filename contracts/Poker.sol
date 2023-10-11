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
    // euint8 count;
    // uint8 countPlain;


    enum TableState {
        Active,
        Inactive,
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

    struct Table {
        TableState state;
        uint totalHands; //total hands till now
        uint currentRound; // index of curr round
        uint buyInAmount;
        uint maxPlayers;
        address[] players;
        uint pot;
        uint bigBlind;
        IERC20 token; // token used to bet and play
    }
    struct Round {
        bool state; // state of the round, if active or not
        uint turn; // index of the players array, who has the current turn
        address [] players; // players still in the round (not folded)
        uint highestChip; // current highest chip to be called
        uint[] chips; // array of chips each player has put in, compared with highestChip to see if player has to call again
    }
    struct PlayerCardsEncrypted {
        euint8 card1Encrypted;
        euint8 card2Encrypted;
    }
    struct PlayerCardsPlainText {
        uint8 card1;
        uint8 card2;
    }


    // bool public isTableInitialized = false;
    uint public totalTables;

    // id => Table
    mapping(uint => Table) public tables;

    // each tableId maps to a deck
    // tableId => deck
    mapping(uint => euint8[]) public decks;

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
            state: TableState.Inactive,
            totalHands: 0,
            currentRound: 0,
            buyInAmount: _buyInAmount, 
            maxPlayers: _maxPlayers,
            players: empty, // initializing with empty dynamic array
            pot: 0,
            bigBlind: _bigBlind,
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
        require(table.token.transferFrom(msg.sender, address(this), _amount));
        playerChipsRemaining[msg.sender][_tableId] += _amount;

        // add player to the table
        table.players.push(msg.sender);

        emit NewBuyIn(_tableId, msg.sender, _amount);
    }


    function dealCards(uint _tableId) public {
        Table storage table = tables[_tableId];
        uint numOfPlayers = table.players.length;
        require(table.state == TableState.Inactive, "Game already going on");
        require(numOfPlayers > 1, "ERROR : not enough players");
        table.state = TableState.Active;

        setDeal(_tableId, 2 * numOfPlayers + 5); // assuming 2 cards per player and 5 community cards

        Round storage round = rounds[_tableId][0];

        round.state = true;
        round.players = table.players;
        round.highestChip = table.bigBlind;

        for (uint i = 0; i < numOfPlayers; i++) {
            if (i == (numOfPlayers - 1)) { // last player, small blind
                round.chips[i] = table.bigBlind / 2;
                playerChipsRemaining[round.players[i]][_tableId] -= table.bigBlind / 2;
            } else if (i == (numOfPlayers - 2)) { // second to last player, big blind
                round.chips[i] = table.bigBlind;
                playerChipsRemaining[round.players[i]][_tableId] -= table.bigBlind;
            }

            // Save the encrypted card for each player
            PlayerCardsEncrypted[] memory playerCardsEncrypted;
            // console.log("Player ", numOfPlayers , " Deck: ", decks[_tableId]);
            playerCardsEncrypted[i].card1Encrypted = decks[_tableId][2 * i];
            playerCardsEncrypted[i].card2Encrypted = decks[_tableId][2 * i + 1];
            playerCardsEncryptedDuringHand[table.players[i]][_tableId][table.totalHands] = playerCardsEncrypted[i];
            // console.log("Player Cards Encrypted: ", playerCardsEncrypted);

            emit PlayerCardsDealt(playerCardsEncrypted, _tableId); // emit encrypted player cards
        }

        table.pot += table.bigBlind + (table.bigBlind / 2);

    }


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
        if (decks[_tableId].length == 0) {
            decks[_tableId].push(card);
        } else if (TFHE.decrypt(checkDuplication(card, _tableId)) == 0) {
            decks[_tableId].push(card);
        }
    }

    function setDeal(uint _tableId, uint256 n) public { //this count is 2n + 5 
        for (uint256 i = 0; i < n; i++) {
            dealCard(_tableId);
        }
    } 


     /// @param _raiseAmount only required in case of raise. Else put zero. This is the amount you are putting in addition to what you have already put in this round
    function playHand(uint _tableId, PlayerAction _action, uint _raiseAmount) external {
        Table storage table = tables[_tableId];
        require(table.state == TableState.Active, "No active round");

        Round storage round = rounds[_tableId][table.currentRound];
        require(round.players[round.turn] == msg.sender, "Not your turn");

        if (_action == PlayerAction.Call) {
            // in case of calling
            // deduct chips from user
            // add chips to pot
            // keep the player in the round

            uint callAmount = round.highestChip - round.chips[round.turn];

            playerChipsRemaining[msg.sender][_tableId] -= callAmount;
            table.pot += callAmount;

        } else if (_action == PlayerAction.Raise) {
            // in case of raising
            // deduct chips from the player's account
            // add those chips to the pot
            // update the highestChip for the round
            uint totalAmount = _raiseAmount + round.chips[round.turn];
            require(totalAmount > round.highestChip, "Raise amount not enough");
            require(playerChipsRemaining[msg.sender][_tableId] >= _raiseAmount);
            playerChipsRemaining[msg.sender][_tableId] -= _raiseAmount;
            table.pot += _raiseAmount;
            round.highestChip = totalAmount;

        } else if (_action == PlayerAction.Check) {
            // add check logic
            
        } else if (_action == PlayerAction.Fold) {
            // in case of folding
            /// remove the player from the players & chips array for this round
            _remove(round.turn, round.players);
            _remove(round.turn, round.chips);
        }
    }


    function showdown(PlayerCardsPlainText[] memory _cards) external {
        // figure out showdown logic
    }

    /// @dev method called to update the community cards for the next round
    /// @param _cards Code of each card(s), (as per the PokerHandUtils Library)
    function dealCommunityCards(uint _tableId, uint _roundId, uint8[] memory _cards) external {
        for (uint i=0; i<_cards.length; i++) {
            communityCards[_tableId].push(_cards[i]);
        }
        emit CommunityCardsDealt(_tableId, _roundId, _cards);
    }

    function _reInitiateTable(Table storage _table, uint _tableId) internal {

        _table.state = TableState.Inactive;
        _table.totalHands += 1;
        _table.currentRound = 0;
        _table.pot = 0;
        delete communityCards[_tableId]; // delete the community cards of the previous round

        // initiate the first round
        Round storage round = rounds[_tableId][0];
        round.state = true;
        round.players = _table.players;
        round.highestChip = _table.bigBlind;
    } 

    function _remove(uint index, address[] storage arr) internal {
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }

    function _remove(uint index, uint[] storage arr) internal {
        arr[index] = arr[arr.length - 1];
        arr.pop();
    }


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