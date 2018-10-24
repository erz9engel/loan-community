pragma solidity ^0.4.25;

/*
This is a smart contract that represents work of Credit Union.
Loan Community is a form of cooperation where every round each member pays 
a constant contribution and than by placing bids Community decides who is going
to receive gathered ammount. For security reasons payment is divided in two 
parts. Contract finishes after passing number of rounds that is equal to 
initial number of community members. If a certain member will not pay his 
contribution he will be banned, and will not be able to receive any payments
from Community also his payed contributions and placed bids will be divided 
between other community members after the last round.

This contract was made in EDUCATIONAL PURPOSES.

DO NOT USE IT, IT MAY CONTAIN BUGS AND VULNERABILITIES!

@author Yaroslav Biletskyi 
*/


contract LoanCommunity {
    struct Member{
        uint allBids;
        uint currentBid;
        uint contributions;
        bool banned;
        bool exists;
        bool gotPayed;
    }
    address[] indexes; // Is used for mapping iteration
    uint round;
    uint communitySize;
    address payable communityManager;
    uint insurance; // Represents smart contract balance
    bool isBidTime;
    uint endRound;
    uint biddingTime;
    uint roundTime;
    uint contributionSize; // Amount of sum each member has to pay each round
    
    mapping(address => Member) members;
    
    constructor(
        uint _biddingTime,
        uint _roundTime,
        uint _contributionSize
    )
        public
    {
        communityManager = msg.sender;
        isBidTime = false;
        endRound = 0;
        biddingTime = _biddingTime;
        roundTime = _roundTime;
        contributionSize =_contributionSize;
        round = 0;
        insurance = 0;
        communitySize = 0;
    }
    function joinCommunity() public {
        require(round == 0, "Community already started");
        require(!members[msg.sender].exists, "You are already in Community");
        members[msg.sender] = Member(0, 0, 0, false, true, false);
        indexes.push(msg.sender);
        communitySize++;
    }
    
    function payContribution() public payable {
        require(members[msg.sender].exists, 
                "Only community members can pay contribution"
                );
        require(!isBidTime, "It is time for biding now");
        require(round > 0, "Community hasn't started yet");
        members[msg.sender].contributions = members[msg.sender].contributions 
                                            + msg.value;
        insurance = insurance + msg.value;
    }
    
    function placeBid() public payable {
        require(members[msg.sender].exists,
                "Only community members can place bids"
                );
        require(isBidTime, "It is not time for biding now");
        members[msg.sender].currentBid = members[msg.sender].currentBid
                                            + msg.value;
        insurance = insurance + msg.value;
    }
    
    function startBidding() public {
        require(msg.sender == communityManager,
                "Only community manager can open bidding"
                );
        require(round > 0, "Community isn't formed yet");
        require(now > endRound, "Time for paying contributes isn't over");
        isBidTime = true;
        for (uint i=0; i<communitySize; i++) {
            if (members[indexes[i]].contributions < round * contributionSize){
                members[indexes[i]].banned = true;
            }
        }
        endRound = now + biddingTime;
    }
    
    function newRound() public {
        require(msg.sender == communityManager,
                "Only community manager can start new round"
                );
        require(communitySize>2, 
                "There is no sense in running community for less than 3 members"
                );
        require(round == 0 || (isBidTime && now > endRound), 
                "Time for bidding isn't over");
        endRound = now + roundTime;
        if (round==0) {
            round++;
        } else if (round < communitySize && readyToPayReward()){
            isBidTime = false;
            uint maxBid = 0;
            uint winnerCount = 0;
            for (uint i=0; i<communitySize; i++) {
                bool isMaxBid = members[indexes[i]].currentBid == maxBid;
                bool notPayed = !members[indexes[i]].gotPayed;
                bool notBanned = !members[indexes[i]].banned;
                if (members[indexes[i]].currentBid > maxBid){
                    maxBid = members[indexes[i]].currentBid;
                    winnerCount = 0;
                }
                if (isMaxBid && notPayed && notBanned){
                    winnerCount = winnerCount + 1;
                }
            }
            
            // In case when there are more than one highest bid, winner will
            // be chosen randomly
            uint random = uint(blockhash(block.number-1)) % winnerCount;
            winnerCount = 0;
            address luckyRoundWinner;
            for (uint i=0; i<communitySize; i++) {
                bool isMaxBid = members[indexes[i]].currentBid == maxBid;
                bool notPayed = !members[indexes[i]].gotPayed;
                bool notBanned = !members[indexes[i]].banned;
                if (isMaxBid && notPayed && notBanned){
                    if (winnerCount==random){
                        luckyRoundWinner = indexes[i];
                    } else {
                        winnerCount = winnerCount + 1;
                    }
                } 
                members[indexes[i]].allBids = members[indexes[i]].allBids 
                                + members[indexes[i]].currentBid;
                members[indexes[i]].currentBid = 0;
            }
            require(luckyRoundWinner.call.value(contributionSize/2));
            insurance -= contributionSize/2;
            members[luckyRoundWinner].gotPayed = true;
        } else if (round > communitySize){
            lastRound();
        }
    }

    // Payment will only be possible, when balance is enough to cover possible
    // loss from one or more members to leave community
    function readyToPayReward() private view returns (bool) {
        uint payedRound = 0;
        for (uint i=0; i<communitySize; i++) {
            if (members[indexes[i]].gotPayed) payedRound++;
        }
        uint expenses = payedRound * (communitySize - round) * contributionSize
                        + contributionSize / 2;   
        if (insurance > expenses){
            return true;
        } else {
            return false;
        }
    }
    
    function lastRound() public {
        require(msg.sender == communityManager,
                "Only community manager can initiate this"
                );
        uint sumOfBiddersLeft = 0;
        for (uint i=0; i<communitySize; i++) {
            bool notPayed = !members[indexes[i]].gotPayed;
            bool notBanned = !members[indexes[i]].banned;
            
            // transfering second part of reward for those, who payed all
            // the contributions
            if (notBanned) {
                require(indexes[i].call.value(contributionSize/2));
                insurance = insurance - contributionSize/2;
                // Returning overpayed contribution if any
                if (members[indexes[i]].contributions > contributionSize * communitySize){
                    require(indexes[i].call.value(members[indexes[i]].contributions 
                                            - contributionSize * communitySize));
                    insurance = insurance - (members[indexes[i]].contributions 
                                - contributionSize * communitySize);
                }
                sumOfBiddersLeft = sumOfBiddersLeft + members[indexes[i]].allBids;
            }
            
            // transfering first part of reward for those who haven't received it yet
            if (notPayed) {
                require(indexes[i].call.value(contributionSize/2));
                insurance = insurance - contributionSize/2;
            }
        }
        
        // 5% commision fee for Community manager
        uint returnBidAmount = insurance * 95 / 100; 

        // Distribution of remaining amount proportionally to the bids placed
        for (uint i=0; i<communitySize; i++) { 
            if (!members[indexes[i]].banned) {
                uint sumToReturn = members[indexes[i]].allBids 
                                    / sumOfBiddersLeft * returnBidAmount;
                require(indexes[i].call.value(sumToReturn));
                insurance = insurance - sumToReturn;
            }
        }
        selfdestruct(communityManager);
    }
}
