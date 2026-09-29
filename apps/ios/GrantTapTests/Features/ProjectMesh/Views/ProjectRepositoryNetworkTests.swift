import XCTest
@testable import GrantTap

final class ProjectRepositoryNetworkTests: XCTestCase {
    func testEqualDisplayNamesStaySeparateAndLayoutDoesNotDependOnInputOrder() {
        let first = ProjectGraphNode(id: "github.com/a/project", name: "project",
            isOwn: true, available: true, openTasks: 1, layers: [])
        let fork = ProjectGraphNode(id: "github.com/b/project", name: "project",
            isOwn: false, available: true, openTasks: 0, layers: [])
        let size = CGSize(width: 900, height: 440)
        let forward = ProjectRepositoryNetworkLayout.positions([first, fork], size: size)
        let reversed = ProjectRepositoryNetworkLayout.positions([fork, first], size: size)
        XCTAssertEqual(forward, reversed)
        XCTAssertNotEqual(forward[first.id], forward[fork.id])
        XCTAssertEqual(forward.count, 2)
    }

    func testEmptyAndSingleRepositoryHaveFinitePositions() {
        let node = ProjectGraphNode(id: "repo", name: "repo", isOwn: true,
            available: true, openTasks: 0, layers: [])
        let size = CGSize(width: 500, height: 440)
        XCTAssertTrue(ProjectRepositoryNetworkLayout.positions([], size: size).isEmpty)
        XCTAssertEqual(ProjectRepositoryNetworkLayout.positions([node], size: size)[node.id],
            CGPoint(x: 250, y: 220))
    }
}
