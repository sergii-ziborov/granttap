import XCTest
@testable import GrantTap

final class ProjectRestrictionRuleEditorTests: XCTestCase {
    private let original = ProjectRestrictionRule(ruleId: "custom-1", kind: "custom", name: "Old rule")

    func testEditedRuleUsesAnEnforcedCheckAndSurvivesWireValidation() throws {
        let rule = try XCTUnwrap(ProjectRestrictionRuleEditor.makeRule(
            from: original, kind: "max_file_lines", name: "Core files", limit: "300",
            effect: "deny", paths: "src/**/*.swift\nTests/**", requiresName: true
        ))
        XCTAssertEqual(rule.ruleId, original.ruleId)
        XCTAssertEqual(rule.kind, "max_file_lines")
        XCTAssertEqual(rule.paths, ["src/**/*.swift", "Tests/**"])
        let set = ProjectRestrictionSet(projectId: "project", revision: 1, scope: "project", rules: [rule])
        XCTAssertTrue(ProjectAuxiliaryPolicyValidation.valid(
            nil, restrictions: set, environment: nil, projectId: "project"
        ))
        XCTAssertEqual(try JSONDecoder().decode(ProjectRestrictionSet.self,
                                                from: JSONEncoder().encode(set)), set)
    }

    func testLegacyNamedRuleAndInvalidPathCannotBeSavedAsActiveRule() {
        XCTAssertNil(ProjectRestrictionRuleEditor.makeRule(
            from: original, kind: "custom", name: "Looks active", limit: "300",
            effect: "deny", paths: "", requiresName: true
        ))
        XCTAssertNil(ProjectRestrictionRuleEditor.makeRule(
            from: original, kind: "max_file_bytes", name: "Bad path", limit: "30",
            effect: "ask", paths: "../private", requiresName: true
        ))
        XCTAssertNil(ProjectRestrictionRuleEditor.makeRule(
            from: original, kind: "max_function_lines", name: "Bad limit", limit: "0",
            effect: "deny", paths: "", requiresName: true
        ))
    }
}
