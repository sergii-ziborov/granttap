import XCTest
@testable import GrantTap

final class ProjectEnvironmentVariableEditorTests: XCTestCase {
    func testExistingSecretIsWriteOnlyAndCanBeKeptOrReplaced() {
        let existing = ProjectEnvironmentVariable(key: "APP_TOKEN", value: "stored-reference", secret: true)
        XCTAssertEqual(ProjectEnvironmentVariableEditor.initialValue(for: existing), "")
        XCTAssertEqual(ProjectEnvironmentVariableEditor.updated(existing, value: "", secret: true), existing)
        XCTAssertEqual(ProjectEnvironmentVariableEditor.updated(existing, value: "replacement", secret: true)?.value,
                       "replacement")
    }

    func testOrdinaryValueCanBeReadAndEdited() {
        let existing = ProjectEnvironmentVariable(key: "APP_MODE", value: "staging", secret: false)
        XCTAssertEqual(ProjectEnvironmentVariableEditor.initialValue(for: existing), "staging")
        XCTAssertEqual(ProjectEnvironmentVariableEditor.updated(existing, value: "production", secret: false)?.value,
                       "production")
        XCTAssertNil(ProjectEnvironmentVariableEditor.updated(existing, value: "", secret: false))
    }
}
