import Foundation

#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

/// Evaluates n8n parameter expressions on-device.
///
/// n8n parameters are either literals or expressions: a leading `=` marks an
/// expression, and `{{ … }}` segments hold JavaScript evaluated against the
/// current item's JSON (bound as `$json`). We evaluate those segments with
/// **JavaScriptCore** (Apple's built-in JS engine — App-Store-safe; no
/// downloaded code), interpolating text or returning a typed value when the
/// whole parameter is a single expression.
enum N8nExpression {
    static func evaluate(_ raw: String, item: FlowValue) -> FlowValue {
        guard raw.hasPrefix("=") else { return .text(raw) }      // literal
        let body = String(raw.dropFirst())
        guard body.contains("{{") else { return .text(body) }

        let json = (item.toFoundation() as? [String: Any]) ?? [:]

        // Whole-value single expression → return its typed result.
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{{"), trimmed.hasSuffix("}}"),
           let inner = stripBraces(trimmed), !inner.contains("{{") {
            return evalExpression(inner, json: json) ?? .text("")
        }

        // Otherwise interpolate every {{ … }} segment into a string.
        var result = body
        while let open = result.range(of: "{{"),
              let close = result.range(of: "}}", range: open.upperBound ..< result.endIndex) {
            let expr = String(result[open.upperBound ..< close.lowerBound])
            let text = evalExpression(expr, json: json)?.asText ?? ""
            result.replaceSubrange(open.lowerBound ..< close.upperBound, with: text)
        }
        return .text(result)
    }

    private static func stripBraces(_ s: String) -> String? {
        guard s.hasPrefix("{{"), s.hasSuffix("}}") else { return nil }
        return String(s.dropFirst(2).dropLast(2))
    }

    private static func evalExpression(_ expr: String, json: [String: Any]) -> FlowValue? {
        #if canImport(JavaScriptCore)
        guard let context = JSContext() else { return nil }
        context.setObject(json, forKeyedSubscript: "$json" as NSString)
        guard let value = context.evaluateScript(expr) else { return nil }
        if value.isUndefined || value.isNull { return .null }
        if value.isBoolean { return .bool(value.toBool()) }
        if value.isNumber { return .number(value.toDouble()) }
        if value.isString { return .text(value.toString() ?? "") }
        return .text(value.toString() ?? "")   // object/array → stringified
        #else
        return .text("")
        #endif
    }
}
