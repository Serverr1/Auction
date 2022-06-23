
// SPDX-License-Identifier: MIT

pragma solidity>=0.8.0;


import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract Auction {
    // Variables

    // NFTs that are allowed to be exchanged in this contract
    mapping (address => bool) private _allowed_to_exchange;
    
    // allowed operators
    mapping (address => bool) private _privilleged_operators;
    // contract owner
    address public owner;
    
    // Accounts Balance
    mapping (address => uint256) public balance;

    // NFTs ownership history
    mapping (address => mapping (uint256 => address)) private _ownership;
     
    // NFTs auctions status
    mapping (address => mapping (uint256 => bool)) public onAuction;
    mapping (address => mapping (uint256 => uint256)) public current_auction_price;
    mapping (address => mapping (uint256 => address)) public current_bidder;
    mapping (address => mapping (uint256 => uint256)) public bid_end_time;
    
    // Events

    // Add/Remove operator event
    event OperatorCh(address operator, bool chType);
    // Ownership transfer
    event Owner(address newOwner);
    // Admin withdrawal
    event AdminWithDrawal(uint256 amount);
    
    // New Bid Event
    event NewBid(address NFTContract, uint256 NFTId, uint256 price, address bidder);
    // Auction over Event
    event AuctionOver(address NFTContract, uint256 NFTId, address bidder);
    // Force bid removal event
    event ForceRemoval(address Operator, address NFTContract, uint256 NFTId, address bidder);
    
    // Management interfaces:
    // constructor
    constructor() {
        owner = msg.sender;
        _privilleged_operators[msg.sender] = true;
    }
    
    modifier isOwner {
        require(msg.sender == owner, "Only the contract owner is allowed to do this.");
        _;
    }

    modifier isOperator {
        require(_privilleged_operators[msg.sender], "Denied");
        _;
    }

    modifier isNftOwner(address _NFTContract, uint _NFTId) {
        require(_ownership[_NFTContract][_NFTId] == msg.sender, "You must be the token's owner");
        _;
    }

    modifier isBidTimeOver(address _NFTContract, uint _NFTId) {
        require(block.number > bid_end_time[_NFTContract][_NFTId], "Auction still active.");
        _;
    }

    // Add an address to _privilleged_operators
    function addOperator(address operator) public isOwner {
        require(operator != address(0), "Enter a valid address");
        require(_privilleged_operators[operator] == false, "Operator was already added");
        _privilleged_operators[operator] = true;
        emit OperatorCh(operator, true);
    }
    
    // Remove someone from  _privilleged_operators
    function removeOperator(address operator) public isOwner {
        require(_privilleged_operators[operator], "Operator was already removed");
        _privilleged_operators[operator] = false;
        emit OperatorCh(operator, false);
    }
    
    // Transfer contract ownership, please be extremly careful while using this
    function transferOwnership(address newOwner) public isOwner {
        owner = newOwner;
        emit Owner(newOwner);
    }
    
   
    
    // Force cancel bid, to prevent DDoS by bidding from contract.
    function force_remove_auction(address NFTContract, uint256 NFTId) public {
        require(_privilleged_operators[msg.sender] == true, "Operators only");
        require(NFTId >= 0, "Enter a valid NFT id");
        // Remove bid and disable the nft's auction.
        onAuction[NFTContract][NFTId] = false;
        bid_end_time[NFTContract][NFTId] = 2**256 - 1;
        balance[current_bidder[NFTContract][NFTId]] += current_auction_price[NFTContract][NFTId];
        emit ForceRemoval(msg.sender, NFTContract, NFTId, current_bidder[NFTContract][NFTId]);
    }

    // Allow to auction specified token
    function allow(address NFTContract) public isOperator {
        require(_allowed_to_exchange[NFTContract] == false, "Tokens from this contract are already allowed to be exchanged");
        _allowed_to_exchange[NFTContract] = true;
    }

    function disallow(address NFTContract) public isOperator {
        require(_allowed_to_exchange[NFTContract], "Tokens from this contract are already not allowed to be exchanged");
        _allowed_to_exchange[NFTContract] = false;
    }
    
    // Withdrawal methods
    function withDraw(uint256 amount) public payable {
        require(balance[msg.sender] >= amount, "Balance not sufficient.");
        balance[msg.sender] -= amount;
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdrawing money failed");
    }

    function withDrawERC721(address NFTContract, uint256 NFTId) public payable isNftOwner(NFTContract, NFTId) isBidTimeOver(NFTContract, NFTId){
        require(onAuction[NFTContract][NFTId] == false, "The nft is still on auction, please claim it or wait for auction to be over");
        _ownership[NFTContract][NFTId] = address(0);
        ERC721(NFTContract).safeTransferFrom(address(this), msg.sender, NFTId);
        // Currently we do not support using approval mechinesm or paid transfer. This will be added later
    }

    function ownerWithdrawal(uint256 amount) public isOwner {
        (bool success,) = payable(msg.sender).call{value :amount}("");
        require(success, "Owner failed to withdraw money");
        emit AdminWithDrawal(amount);
    }

    // Auction Ops

    function startAuction(address NFTContract, uint256 NFTId, uint256 lowest_price) public {
        require(onAuction[NFTContract][NFTId] == false, "Already auctioned");
        // 1. Set lowest bid
        current_auction_price[NFTContract][NFTId] = lowest_price;
        current_bidder[NFTContract][NFTId] = address(0);
        // 2. Enable Auction
        onAuction[NFTContract][NFTId] = true;
        // 3. Set timestamp
        bid_end_time[NFTContract][NFTId] = block.number + 5760;
        // 4. Setting the ownership of the contract
        _ownership[NFTContract][NFTId] = msg.sender;
        
    }

    function bid(address NFTContract, uint256 NFTId) public payable {
        require(msg.sender != current_bidder[NFTContract][NFTId], "You can't outbid yourself");
        require(msg.value > current_auction_price[NFTContract][NFTId], "Must bid higher");
        require(onAuction[NFTContract][NFTId], "Not for Auction");
        // 0. Refund previous bidder
        balance[current_bidder[NFTContract][NFTId]] += current_auction_price[NFTContract][NFTId];
        // 1. Change price
        current_auction_price[NFTContract][NFTId] = msg.value;
        // 2. Change bidder
        current_bidder[NFTContract][NFTId] = msg.sender;
        // 3. Set timestamp
        bid_end_time[NFTContract][NFTId] = block.number + 5760;
    }

    function claimAuction(address NFTContract, uint256 NFTId) public isBidTimeOver(NFTContract, NFTId) {
        require(msg.sender == _ownership[NFTContract][NFTId] 
        || msg.sender == current_bidder[NFTContract][NFTId],
         "You are not allowed to do this.");
        // 1. End the auction
        onAuction[NFTContract][NFTId] = false;
        // 2. Transfer the value
        balance[_ownership[NFTContract][NFTId]] += current_auction_price[NFTContract][NFTId];
        // 3. Transfer the ownership
        _ownership[NFTContract][NFTId] = current_bidder[NFTContract][NFTId];
        emit AuctionOver(NFTContract, NFTId, current_bidder[NFTContract][NFTId]);
    }
    
   
}
