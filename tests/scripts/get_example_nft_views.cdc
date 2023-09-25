/// This script checks all the supported views from
/// the NounsToken contract. Used for testing only.

import NounsToken from "NounsToken"
import MetadataViews from "MetadataViews"

pub fun main(): Bool {
    let views = NounsToken.getViews()

    let expected = [
        Type<MetadataViews.NFTCollectionData>(),
        Type<MetadataViews.NFTCollectionDisplay>()
    ]
    assert(expected == views)

    return true
}
