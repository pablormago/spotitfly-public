//
//  GroupsFeatureFlags.swift
//  Spots
//
//  Created by Pablo Jimenez on 24/10/25.
//


import Foundation
import FirebaseFirestore

struct GroupsFeatureFlags: Codable {
    var enabled: Bool
    var testers: [String]
}

final class FeatureFlagsService {
    static let shared = FeatureFlagsService()
    private init() {}

    private var cache: GroupsFeatureFlags?

    func fetchGroupsFlag() async throws -> GroupsFeatureFlags {
        if let c = cache { return c }
        let snap = try await Firestore.firestore()
            .collection("meta").document("features").getDocument()
        let data = snap.data() ?? [:]
        let groups = (data["groups"] as? [String: Any]) ?? [:]
        let enabled = (groups["enabled"] as? Bool) ?? false
        let testers = (groups["testers"] as? [String]) ?? []
        let flags = GroupsFeatureFlags(enabled: enabled, testers: testers)
        self.cache = flags
        return flags
    }

    func isGroupsEnabledFor(uid: String) async -> Bool {
        do {
            let flags = try await fetchGroupsFlag()
            return flags.enabled && flags.testers.contains(uid)
        } catch {
            return false
        }
    }

    func invalidateCache() {
        cache = nil
    }
}
