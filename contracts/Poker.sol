// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity >=0.8.13 <0.9.0;

import "fhevm/abstracts/EIP712WithModifier.sol";
import "fhevm/lib/TFHE.sol";
import "hardhat/console.sol";

contract Poker is EIP712WithModifier {

    constructor() EIP712WithModifier("Authorization token", "1") {
        owner = msg.sender;
    }

    address public owner;
    //mapping(uint8 => euint8) deck;
    euint8 count;
    uint8 countPlain;


    euint8[] public deck;
    mapping(address => euint8[]) players;
    address[] playersArray;

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

    event NewTableCreated(Table table);
    event NewBuyIn(uint tableId, address player, uint amount);
    event CardsDealt(PlayerCardHashes[] PlayerCardHashes, uint tableId);
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
    // struct PlayerCardHashes {
    //     bytes32 card1Hash;
    //     bytes32 card2Hash;
    // }
    struct PlayerCards {
        uint8 card1;
        uint8 card2;
    }


    Table public existingTable;
    bool public isTableInitialized = false;

    //keeps track of remaining chips of a player in a table.... player => remainingChips
    mapping(address => uint) public playerChips;

    // player => handNum => PlayerCards;
    mapping(address => mapping(uint => PlayerCards)) public playerCardsDuringHand;

    // maps roundNum to Round
    mapping(uint => Round) public rounds;

    // array of community cards
    uint8[] public communityCards;


    /// @dev Initialize the table, this should only be called once
    /// @param _buyInAmount The minimum amount of tokens required to enter the table
    /// @param _maxPlayers The maximum number of players allowed in this table
    /// @param _bigBlind The big blind amount for the table
    /// @param _token The token used to bet in this table
    function initializeTable(uint _buyInAmount, uint _maxPlayers, uint _bigBlind, address _token) external {
        require(!isTableInitialized, "Table already initialized");

        address [] memory empty;

        existingTable = Table({
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

        isTableInitialized = true;
        emit NewTableCreated(existingTable);
    }

    /// @dev a player can call to withdraw their chips from the table
    function withdrawChips(uint _amount) external {
        require(playerChips[msg.sender] >= _amount, "Not enough balance");
        playerChips[msg.sender] -= _amount;
        require(existingTable.token.transfer(msg.sender, _amount));
    }


    /// @dev players have to call this to buy ina nd enter the table
    /// @param _amount The amount of tokens to buy in the table. (must be >= min table buy in amount)
    /// TODO: add logic to allow existing player at table to re-buy in
    function buyIn(uint _amount) public {
        require(isTableInitialized, "Table has not been initialized");

        Table storage table = existingTable;

        require(_amount >= existingTable.buyInAmount, "Not enough buyInAmount");
        require(existingTable.players.length < existingTable.maxPlayers, "Table is full");

        // transfer player's buy in to contract
        require(existingTable.token.transferFrom(msg.sender, address(this), _amount));
        playerChips[msg.sender] += _amount;

        // add player to the table
        existingTable.players.push(msg.sender);

        emit NewBuyIn(_tableId, msg.sender, _amount);
    }


    function dealCards() public {
        Table storage table = existingTable;
        uint numOfPlayers = table.players.length;

        require(table.state == TableState.Inactive, "Game already going on");
        require(numOfPlayers > 1, "ERROR : not enough players");
        table.state = TableState.Active;

        setDeal(2 * numOfPlayers + 5); // assuming 2 cards per player and 5 community cards

        Round storage round = rounds[0];

        round.state = true;
        round.players = table.players;
        round.highestChip = table.bigBlind;

        for (uint i = 0; i < numOfPlayers; i++) {
            if (i == (numOfPlayers - 1)) { // last player, small blind
                round.chips[i] = table.bigBlind / 2;
                playerChips[round.players[i]] -= table.bigBlind / 2;
            } else if (i == (numOfPlayers - 2)) { // second to last player, big blind
                round.chips[i] = table.bigBlind;
                playerChips[round.players[i]] -= table.bigBlind;
            }

            // Save the encrypted card for each player
            PlayerCards memory playerCards;
            playerCards.card1 = deck[2 * i];
            playerCards.card2 = deck[2 * i + 1];
            playerCardsDuringHand[table.players[i]][table.totalHands] = playerCards;
        }

        table.pot += table.bigBlind + (table.bigBlind / 2);
        // emit CardsDealt(_playerCards); // emit encrypted player cards

    }


    function checkDuplication(euint8 _card) internal view returns (euint8) {
        euint8 total;
        for (uint8 i = 0; i < deck.length; i++) {
            ebool duplicate = TFHE.eq(deck[i], _card);
            total = TFHE.add(total, TFHE.cmux(duplicate, TFHE.asEuint8(1), TFHE.asEuint8(0)));
        }
        return total;
    }

    function dealCard() public {

        Table storage table = existingTable;


        euint8 card = TFHE.randEuint8();
        if (deck.length == 0) {
            deck.push(card);
        } else if (TFHE.decrypt(checkDuplication(card)) == 0) {
            deck.push(card);
        }
    }

    function setDeal(uint8 n) public { //this count is 2n + 5 
        for (uint8 i = 0; i < n; i++) {
            dealCard();
        }
    } 


     /// @param _raiseAmount only required in case of raise. Else put zero. This is the amount you are putting in addition to what you have already put in this round
    function playHand(PlayerAction _action, uint _raiseAmount) external {
        Table storage table = existingTable;
        require(table.state == TableState.Active, "No active round");

        Round storage round = rounds[table.currentRound];
        print(round);
        require(round.players[round.turn] == msg.sender, "Not your turn");

        if (_action == PlayerAction.Call) {
            // in case of calling
            // deduct chips from user
            // add chips to pot
            // keep the player in the round

            uint callAmount = round.highestChip - round.chips[round.turn];

            chips[msg.sender] -= callAmount;
            table.pot += callAmount;
        } else if (_action == PlayerAction.Raise) {
            // add raise logic
        } else if (__action == PlayerAction.Check) {
            // add check logic
        } else if (_action == PlayerAction.Fold) {
            // in case of folding
            /// remove the player from the players & chips array for this round
            _remove(round.turn, round.players);
            _remove(round.turn, round.chips);
        }
    }


    function showdown(PlayerCards[] memory _cards) external onlyOwner {
        // figure out showdown logic
    }

    /// @dev method called to update the community cards for the next round
    /// @param _cards Code of each card(s), (as per the PokerHandUtils Library)
    function dealCommunityCards(uint _roundId, uint8[] memory _cards) external onlyOwner {
        for (uint i=0; i<_cards.length; i++) {
            communityCards.push(_cards[i]);
        }
        emit CommunityCardsDealt(_tableId, _roundId, _cards);
    }

    function getDeck() public view returns (euint8[] memory) {
        return deck;
    }

    function getDeckLength() public view returns (uint) {
        return deck.length;
    }

    function joinGame() public {
        players[msg.sender].push(deck[deck.length - 2]);
        players[msg.sender].push(deck[deck.length - 1]);
    }

    function checkFirstCard(bytes32 publicKey, bytes calldata signature) public view onlySignedPublicKey(publicKey, signature) returns (bytes memory) {
        return  TFHE.reencrypt(players[msg.sender][0], publicKey, 0);
    }
    function checkSecondCard(bytes32 publicKey, bytes calldata signature) public view onlySignedPublicKey(publicKey, signature) returns (bytes memory) {
        return  TFHE.reencrypt(players[msg.sender][1], publicKey, 0);
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