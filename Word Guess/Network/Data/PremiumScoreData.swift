//
//  PremiumScoreData.swift
//  WordZap
//
//  Created by Barak Ben Hur on 13/09/2025.
//

import Foundation

struct PremiumScoreData: Codable, Hashable {
    let name: String
    let uniqe: String
    let value: Int
    let rank: Int
}

extension PremiumScoreData {
    var id: String { uniqe }
}
