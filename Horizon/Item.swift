//
//  Item.swift
//  Clash
//
//  Created by 吴铠涵 on 2026/10/1.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
