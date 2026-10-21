import XCTest
@testable import GrantTap

final class HealthReportControlsTests: XCTestCase {
    func testFreshGitObservationReplacesOldBindingRevisionWithoutCallingPartialReportFailed() {
        let repository = "github.com/example/project"
        let report = ProjectRepositoryGraph(projectId: "p", repositoryId: repository, revision: "new",
            weavatrixVersion: "2.17.4", analysisStatus: "INCOMPLETE", nodes: [], relations: [],
            totalNodes: 4, totalRelations: 5, truncated: true)
        let snapshot = ProjectMeshSnapshot(type: "mesh.snapshot", sessionId: "p", projectId: "p",
            project: .init(projectId: "p", name: "Project", canonicalRepositoryId: repository, createdAt: 1),
            bindings: [.init(bindingId: "b", projectId: "p", endpointId: "computer", repositoryId: repository,
                displayName: "Project", available: true, revision: "old")],
            repositoryGraphs: [report], repositoryDetails: [.init(projectId: "p", repositoryId: repository,
                canonicalRepositoryId: repository, endpointId: "computer", status: "ready", revision: "new", observedAt: 2)],
            tasks: [], executions: [], claims: [], dependencies: [], events: [], generatedAt: 2)
        let health = ProjectHealthPresentation(snapshot: snapshot, connections: [])
        XCTAssertFalse(health.needsAnalysis, "bounded evidence at the observed revision does not need another rebuild")
        XCTAssertFalse(health.repositories[0].stale)
        XCTAssertTrue(health.repositories[0].usable)
        XCTAssertFalse(health.repositories[0].ready, "partial is still not complete")
        XCTAssertEqual(health.repositories[0].statusTitle, L("Current · partial report"))
    }

    func testCodeChecksSurviveAppleWireRoundTripAndUnknownStaysAbsent() throws {
        let json = """
        {"files":[{"path":"main.rs","language":"rust","lineCount":12,"symbols":[
        {"id":"f","label":"f","kind":"function","startLine":1,"lineCount":12,
        "metrics":{"measured":true,"sourceLines":12,"cyclomatic":4,"maxLoopDepth":2,"callers":0}}]}],
        "roads":[],"totalFiles":1,"truncated":false}
        """
        let map = try JSONDecoder().decode(ProjectCodeMap.self, from: Data(json.utf8))
        XCTAssertTrue(map.valid())
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(map)) as! [String: Any]
        let file = (encoded["files"] as! [[String: Any]])[0]
        let symbol = (file["symbols"] as! [[String: Any]])[0]
        XCTAssertNotNil(symbol["metrics"], "native decoding must preserve real Engine measurements for the viewer")
        var invalid = map
        let negative = json.replacingOccurrences(of: "\"cyclomatic\":4", with: "\"cyclomatic\":-1")
        invalid = try JSONDecoder().decode(ProjectCodeMap.self, from: Data(negative.utf8))
        XCTAssertFalse(invalid.valid())
        let legacy = json.replacingOccurrences(of: ",\n\"metrics\":{\"measured\":true,\"sourceLines\":12,\"cyclomatic\":4,\"maxLoopDepth\":2,\"callers\":0}", with: "")
        XCTAssertTrue(try JSONDecoder().decode(ProjectCodeMap.self, from: Data(legacy.utf8)).valid())
    }

    func testLocalHealthOptionsFilterAndSortRealStatesWithoutHidingPartialEvidence() {
        func repository(_ id: String, status: String?, stale: Bool = false) -> ProjectHealthPresentation.Repository {
            .init(id: id, name: id, disambiguation: nil, report: status.map { state in
                .init(projectId: "p", repositoryId: id, revision: "head", weavatrixVersion: "2.17.4",
                    analysisStatus: state, nodes: [], relations: [], totalNodes: 1, totalRelations: 0, truncated: false)
            }, stale: stale)
        }
        let values = [repository("a", status: "COMPLETE"), repository("b", status: "INCOMPLETE"),
            repository("c", status: "COMPLETE", stale: true), repository("d", status: nil),
            repository("e", status: "UNAVAILABLE")]
        let select = { (filter: String, sort: String) in
            ProjectHealthOptions.repositories(values, filter: filter, sort: sort).map(\.id)
        }
        XCTAssertEqual(select("all", "problems"), ["e", "d", "c", "b", "a"])
        XCTAssertEqual(select("all", "name"), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(select("refresh", "name"), ["c", "d", "e"])
        XCTAssertEqual(select("errors", "name"), ["e"])
        XCTAssertEqual(select("invalid", "invalid"), ["a", "b", "c", "d", "e"])
    }
}
