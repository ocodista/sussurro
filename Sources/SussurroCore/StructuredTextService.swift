import Foundation

public enum StructuredOutputError: LocalizedError, Equatable {
    case invalidSchema(String)
    case unsupportedSchemaKeyword(String)
    case missingRequiredValue(String)
    case validationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidSchema(message): return "Invalid JSON schema: \(message)"
        case let .unsupportedSchemaKeyword(keyword): return "Unsupported Phase 1 JSON schema keyword: \(keyword)"
        case let .missingRequiredValue(name): return "Could not extract required field '\(name)' from text."
        case let .validationFailed(message): return "Structured output does not match schema: \(message)"
        }
    }
}

public struct StructuredTextService: Sendable {
    public init() {}

    public func structure(text: String, schemaData: Data) throws -> [String: Any] {
        let schema = try JSONSchemaValidator.decodeSchema(schemaData)
        guard (schema["type"] as? String) == "object",
              let properties = schema["properties"] as? [String: Any]
        else {
            throw StructuredOutputError.invalidSchema("the root must be an object with properties")
        }

        let labels = Self.labeledValues(in: text)
        let required = Set(schema["required"] as? [String] ?? [])
        var result: [String: Any] = [:]

        for (name, untypedPropertySchema) in properties {
            guard let propertySchema = untypedPropertySchema as? [String: Any] else {
                throw StructuredOutputError.invalidSchema("property '\(name)' must be a schema object")
            }
            if let constant = propertySchema["const"] {
                result[name] = constant
                continue
            }
            if let raw = labels[name.lowercased()] {
                result[name] = try Self.convert(raw, schema: propertySchema, field: name)
            } else if let defaultValue = propertySchema["default"] {
                result[name] = defaultValue
            } else if required.contains(name) {
                throw StructuredOutputError.missingRequiredValue(name)
            }
        }

        try JSONSchemaValidator().validate(instance: result, schema: schema)
        return result
    }

    private static func labeledValues(in text: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \Character.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            values[key] = value
        }
        return values
    }

    private static func convert(_ value: String, schema: [String: Any], field: String) throws -> Any {
        switch schema["type"] as? String {
        case "string", nil:
            return value
        case "integer":
            guard let converted = Int(value) else {
                throw StructuredOutputError.validationFailed("'\(field)' is not an integer")
            }
            return converted
        case "number":
            guard let converted = Double(value) else {
                throw StructuredOutputError.validationFailed("'\(field)' is not a number")
            }
            return converted
        case "boolean":
            switch value.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: throw StructuredOutputError.validationFailed("'\(field)' is not a boolean")
            }
        case "null":
            guard value.lowercased() == "null" else {
                throw StructuredOutputError.validationFailed("'\(field)' is not null")
            }
            return NSNull()
        default:
            throw StructuredOutputError.validationFailed("'\(field)' uses a type that label extraction cannot produce")
        }
    }
}

public struct JSONSchemaValidator: Sendable {
    private static let supportedKeywords: Set<String> = [
        "$schema", "$id", "title", "description", "type", "properties", "required",
        "additionalProperties", "items", "enum", "const", "default", "minLength",
        "maxLength", "minimum", "maximum", "minItems", "maxItems"
    ]

    public init() {}

    public func validate(instance: Any, schemaData: Data) throws {
        try validate(instance: instance, schema: Self.decodeSchema(schemaData))
    }

    public func validate(instance: Any, schema: [String: Any]) throws {
        try Self.checkSupportedKeywords(schema)
        try Self.validateValue(instance, schema: schema, path: "$")
    }

