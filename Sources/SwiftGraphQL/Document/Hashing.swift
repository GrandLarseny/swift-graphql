//
//  Hashing.swift
//  swift-graphql
//
//  Created by Daniel Larsen on 12/11/24.
//

import CryptoKit
import Foundation

extension String {
    var stableHash: String {
        let data = Data(utf8)
        let hash = SHA256.hash(data: data)

        // Convert the digest to a lowercase hex string
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
