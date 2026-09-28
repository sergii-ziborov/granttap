import Foundation

extension ProjectGovernanceWireValidator {
    /// The same value with every null removed, at every depth: an absent
    /// field and a null field mean the same thing to the sender.
    static func withoutNulls(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, item) in object where !(item is NSNull) { out[key] = withoutNulls(item) }
            return out
        }
        if let array = value as? [Any] {
            return array.filter { !($0 is NSNull) }.map(withoutNulls)
        }
        return value
    }

    static func strictNestedShapes(_ root: [String: Any]) -> Bool {
        guard let policy = root["policy"] as? [String: Any], validPolicyShape(policy) else {
            if let ack = root["acknowledgement"] as? [String: Any] {
                return validAcknowledgementShape(ack)
            }
            return false
        }
        guard let coverage = root["coverage"] else { return true }
        return (coverage as? [String: Any]).map(validCoverageShape) ?? false
    }

    private static func validPolicyShape(_ value: [String: Any]) -> Bool {
        guard ["projectId", "revision", "enforcement", "rules"].allSatisfy({ value[$0] != nil }),
              subset(value, ["projectId", "revision", "enforcement", "rules",
                             "execution", "restrictions", "environment"]),
              let rules = value["rules"] as? [[String: Any]] else { return false }
        let execution = (value["execution"] as? [String: Any]).map(validExecutionShape)
            ?? (value["execution"] == nil)
        let restrictions = (value["restrictions"] as? [String: Any]).map(validRestrictionShape)
            ?? (value["restrictions"] == nil)
        let environment = (value["environment"] as? [String: Any]).map(validEnvironmentShape)
            ?? (value["environment"] == nil)
        return rules.allSatisfy(validRuleShape) && execution && restrictions && environment
    }

    private static func validExecutionShape(_ value: [String: Any]) -> Bool {
        ["mode", "revision"].allSatisfy { value[$0] != nil }
            && subset(value, ["mode", "targetEndpointId", "revision", "hostGrantId",
                              "hostGrantStatus", "offlineBehavior"])
    }

    private static func validRestrictionShape(_ value: [String: Any]) -> Bool {
        guard ["projectId", "revision", "scope", "rules"].allSatisfy({ value[$0] != nil }),
              subset(value, ["projectId", "revision", "scope", "repositoryId", "rules", "source"]),
              let rules = value["rules"] as? [[String: Any]] else { return false }
        return rules.allSatisfy { rule in
            ["ruleId", "kind"].allSatisfy { key in rule[key] != nil }
                && subset(rule, ["ruleId", "kind", "limit", "name", "paths", "effect"])
        }
    }

    private static func validEnvironmentShape(_ value: [String: Any]) -> Bool {
        guard ["projectId", "revision", "variables"].allSatisfy({ value[$0] != nil }),
              subset(value, ["projectId", "revision", "shareNonSecretsWithRepo", "variables"]),
              let variables = value["variables"] as? [[String: Any]] else { return false }
        return variables.allSatisfy { variable in
            ["key", "secret"].allSatisfy { key in variable[key] != nil }
                && subset(variable, ["key", "value", "secret"])
        }
    }

    private static func validRuleShape(_ value: [String: Any]) -> Bool {
        guard exact(value, [
            "ruleId", "projectId", "selector", "effect", "conditions", "revision", "createdBy",
        ]), let selector = value["selector"] as? [String: Any],
              let conditions = value["conditions"] as? [String: Any],
              subset(selector, ["kind", "displayName", "provider", "origin", "fingerprint"]),
              subset(conditions, ["endpointIds", "providers", "impact"]) else { return false }
        guard let predicate = selector["fingerprint"] else { return true }
        guard let object = predicate as? [String: Any], let match = object["match"] as? String else {
            return false
        }
        if match == "confidence" { return exact(object, ["match", "value"]) }
        guard exact(object, ["match", "expected"]),
              let expected = object["expected"] as? [String: Any] else { return false }
        return subset(expected, [
            "kind", "displayName", "provider", "origin", "publisher", "version", "transport",
            "executablePathHash", "configHash", "scriptHash", "confidence",
        ]) && ["kind", "displayName", "confidence"].allSatisfy { expected[$0] != nil }
    }

    private static func validCoverageShape(_ value: [String: Any]) -> Bool {
        guard exact(value, [
            "projectId", "policyRevision", "enforcement", "requiredCapabilities", "endpoints",
            "strictReady",
        ]), let endpoints = value["endpoints"] as? [[String: Any]] else { return false }
        return endpoints.allSatisfy(validAcknowledgementShape)
    }

    private static func validAcknowledgementShape(_ value: [String: Any]) -> Bool {
        guard exact(value, [
            "projectId", "policyRevision", "endpointId", "provider", "capabilities", "observedAt",
        ]), let capabilities = value["capabilities"] as? [[String: Any]] else { return false }
        return capabilities.allSatisfy { exact($0, ["kind", "status"]) }
    }

    private static func exact(_ value: [String: Any], _ keys: Set<String>) -> Bool {
        Set(value.keys) == keys
    }

    private static func subset(_ value: [String: Any], _ keys: Set<String>) -> Bool {
        Set(value.keys).isSubset(of: keys)
    }
}