    static func decodeSchema(_ data: Data) throws -> [String: Any] {
        do {
            guard let schema = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw StructuredOutputError.invalidSchema("root is not an object")
            }
            return schema
        } catch let error as StructuredOutputError {
            throw error
        } catch {
            throw StructuredOutputError.invalidSchema(error.localizedDescription)
        }
    }

    private static func checkSupportedKeywords(_ schema: [String: Any]) throws {
        for key in schema.keys where !supportedKeywords.contains(key) {
            throw StructuredOutputError.unsupportedSchemaKeyword(key)
        }
        if let properties = schema["properties"] as? [String: Any] {
            for value in properties.values {
                guard let child = value as? [String: Any] else {
                    throw StructuredOutputError.invalidSchema("property schema is not an object")
                }
                try checkSupportedKeywords(child)
            }
        }
        if let items = schema["items"] as? [String: Any] {
            try checkSupportedKeywords(items)
        }
    }

    private static func validateValue(_ value: Any, schema: [String: Any], path: String) throws {
        if let constant = schema["const"], !jsonEqual(value, constant) {
            throw StructuredOutputError.validationFailed("\(path) does not equal const")
        }
        if let allowed = schema["enum"] as? [Any], !allowed.contains(where: { jsonEqual(value, $0) }) {
            throw StructuredOutputError.validationFailed("\(path) is not in enum")
        }

        guard let type = schema["type"] as? String else { return }
        switch type {
        case "object":
            guard let object = value as? [String: Any] else { throw typeError(path, type) }
            let properties = schema["properties"] as? [String: Any] ?? [:]
            for name in schema["required"] as? [String] ?? [] where object[name] == nil {
                throw StructuredOutputError.validationFailed("\(path).\(name) is required")
            }
            if (schema["additionalProperties"] as? Bool) == false {
                let unknown = Set(object.keys).subtracting(properties.keys)
                if let name = unknown.sorted().first {
                    throw StructuredOutputError.validationFailed("\(path).\(name) is not allowed")
                }
            }
            for (name, childValue) in object {
                if let childSchema = properties[name] as? [String: Any] {
                    try validateValue(childValue, schema: childSchema, path: "\(path).\(name)")
                }
            }
        case "array":
            guard let array = value as? [Any] else { throw typeError(path, type) }
            try checkCount(array.count, schema: schema, path: path, minimumKey: "minItems", maximumKey: "maxItems")
            if let itemSchema = schema["items"] as? [String: Any] {
                for (index, item) in array.enumerated() {
                    try validateValue(item, schema: itemSchema, path: "\(path)[\(index)]")
                }
            }
        case "string":
            guard let string = value as? String else { throw typeError(path, type) }
            try checkCount(string.count, schema: schema, path: path, minimumKey: "minLength", maximumKey: "maxLength")
        case "integer":
            guard isNumber(value), floor(number(value)) == number(value) else { throw typeError(path, type) }
            try checkNumber(number(value), schema: schema, path: path)
        case "number":
            guard isNumber(value) else { throw typeError(path, type) }
            try checkNumber(number(value), schema: schema, path: path)
        case "boolean":
            guard value is Bool else { throw typeError(path, type) }
        case "null":
            guard value is NSNull else { throw typeError(path, type) }
        default:
            throw StructuredOutputError.invalidSchema("unknown type '\(type)'")
        }
    }

    private static func checkCount(_ count: Int, schema: [String: Any], path: String, minimumKey: String, maximumKey: String) throws {
        if let minimum = schema[minimumKey] as? Int, count < minimum {
            throw StructuredOutputError.validationFailed("\(path) is shorter than \(minimumKey)")
        }
        if let maximum = schema[maximumKey] as? Int, count > maximum {
            throw StructuredOutputError.validationFailed("\(path) is longer than \(maximumKey)")
        }
    }

    private static func checkNumber(_ value: Double, schema: [String: Any], path: String) throws {
        if let minimum = (schema["minimum"] as? NSNumber)?.doubleValue, value < minimum {
            throw StructuredOutputError.validationFailed("\(path) is below minimum")
        }
        if let maximum = (schema["maximum"] as? NSNumber)?.doubleValue, value > maximum {
            throw StructuredOutputError.validationFailed("\(path) is above maximum")
        }
    }

    private static func typeError(_ path: String, _ type: String) -> StructuredOutputError {
        .validationFailed("\(path) is not \(type)")
    }

    private static func isNumber(_ value: Any) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    }

    private static func number(_ value: Any) -> Double { (value as! NSNumber).doubleValue }

    private static func jsonEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        guard JSONSerialization.isValidJSONObject([lhs]), JSONSerialization.isValidJSONObject([rhs]),
              let left = try? JSONSerialization.data(withJSONObject: [lhs], options: [.sortedKeys]),
              let right = try? JSONSerialization.data(withJSONObject: [rhs], options: [.sortedKeys])
        else { return false }
        return left == right
    }
}
