/*
*
*  This is a cadence implementation of a generic auction
*
*  This contract allows anyone to create an auction in their account
*  without having to deploy their own smart contract.
*  In order to create an auction, you create an Auction Resource with
*  your desired parameters and prize and create a public `AuctionPublic`
*  reference to it that anyone can use to register.
*
*  To bid on an existing auction, a user must create an AuctionParticipant
*  resource in their account, deposit their bid into the participant resource,
*  create a private capability to their participant resource,
*  and then call the createBid() function on the auction they want to participate
*  in, providing their capability as an argument to the function.
*
*  This capability is used to query the bidder's bid balance and used to deposit
*  the prize at the end of the auction if the bidder wins.
*
*  The design of this has multiple benefits.
*
*  1. It allows anyone to run any number of auctions from a single account
*     without having to deploy any smart contracts.
*  2. All parties in the auction store their own data in their own accounts,
*     meaning that they only have to pay storage fees for the data they own.
*  3. Anyone can run or participate in auctions without having
*     to trust the owner of the auction or the other participants, because 
*     the worst that a malicious owner could do is destroy or move the auction resource.
*     If this happens, the participants can still just withdraw their fungible tokens
*     after the original end time of the auction. 
*  4. Settling the auction also happens trustlessly because anyone can call it through
*     the public capability. Additionally, it is not able to panic from a malicious
*     particpant because if the settle function detects that a capability
*     has been modified, it will simply ignore that bidder and reward the prize
*     to the next highest bidder.
*  5. Participants can increase their bid during the auction without having to
*     create a new Participant resource
*
*  One downside to this implementation is that participant's bids 
*  are not allowed to be withdrawn until after the auction is over.
*  This is because when the auction is settled, there is a chance that the winner's
*  bid capability has been modified, in which case the prize
*  will go to the next highest bidder.
*
*/

import NonFungibleToken from "NonFungibleToken"
import FungibleToken from "FungibleToken"
import MetadataViews from "MetadataViews"
import ViewResolver from "ViewResolver"

