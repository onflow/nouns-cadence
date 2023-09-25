/*
*
*  This is a cadence implementation of the Nouns Token Solidity smart contract
*  https://nouns.wtf/
*
*/

import NonFungibleToken from "NonFungibleToken"
import MetadataViews from "MetadataViews"
import ViewResolver from "ViewResolver"
import NounsDescriptor from "NounsDescriptor"

pub contract NounsToken: NonFungibleToken, ViewResolver {

    access(all) var nounsDAOCollection: Capability<&{NonFungibleToken.CollectionPublic}>?

    // The noun seeds
    pub let seeds: {UInt64: NounsDescriptor.Seed}

    // IPFS content hash of contract-level metadata
    access(self) var contractURIHash: String

    /// Total supply of NounsTokens in existence
    pub var totalSupply: UInt64

    /// The event that is emitted when the contract is created
    pub event ContractInitialized()

    /// The event that is emitted when an NFT is withdrawn from a Collection
    pub event Withdraw(id: UInt64, from: Address?)

    /// The event that is emitted when an NFT is deposited to a Collection
    pub event Deposit(id: UInt64, to: Address?)

    /// Storage and Public Paths
    pub let CollectionStoragePath: StoragePath
    pub let CollectionPublicPath: PublicPath
    pub let MinterStoragePath: StoragePath

    /// The core resource that represents a Non Fungible Token.
    /// New instances will be created using the NFTMinter resource
    /// and stored in the Collection resource
    ///
    pub resource NFT: NonFungibleToken.INFT, MetadataViews.Resolver {

        /// The unique ID that each NFT has
        pub let id: UInt64

        /// Metadata fields
        pub var name: String
        pub var description: String

        access(self) let metadata: {String: AnyStruct}

        init(
            id: UInt64,
            seed: NounsDescriptor.Seed,
            metadata: {String: AnyStruct}
        ) {
            self.id = id
            self.name = ""
            self.description = ""
            self.metadata = metadata
        }

        /// Function that returns all the Metadata Views implemented by a Non Fungible Token
        ///
        /// @return An array of Types defining the implemented views. This value will be used by
        ///         developers to know which parameter to pass to the resolveView() method.
        ///
        pub fun getViews(): [Type] {
            return [
                Type<MetadataViews.Display>(),
                Type<MetadataViews.Editions>(),
                Type<MetadataViews.ExternalURL>(),
                Type<MetadataViews.NFTCollectionData>(),
                Type<MetadataViews.NFTCollectionDisplay>(),
                Type<MetadataViews.Serial>(),
                Type<MetadataViews.Traits>()
            ]
        }

        /// Function that resolves a metadata view for this token.
        ///
        /// @param view: The Type of the desired view.
        /// @return A structure representing the requested view.
        ///
        pub fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<MetadataViews.Display>():
                    return MetadataViews.Display(
                        name: self.name,
                        description: self.description,
                        thumbnail: MetadataViews.HTTPFile(
                            url: ""
                        )
                    )
                case Type<MetadataViews.Editions>():
                    // There is no max number of NFTs that can be minted from this contract
                    // so the max edition field value is set to nil
                    let editionInfo = MetadataViews.Edition(name: "Example NFT Edition", number: self.id, max: nil)
                    let editionList: [MetadataViews.Edition] = [editionInfo]
                    return MetadataViews.Editions(
                        editionList
                    )
                case Type<MetadataViews.Serial>():
                    return MetadataViews.Serial(
                        self.id
                    )
                case Type<MetadataViews.ExternalURL>():
                    return MetadataViews.ExternalURL("nouns.wtf")
                case Type<MetadataViews.NFTCollectionData>():
                    return NounsToken.resolveView(Type<MetadataViews.NFTCollectionData>())
                case Type<MetadataViews.NFTCollectionDisplay>():
                    return NounsToken.resolveView(Type<MetadataViews.NFTCollectionDisplay>())
                case Type<MetadataViews.Traits>():
                    // exclude mintedTime and foo to show other uses of Traits
                    let excludedTraits = ["mintedTime", "foo"]
                    let traitsView = MetadataViews.dictToTraits(dict: self.metadata, excludedNames: excludedTraits)

                    // mintedTime is a unix timestamp, we should mark it with a displayType so platforms know how to show it.
                    let mintedTimeTrait = MetadataViews.Trait(name: "mintedTime", value: self.metadata["mintedTime"]!, displayType: "Date", rarity: nil)
                    traitsView.addTrait(mintedTimeTrait)

                    // foo is a trait with its own rarity
                    let fooTraitRarity = MetadataViews.Rarity(score: 10.0, max: 100.0, description: "Common")
                    let fooTrait = MetadataViews.Trait(name: "foo", value: self.metadata["foo"], displayType: nil, rarity: fooTraitRarity)
                    traitsView.addTrait(fooTrait)

                    return traitsView

            }
            return nil
        }
    }

    /// Defines the methods that are particular to this NFT contract collection
    /// And should be made publicly accessible
    ///
    pub resource interface NounsTokenCollectionPublic {
        pub fun deposit(token: @NonFungibleToken.NFT)
        pub fun getIDs(): [UInt64]
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT
        pub fun borrowNFTSafe(id: UInt64): &NonFungibleToken.NFT?
        pub fun borrowNounsToken(id: UInt64): &NounsToken.NFT? {
            post {
                (result == nil) || (result?.id == id):
                    "Cannot borrow NounsToken reference: the ID of the returned reference is incorrect"
            }
        }
        pub fun borrowViewResolver(id: UInt64): &AnyResource{MetadataViews.Resolver}
    }

    /// The resource that holds the NFTs inside any account
    /// In order to be able to own and manage NFTs any account will need to create
    /// and store an empty collection first
    ///
    pub resource Collection: NounsTokenCollectionPublic, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection {
        // dictionary where the owned NFTs are stored
        // NFT is a resource type with an `UInt64` ID field
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        init () {
            self.ownedNFTs <- {}
        }

        /// Removes an NFT from the collection and moves it to the caller
        /// @param withdrawID: The ID of the NFT that wants to be withdrawn
        /// @return The NFT resource that has been taken out of the collection
        ///
        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            let token <- self.ownedNFTs.remove(key: withdrawID) ?? panic("missing NFT")

            emit Withdraw(id: token.id, from: self.owner?.address)

            return <-token
        }

        /// Adds an NFT to the collections dictionary and adds the ID to the id array
        /// @param token: The NFT resource to be included in the collection
        ///
        pub fun deposit(token: @NonFungibleToken.NFT) {
            let token <- token as! @NounsToken.NFT
            let id: UInt64 = token.id

            // add the new token to the dictionary which removes the old one
            let oldToken <- self.ownedNFTs[id] <- token
            destroy oldToken

            emit Deposit(id: id, to: self.owner?.address)
        }

        /// Helper method for getting the collection IDs
        /// @return An array containing the IDs of the NFTs in the collection
        ///
        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        /// Gets a reference to an NFT
        /// @param id: The ID of the wanted NFT
        /// @return A reference to the wanted NFT resource
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return (&self.ownedNFTs[id] as &NonFungibleToken.NFT?)!
        }

        /// Gets an optional reference to an NFT
        /// @param id: The ID of the wanted NFT
        /// @return A reference to the wanted NFT resource, or nil if it isn't in the collection
        pub fun borrowNFTSafe(id: UInt64): &NonFungibleToken.NFT? {
            if self.ownedNFTs[id] != nil {
                // Create an authorized reference to allow downcasting
                let ref = (&self.ownedNFTs[id] as &NonFungibleToken.NFT?)
                return ref
            }
            return nil
        }

        /// Gets a reference to an NFT as a NounsToken in the collection so that
        /// the caller can read its metadata and call its methods
        /// @param id: The ID of the wanted NFT
        /// @return A reference to the wanted NFT resource, or nil if it isn't in the collection
        pub fun borrowNounsToken(id: UInt64): &NounsToken.NFT? {
            if self.ownedNFTs[id] != nil {
                // Create an authorized reference to allow downcasting
                let ref = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!
                return ref as! &NounsToken.NFT
            }
            return nil
        }

        /// Gets a reference to the NFT conforming to `{MetadataViews.Resolver}`
        /// @param id: The ID of the wanted NFT
        /// @return The resource reference conforming to the Resolver interface
        pub fun borrowViewResolver(id: UInt64): &AnyResource{MetadataViews.Resolver} {
            let nft = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!
            let NounsToken = nft as! &NounsToken.NFT
            return NounsToken as &{MetadataViews.Resolver}
        }

        destroy() {
            destroy self.ownedNFTs
        }
    }

    /// Allows anyone to create a new empty collection
    /// @return The new Collection resource
    ///
    pub fun createEmptyCollection(): @NonFungibleToken.Collection {
        return <- create Collection()
    }

    /// Resource that an admin or something similar would own to be
    /// able to mint new NFTs and do other admin functionality
    ///
    pub resource NounsAdmin {

        pub fun setNounsDAOCollection(_ newCollection: Capability<&{NonFungibleToken.CollectionPublic}>) {
            NounsToken.nounsDAOCollection = newCollection
        }

        /// Sets the contractURIHash
        pub fun setContractURIHash(newContractURIHash: String) {
            NounsToken.contractURIHash = newContractURIHash;
        }

        /// Mints a new NFT with a new ID
        ///
        access(all) fun mintNFT(): @NounsToken.NFT {
            let metadata: {String: AnyStruct} = {}
            let currentBlock = getCurrentBlock()
            metadata["mintedBlock"] = currentBlock.height
            metadata["mintedTime"] = currentBlock.timestamp

            let seed = NounsDescriptor.generateSeed()

            // create a new NFT
            var newNFT <- create NFT(
                id: NounsToken.totalSupply,
                seed: seed,
                metadata: metadata,
            )

            NounsToken.totalSupply = NounsToken.totalSupply + 1

            return <-newNFT
        }
    }

    /// Function that resolves a metadata view for this contract.
    /// @param view: The Type of the desired view.
    /// @return A structure representing the requested view.
    ///
    pub fun resolveView(_ view: Type): AnyStruct? {
        switch view {
            case Type<MetadataViews.NFTCollectionData>():
                return MetadataViews.NFTCollectionData(
                    storagePath: NounsToken.CollectionStoragePath,
                    publicPath: NounsToken.CollectionPublicPath,
                    providerPath: /private/NounsTokenCollection,
                    publicCollection: Type<&NounsToken.Collection{NounsToken.NounsTokenCollectionPublic}>(),
                    publicLinkedType: Type<&NounsToken.Collection{NounsToken.NounsTokenCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>(),
                    providerLinkedType: Type<&NounsToken.Collection{NounsToken.NounsTokenCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Provider,MetadataViews.ResolverCollection}>(),
                    createEmptyCollectionFunction: (fun (): @NonFungibleToken.Collection {
                        return <-NounsToken.createEmptyCollection()
                    })
                )
            case Type<MetadataViews.NFTCollectionDisplay>():
                let media = MetadataViews.Media(
                    file: MetadataViews.HTTPFile(
                        url: ""
                    ),
                    mediaType: "image/svg+xml"
                )
                return MetadataViews.NFTCollectionDisplay(
                    name: "The Nouns Collection",
                    description: "This collection is a Cadence implementation of the Nouns Protocol",
                    externalURL: MetadataViews.ExternalURL("https://nouns.wtf/"),
                    squareImage: media,
                    bannerImage: media,
                    socials: {
                        "twitter": MetadataViews.ExternalURL("https://twitter.com/nounsdao")
                    }
                )
            case Type<MetadataViews.IPFSFile>():
                //let cid = String(abi.encodePacked("ipfs://", self.contractURIHash))
                return MetadataViews.IPFSFile(cid: "empty", path: nil)
        }
        return nil
    }

    /// Function that returns all the Metadata Views implemented by a Non Fungible Token
    ///
    /// @return An array of Types defining the implemented views. This value will be used by
    ///         developers to know which parameter to pass to the resolveView() method.
    ///
    pub fun getViews(): [Type] {
        return [
            Type<MetadataViews.NFTCollectionData>(),
            Type<MetadataViews.NFTCollectionDisplay>(),
            Type<MetadataViews.IPFSFile>()
        ]
    }

    init() {
        self.seeds = {}
        self.nounsDAOCollection = nil
        self.contractURIHash = "QmZi1n79FqWt2tTLwCqiy6nLM6xLGRsEPQ5JmReJQKNNzX"

        // Initialize the total supply
        self.totalSupply = 0

        // Set the named paths
        self.CollectionStoragePath = /storage/NounsTokenCollection
        self.CollectionPublicPath = /public/NounsTokenCollection
        self.MinterStoragePath = /storage/NounsTokenMinter

        // Create a Collection resource and save it to storage
        let collection <- create Collection()
        self.account.save(<-collection, to: self.CollectionStoragePath)

        // create a public capability for the collection
        self.account.link<&NounsToken.Collection{NonFungibleToken.CollectionPublic, NounsToken.NounsTokenCollectionPublic, MetadataViews.ResolverCollection}>(
            self.CollectionPublicPath,
            target: self.CollectionStoragePath
        )

        // Create a Minter resource and save it to storage
        let minter <- create NounsAdmin()
        self.account.save(<-minter, to: self.MinterStoragePath)

        emit ContractInitialized()
    }
}
