import XCTest
@testable import GrantTap

final class ProjectEnvironmentKeyTests: XCTestCase {
    func testApplicationVariablesAreAllowedButAgentRuntimeKeysAreRefusedBeforeDelivery() {
        for key in ["APP_MODE", "DATABASE_URL", "FEATURE_2"] {
            XCTAssertTrue(ProjectEnvironmentKey.allowed(key), key)
        }
        for key in ["HOME", "PATH", "NODE_OPTIONS", "GRANTTAP_TOKEN",
                    "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "CODEX_HOME", "XDG_CONFIG_HOME",
                    "2_INVALID", "lowercase"] {
            XCTAssertFalse(ProjectEnvironmentKey.allowed(key), key)
            let environment = ProjectEnvironment(
                projectId: "project", revision: 1, shareNonSecretsWithRepo: false, variables: [
                    ProjectEnvironmentVariable(key: key, value: "value", secret: false)
                ]
            )
            XCTAssertFalse(ProjectAuxiliaryPolicyValidation.valid(
                nil, restrictions: nil, environment: environment, projectId: "project"
            ), key)
        }
    }
}
