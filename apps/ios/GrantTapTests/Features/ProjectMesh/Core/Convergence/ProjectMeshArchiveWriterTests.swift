import XCTest
@testable import GrantTap

final class ProjectMeshArchiveWriterTests: XCTestCase {
    func testSlowStorageDoesNotBlockUpdatesAndLatestArchiveIsDurableBeforeFinish() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let returned = DispatchSemaphore(value: 0)
        let writer = ProjectMeshArchiveWriter { archive in
            if archive.projectRooms["project"] == ["room-1"] {
                started.signal()
                _ = release.wait(timeout: .now() + 5)
            }
            do { try JSONEncoder().encode(archive).write(to: url, options: .atomic) }
            catch { XCTFail("Could not persist the Mesh archive") }
        }
        DispatchQueue.global().async {
            writer.enqueue(self.archive(1))
            returned.signal()
        }
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(returned.wait(timeout: .now() + 0.2), .success,
                       "A blocked disk must not block the caller updating Health")
        release.signal()
        _ = returned.wait(timeout: .now() + 2)
        for revision in 2...20 { writer.enqueue(archive(revision)) }
        let finished = expectation(description: "Mesh is durable before background suspension")
        writer.finish {
            do {
                let restored = try JSONDecoder().decode(ProjectMeshArchive.self, from: Data(contentsOf: url))
                XCTAssertEqual(restored.projectRooms, ["project": ["room-20"]])
                XCTAssertEqual(restored.eventSourceRooms, ["question": "source"])
                XCTAssertEqual(restored.attentionStates["question"]?.status, .answered)
            } catch { XCTFail("No durable Mesh archive at completion") }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 3)
        writer.barrier { try? FileManager.default.removeItem(at: url) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func archive(_ revision: Int) -> ProjectMeshArchive {
        .init(snapshots: [:], pendingEvents: [], eventSourceRooms: ["question": "source"],
              attentionStates: ["question": .init(status: .answered)],
              projectRooms: ["project": ["room-\(revision)"]])
    }
}
