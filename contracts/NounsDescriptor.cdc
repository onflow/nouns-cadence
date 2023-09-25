

pub contract NounsDescriptor {

    pub var arePartsLocked: Bool

    // Whether or not `tokenURI` should be returned as a data URI (Default: true)
    pub var isDataURIEnabled: Bool

    // Base URI
    pub var baseURI: String

    // Noun Color Palettes (Index => Hex Colors)
    pub let palettes: {UInt8: [String]}

    // Noun Backgrounds (Hex Colors)
    pub let backgrounds: [String]

    // Noun Bodies (Custom RLE)
    pub let bodies: [[UInt8]]

    // Noun Accessories (Custom RLE)
    pub let accessories: [[UInt8]]

    // Noun Heads (Custom RLE)
    pub let heads: [[UInt8]]

    // Noun Glasses (Custom RLE)
    pub let glasses: [[UInt8]]

    pub event PartsLocked();

    pub event DataURIToggled(_ enabled: Bool);

    pub event BaseURIUpdated(_ baseURI: String);

    pub resource TraitsAdmin {

        /**
        * @notice Add a single color to a color palette.
        */
        pub fun addColorToPalette(paletteIndex: UInt8, color: String) {
            pre {
                NounsDescriptor.palettes[paletteIndex] != nil: "Invalid palletteIndex"
                NounsDescriptor.palettes[paletteIndex]!.length <= 255: "Palettes can only hold 256 colors"
            }
            NounsDescriptor.palettes[paletteIndex]?.append(color);
        }

        /**
        * @notice Add a Noun background.
        * @dev This function can only be called when not locked.
        */
        pub fun addBackground(background: String) {
            pre {
                NounsDescriptor.arePartsLocked == false: "Parts are locked"
            }
            NounsDescriptor.backgrounds.append(background)
        }

        /**
        * @notice Add a Noun body.
        * @dev This function can only be called when not locked.
        */
        pub fun addBody(body: [UInt8]) {
            pre {
                NounsDescriptor.arePartsLocked == false: "Parts are locked"
            }
            NounsDescriptor.bodies.append(body)
        }

        /**
        * @notice Add a Noun accessory.
        * @dev This function can only be called when not locked.
        */
        pub fun addAccessory(accessory: [UInt8]) {
            pre {
                NounsDescriptor.arePartsLocked == false: "Parts are locked"
            }
            NounsDescriptor.accessories.append(accessory)
        }

        /**
        * @notice Add a Noun head.
        * @dev This function can only be called when not locked.
        */
        pub fun addHead(head: [UInt8]) {
            pre {
                NounsDescriptor.arePartsLocked == false: "Parts are locked"
            }
            NounsDescriptor.heads.append(head)
        }

        /**
        * @notice Add Noun glasses.
        * @dev This function can only be called when not locked.
        */
        pub fun addGlasses(glasses: [UInt8]) {
            pre {
                NounsDescriptor.arePartsLocked == false: "Parts are locked"
            }
            NounsDescriptor.glasses.append(glasses)
        }

        /**
        * @notice Lock all Noun parts.
        * @dev This cannot be reversed and can only be called when not locked.
        */
        pub fun lockParts() {
            NounsDescriptor.arePartsLocked = true

            emit PartsLocked()
        }

        /**
        * @notice Toggle a boolean value which determines if `tokenURI` returns a data URI
        * or an HTTP URL.
        */
        pub fun toggleDataURIEnabled() {
            let enabled = !NounsDescriptor.isDataURIEnabled

            NounsDescriptor.isDataURIEnabled = enabled
            emit DataURIToggled(enabled)
        }

        /**
        * @notice Set the base URI for all token IDs. It is automatically
        * added as a prefix to the value returned in {tokenURI}, or to the
        * token ID if {tokenURI} is empty.
        */
        pub fun setBaseURI(baseURI: String) {
            NounsDescriptor.baseURI = baseURI

            emit BaseURIUpdated(baseURI)
        }
    }

    pub struct Seed {
        pub let background: UInt64
        pub let body: UInt64
        pub let accessory: UInt64
        pub let head: UInt64
        pub let glasses: UInt64

        init(
            background: UInt64,
            body: UInt64,
            accessory: UInt64,
            head: UInt64,
            glasses: UInt64) 
        {
            self.background = background
            self.body = body
            self.accessory = accessory
            self.head = head
            self.glasses = glasses
        }
    }

    /**
     * @notice Generate a pseudo-random Noun seed
     */
    pub fun generateSeed(): Seed {
        let pseudorandomness = unsafeRandom()

        let backgroundCount = UInt64(self.backgrounds.length)
        let bodyCount = UInt64(self.bodies.length)
        let accessoryCount = UInt64(self.accessories.length)
        let headCount = UInt64(self.heads.length)
        let glassesCount = UInt64(self.glasses.length)

        return Seed(
            background: UInt64(pseudorandomness % backgroundCount),
            body: UInt64((pseudorandomness >> 48) % bodyCount),
            accessory: UInt64((pseudorandomness >> 96) % accessoryCount),
            head: UInt64((pseudorandomness >> 144) % headCount),
            glasses: UInt64((pseudorandomness >> 192) % glassesCount)
        )
    }

    // Keeping the URI and SVG commented out for now to focus on the main parts of the project

    // /**
    //  * @notice Given a token ID and seed, construct a token URI for a Nouns DAO noun.
    //  * @dev The returned value may be a base64 encoded data URI or an API URL.
    //  */
    // pub fun tokenURI(tokenId: UInt64, seed: Seed): String {
    //     if (self.isDataURIEnabled) {
    //         return self.dataURI(tokenId: tokenId, seed: seed)
    //     }
    //     return string(abi.encodePacked(baseURI, tokenId.toString()))
    // }

    // /**
    //  * @notice Given a token ID and seed, construct a base64 encoded data URI for a Nouns DAO noun.
    //  */
    // pub fun dataURI(tokenId: UInt64, seed: Seed): String {
    //     let nounId = tokenId.toString();
    //     let name = String(abi.encodePacked("Noun ", nounId));
    //     let description = String(abi.encodePacked("Noun ", nounId, " is a member of the Nouns DAO"));

    //     return genericDataURI(name, description, seed);
    // }

    // /**
    //  * @notice Given a name, description, and seed, construct a base64 encoded data URI.
    //  */
    // pub fun genericDataURI(
    //     name: String,
    //     description: String,
    //     seed: Seed
    // ): String {
    //     NFTDescriptor.TokenURIParams memory params = NFTDescriptor.TokenURIParams({
    //         name: name,
    //         description: description,
    //         parts: _getPartsForSeed(seed),
    //         background: backgrounds[seed.background]
    //     })
    //     return NFTDescriptor.constructTokenURI(params, palettes)
    // }

    // /**
    //  * @notice Given a seed, construct a base64 encoded SVG image.
    //  */
    // pub fun generateSVGImage(INounsSeeder.Seed memory seed) external view override returns (string memory) {
    //     MultiPartRLEToSVG.SVGParams memory params = MultiPartRLEToSVG.SVGParams({
    //         parts: _getPartsForSeed(seed),
    //         background: backgrounds[seed.background]
    //     })
    //     return NFTDescriptor.generateSVGImage(params, palettes)
    // }

    init() {
        self.arePartsLocked = false
        self.isDataURIEnabled = true
        self.baseURI = ""
        self.palettes = {}
        self.backgrounds = []
        self.bodies = []
        self.accessories = []
        self.heads = []
        self.glasses = []
    }
}