pub contract GenericAuction {

    /// The interface that an account can use to expose
    /// metadata and the createBid method to the public
    pub resource interface AuctionPublic {

        pub var fungibleTokenType: Type
        pub var winningBidID: UInt64
        pub var winningBidAmount: UFix64
        pub var timeBuffer: UFix64
        pub var reservePrice: UFix64
        pub var minBidIncrementPercentage: UFix64
        pub let startTime: UFix64
        pub var endTime: UFix64
        pub var paused: Bool

        pub fun createBid(participantCap: Capability<&AuctionParticipant>)
    }

    /// Resource to hold and manage an auction
    /// The admin of the auction can store this in their
    /// acount and publish the AuctionPublic capability
    /// to start an auction
    pub resource Auction: AuctionPublic {

        /// The object being auctioned
        access(account) var objectForAuction: @NonFungibleToken.NFT?

        /// The type of fungible token that is used for this auction
        pub var fungibleTokenType: Type

        /// The bids that have been submitted
        /// The key is the UUID of the AuctionParticipant resource 
        /// that was used to submit the bid
        access(self) var bids: {UInt64: Capability<&AuctionParticipant>}

        /// The UUID of the resource that submitted the current winning bid
        pub var winningBidID: UInt64

        /// The amount of FLOW that is part of the current winning bid
        pub var winningBidAmount: UFix64
        
        /// The minimum amount of time left in an auction after a new bid is created
        pub var timeBuffer: UFix64

        /// The minimum price accepted in an auction
        pub var reservePrice: UFix64

        /// The minimum percentage difference between the last bid amount and the current bid
        pub var minBidIncrementPercentage: UFix64

        /// UNIX start time of the auction
        pub let startTime: UFix64

        /// UNIX end time of the auction
        pub var endTime: UFix64

        pub var paused: Bool

        init(
            objectForAuction: @NonFungibleToken.NFT,
            fungibleTokenType: Type,
            timeBuffer: UFix64,
            reservePrice: UFix64,
            minBidIncrementPercentage: UFix64,
            startTime: UFix64,
            endTime: UFix64
        ) {
            self.objectForAuction <- objectForAuction
            self.fungibleTokenType = fungibleTokenType
            self.bids = {}
            self.winningBidID = 0
            self.winningBidAmount = 0.0
            self.timeBuffer = timeBuffer
            self.reservePrice = reservePrice
            self.minBidIncrementPercentage = minBidIncrementPercentage
            self.startTime = startTime
            self.endTime = endTime
            self.paused = false
        }

        destroy() {
            destroy self.objectForAuction
        }

        /// Can be called by anyone from a public reference to this resource
        /// to submit a bid 
        pub fun createBid(participantCap: Capability<&AuctionParticipant>) {
            pre {
                // make sure auction isn't over and isn't paused
                getCurrentBlock().timestamp >= UFix64(self.startTime) && getCurrentBlock().timestamp <= UFix64(self.endTime):
                    "Auction is not in progress"
            }
            let participantRef = participantCap.borrow()
                ?? panic("Could not borrow a reference to the participant capability")

            assert(
                participantRef.getVaultType() == self.fungibleTokenType,
                message: "Incorrect fungible token type for auction"
            )

            let bidAmount = participantRef.getBalance()
                ?? panic("The bid does not have a valid vault")

            assert(
                // make sure the bid is above the minimum, above the increment percentage
                bidAmount >= self.reservePrice,
                message: "Bid is not above the minimum"
            )

            assert(
                bidAmount > self.winningBidAmount + self.winningBidAmount * self.minBidIncrementPercentage,
                message: "Bid amount is not high enough"
            )

            // 
            if getCurrentBlock().timestamp > UFix64(self.endTime) - self.timeBuffer {
                self.endTime = getCurrentBlock().timestamp + self.timeBuffer
            }

            participantRef.setEndTime(self.endTime)

            self.bids[participantRef.uuid] = participantCap
            self.winningBidID = participantRef.uuid
            self.winningBidAmount = bidAmount
        }

        /// Called by the admin to settle th auction, sending the NFT to the winner
        /// and taking the winner's bid
        pub fun settleAuction(): @FungibleToken.Vault? {
            pre {
                // make sure auction is over
                getCurrentBlock().timestamp >= UFix64(self.endTime):
                    "Auction needs to be over before settling"
            }

            let wrappedReward <- self.objectForAuction <- nil
            let reward <- wrappedReward ?? panic("Cannot settle the auction without a reward to send")

            // make sure the current winner's participant capability
            // is still valid
            if let winner = self.bids[self.winningBidID] {
                if let winnerRef = winner.borrow() {

                    winnerRef.depositNFT(<-reward)
                    return <-winnerRef.withdrawBid(amount: self.winningBidAmount)
                }
            }

            var highestBid = 0.0
            var winnerID: UInt64 = 0
            var tempWinnerRef: &AuctionParticipant? = nil
            // If the first winner has an invalid capability
            // we have to look for the next eligible winner
            for id in self.bids.keys {
                if let participantRef = self.bids[id]?.borrow() {
                    if participantRef!.getBalance()! > highestBid {
                        highestBid = participantRef!.getBalance()!
                        winnerID = id
                        tempWinnerRef = participantRef
                    }
                }
            }

            if let winnerRef = tempWinnerRef {
                winnerRef.depositNFT(<-reward!)
                return <-winnerRef.withdrawBid(amount: self.winningBidAmount)
            } else {
                destroy reward
                return nil
            }
        }

        pub fun togglePause(): Bool {
            self.paused = !self.paused
            return self.paused
        }
    }

    /// Allows anyone to create an Auction
    pub fun createAuction(objectForAuction: @NonFungibleToken.NFT,
                          fungibleTokenType: Type,
                          timeBuffer: UFix64,
                          reservePrice: UFix64,
                          minBidIncrementPercentage: UFix64,
                          startTime: UFix64,
                          endTime: UFix64): @Auction {
        return <-create Auction(
            objectForAuction: <-objectForAuction,
            fungibleTokenType: fungibleTokenType,
            timeBuffer: timeBuffer,
            reservePrice: reservePrice,
            minBidIncrementPercentage: minBidIncrementPercentage,
            startTime: startTime,
            endTime: endTime)
    }

    /// When a user makes a bid on an auction,
    /// they get this resource as a voucher to either reclaim their bid
    /// or claim the prize that the auction winner wins
    pub resource AuctionParticipant {

        /// Contains the token bid for this participant
        access(self) var bid: @FungibleToken.Vault?

        /// Will store the reward if this bid wins the auction
        access(self) var reward: @NonFungibleToken.NFT?

        /// The end time of that auction that is being
        /// participated in
        pub var endTime: UFix64

        init() {

            self.bid <- nil
            self.reward <- nil
            
            self.endTime = 0.0
        }

        destroy() {
            destroy self.bid
            destroy self.reward
        }

        /// Gets the balance of the bid if it exists
        pub fun getBalance(): UFix64? {
            return self.bid?.balance
        }

        /// Gets the type of the bid vault if it exists
        pub fun getVaultType(): Type? {
            return self.bid?.getType()
        }

        /// Deposit a new bid into the participant resource
        pub fun depositBid(from: @FungibleToken.Vault): @FungibleToken.Vault? {
            pre {
                self.reward != nil: "Need to withdraw reward from previous auction before starting a new one"
            }

            // If there is an existing bid here, 
            // either combine it with the new bid if they are the same type
            // or replace it with the new bid and return the old one
            if let oldBid <- self.bid <- nil {
                if oldBid.getType() == from.getType() {
                    oldBid.deposit(from: <-from)
                    self.bid <-! oldBid
                    return nil
                }
                self.bid <-! from
                return <-oldBid
            }
            
            // If there was no bid, save the new bid and return nil
            self.bid <-! from
            return nil
        }

        /// Allows an auction to set the end time when a participant enters
        access(contract) fun setEndTime(_ endTime: UFix64) {
            self.endTime = endTime
        }

        /// Allows an auction to deposit the winning NFT
        /// When the auction is over
        access(contract) fun depositNFT(_ nft: @NonFungibleToken.NFT) {
            let oldNFT <- self.reward <- nft
            destroy oldNFT
        }

        access(all) fun withdrawBid(amount: UFix64): @FungibleToken.Vault? {
            pre {
                // make sure auction is over
                getCurrentBlock().timestamp >= UFix64(self.endTime):
                    "Auction needs to be over before withdrawing"
            }
            let bid <- self.bid?.withdraw(amount: amount)
            return <-bid
        }

        /// The owner can withdraw the NFT reward after the auction is over
        access(all) fun withdrawReward(): @NonFungibleToken.NFT? {
            pre {
                // make sure auction is over
                getCurrentBlock().timestamp >= UFix64(self.endTime):
                    "Auction needs to be over before withdrawing reward"
            }
            let reward <- self.reward <- nil
            return <-reward
        }
    }

    /// Creates a partipant resource that the user can store
    /// in their account to participate in auctions
    pub fun createAuctionParticipant(): @AuctionParticipant {
        return <- create AuctionParticipant()
    }
}