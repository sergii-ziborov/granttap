import Foundation
import Testing
@testable import DesktopInspectorCore

@Test func backboneCarriesEvidencedRelationsBetweenProjectNodes() throws {
    let body = try JSONSerialization.data(withJSONObject: [
        "project_id": "project-a", "head": "abc", "pending_candidate_count": 2,
        "nodes": [
            ["kind": "service", "identity": "service:a", "display_name": "API"],
            ["kind": "database", "identity": "database:b", "display_name": "Store"],
        ],
        "relations": [["source": "service:a", "target": "database:b",
                       "relation": "reads", "evidence_count": 3]],
    ])
    let backbone = try JSONDecoder().decode(InspectorBackbone.self, from: body)
    #expect(backbone.relations.count == 1)
    #expect(backbone.relations[0].source == "service:a")
    #expect(backbone.relations[0].target == "database:b")
    #expect(backbone.relations[0].evidence_count == 3)
}
