import Foundation

enum MeetingJsonLogic {
    static func evaluate(rule: String, data: [String: Any]) -> Bool {
        guard let ruleData = rule.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: ruleData) else {
            return false
        }
        let result = resolve(json, data: data)
        if let bool = result as? Bool {
            return bool
        }
        if let number = result as? NSNumber {
            return number.boolValue
        }
        return false
    }

    private static func resolve(_ node: Any, data: [String: Any]) -> Any {
        guard let dict = node as? [String: Any], let key = dict.keys.first else {
            return scalarValue(node, data: data)
        }

        let value = dict[key]
        switch key {
        case "var":
            return lookup(value, data: data)
        case "and":
            let items = (value as? [Any]) ?? []
            return items.allSatisfy { truthy(resolve($0, data: data)) }
        case "or":
            let items = (value as? [Any]) ?? []
            return items.contains { truthy(resolve($0, data: data)) }
        case "==":
            let args = arguments(value, data: data)
            guard args.count == 2 else { return false }
            return stringify(args[0]) == stringify(args[1])
        case ">":
            let args = numericArguments(value, data: data)
            guard args.count == 2 else { return false }
            return args[0] > args[1]
        case ">=":
            let args = numericArguments(value, data: data)
            guard args.count == 2 else { return false }
            return args[0] >= args[1]
        case "<":
            let args = numericArguments(value, data: data)
            guard args.count == 2 else { return false }
            return args[0] < args[1]
        case "<=":
            let args = numericArguments(value, data: data)
            guard args.count == 2 else { return false }
            return args[0] <= args[1]
        default:
            return false
        }
    }

    private static func lookup(_ node: Any?, data: [String: Any]) -> Any {
        if let key = node as? String {
            return data[key] ?? NSNull()
        }

        if let values = node as? [Any], let key = values.first as? String {
            return data[key] ?? NSNull()
        }

        return NSNull()
    }

    private static func scalarValue(_ node: Any, data: [String: Any]) -> Any {
        if let dict = node as? [String: Any] {
            return resolve(dict, data: data)
        }
        if let array = node as? [Any] {
            return array.map { resolve($0, data: data) }
        }
        return node
    }

    private static func arguments(_ node: Any?, data: [String: Any]) -> [Any] {
        ((node as? [Any]) ?? []).map { resolve($0, data: data) }
    }

    private static func numericArguments(_ node: Any?, data: [String: Any]) -> [Double] {
        arguments(node, data: data).compactMap { asDouble($0) }
    }

    private static func asDouble(_ value: Any) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func truthy(_ value: Any) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return !string.isEmpty }
        if value is NSNull { return false }
        return true
    }

    private static func stringify(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }
}
