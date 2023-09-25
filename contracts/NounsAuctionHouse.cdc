/*
*
*  This is a cadence implementation of the Nouns Auction Solidity smart contract
*  https://nouns.wtf/
*
*  Builds upon the Generic Auction Smart Contract and NounsToken 
*  to have a special auction every 24 hours that mints one new Noun for each auction
*
*  Just like with the generic auction, a user has to create a `GenericAuction.AuctionParticipant`
*  resource ahead of time in order to participate in the auction.
*  They deposit their bid to the participant resource, create a capability to it,
*  and send it to the NounsAuctionHouse.createBid() function to register their bid.
*  
*  Anyone can call the settle auction function to finish the auction
*  once the end time has passed. This will mint a new noun and start a new auction
*  after the existing auction has been settled.
*  
*
*/

import NonFungibleToken from "NonFungibleToken"
import FungibleToken from "FungibleToken"
import FlowToken from "FlowToken"
import MetadataViews from "MetadataViews"
import ViewResolver from "ViewResolver"
import NounsToken from "NounsToken"
import GenericAuction from "GenericAuction"

pub contract NounsAuctionHouse {

    /// The current nouns auction
    access(self) var auction: @GenericAuction.Auction?

    /// The minimum amount of time left in an auction after a new bid is created
    pub var timeBuffer: UFix64

    /// The minimum price accepted in an auction
    pub var reservePrice: UFix64

    /// The minimum percentage difference between the last bid amount and the current bid
    pub var minBidIncrementPercentage: UFix64

    /// The amount of time in seconds that each auction is supposed to last
    pub var duration: UFix64

    /// Create a new bid in the current auction
    pub fun createBid(_ participantCap: Capability<&GenericAuction.AuctionParticipant>) {
        self.auction.createBid(participantCap)
    }

    /// Callable by anyone to finish an existing auction that has reached its endtime
    /// and start a new one with a new nouns NFT
    pub fun settleAuctionAndStartNew() {
        let auction = self.borrowAuction()
            ?? panic("No auction to borrow")

        // Settle the existing auction
        auction.settleAuction()

        // Destroy the settled auction because it is finished
        let settledAuction <- self.auction <- nil
        destroy settledAuction

        let minter = self.borrowNounsMinter()

        // Mint every 10th Noun to the DAO
        if NounsToken.totalSupply <= 1820 && NounsToken.totalSupply % 10 == 0 {
            let daoNoun <- minter.mintNFT()
            let nounsDaoCollectionRef = (NounsToken.nounsDAOCollection?.borrow()
                ?? panic("No NounsDAOCollection capability"))
                ?? panic("Unable to borrow DAO Collection capability")

            nounsDaoCollectionRef.deposit(token: <-daoNoun)
        }

        let newNoun <- minter.mintNFT()

        // start a new auction
        self.auction <- GenericAuction.createAuction(
            objectForAuction: <-newNoun,
            fungibleTokenType: Type<FlowToken.Vault>(),
            timeBuffer: self.timeBuffer,
            reservePrice: self.reservePrice,
            minBidIncrementPercentage: self.minBidIncrementPercentage,
            startTime: getCurrentBlock().timestamp,
            endTime: getCurrentBlock().timestamp + self.duration)

    }

    access(contract) fun borrowAuction(): &GenericAuction.Auction? {
        return (&self.auction as &GenericAuction.Auction?)
    }

    pub resource Admin {

        pub fun updateTimeBuffer(_ newBuffer: UFix64) {
            NounsAuctionHouse.timeBuffer = newBuffer
        }

        pub fun updateReservePrice(_ newPrice: UFix64) {
            NounsAuctionHouse.reservePrice = newPrice
        }

        pub fun updateMinBidIncrementPercentage(_ newPercentage: UFix64) {
            NounsAuctionHouse.minBidIncrementPercentage = newPercentage
        }

        pub fun updateDuration(_ newDuration: UFix64) {
            NounsAuctionHouse.duration = newDuration
        }
    }

    access(self) fun borrowNounsMinter(): &NounsToken.NounsAdmin {
        let nounsAdmin = self.account.borrow<&NounsToken.NounsAdmin>(from: /storage/nounsAdmin)
            ?? panic("Could not borrow a reference to the Nouns Admin object")

        return nounsAdmin
    }

    init() {
        self.timeBuffer = 300.0
        self.reservePrice = 50.0
        self.minBidIncrementPercentage = 10.0
        self.duration = 86400.0

        let minter = self.account.borrow<&NounsToken.NounsAdmin>(from: /storage/nounsAdmin)
            ?? panic("Could not borrow a reference to the Nouns Admin object")

        let objectForAuction <- minter.mintNFT()

        self.auction <- GenericAuction.createAuction(
            objectForAuction: <-objectForAuction,
            fungibleTokenType: Type<FlowToken.Vault>(),
            timeBuffer: self.timeBuffer,
            reservePrice: self.reservePrice,
            minBidIncrementPercentage: self.minBidIncrementPercentage,
            startTime: getCurrentBlock().timestamp,
            endTime: getCurrentBlock().timestamp + self.duration)
    }

}