//
//  AdminReportedUserItem.swift
//  Spots
//

import SwiftUI

struct AdminReportedUserItem: Identifiable {
    let id: String            // targetUid
    let username: String
    let reportersCount: Int
    let lastReason: String
}
