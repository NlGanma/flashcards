import Foundation

/// Pulls finished cards out of a model reply while it is still streaming, so they can
/// appear one by one instead of all at once after a long wait.
///
/// The scanner tracks JSON structure byte by byte: strings, escapes and nesting. Any
/// object that is an element of an array, and isn't itself inside such an object, is a
/// card, whether the reply is `{"cards":[…]}`, a bare `[…]`, or wrapped in a Markdown
/// fence. Arrays nested inside a card are left to the card decoder.
///
/// Reasoning models open with a `<think>…</think>` block that can contain braces of its
/// own, so nothing is scanned until it has closed.
public struct CardStreamParser {

    private var preamble = ""
    private var started = false
    private var bytes: [UInt8] = []
    private var stack: [UInt8] = []
    private var inString = false
    private var escaped = false
    private var candidateStart: Int?
    private var candidateDepth = 0
    private var emitted = 0

    public init() {}

    /// Feed the next piece of the reply; returns every card it completed.
    public mutating func consume(_ text: String) -> [ModelCard] {
        if started { return scan(Array(text.utf8)) }

        preamble += text
        preamble = preamble.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "",
                                                 options: .regularExpression)
        if preamble.contains("<think>") { return [] }
        guard let start = preamble.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            // Keep only enough to recognise a "<think>" split across two pieces.
            if preamble.count > 16 { preamble = String(preamble.suffix(16)) }
            return []
        }
        started = true
        let json = String(preamble[start...])
        preamble = ""
        return scan(Array(json.utf8))
    }

    /// Call once the stream ends. A model asked for one card sometimes answers with a
    /// bare object rather than an array of one; that is recovered here.
    public mutating func finish() -> [ModelCard] {
        guard emitted == 0, let first = bytes.firstIndex(of: UInt8(ascii: "{")),
              let last = bytes.lastIndex(of: UInt8(ascii: "}")), first < last else { return [] }
        guard let card = ModelCard(json: Data(bytes[first...last])) else { return [] }
        emitted += 1
        return [card]
    }

    private mutating func scan(_ input: [UInt8]) -> [ModelCard] {
        var cards: [ModelCard] = []
        for byte in input {
            bytes.append(byte)
            let index = bytes.count - 1
            if inString {
                if escaped { escaped = false }
                else if byte == UInt8(ascii: "\\") { escaped = true }
                else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""):
                inString = true
            case UInt8(ascii: "{"):
                if candidateStart == nil, stack.last == UInt8(ascii: "[") {
                    candidateStart = index
                    candidateDepth = stack.count
                }
                stack.append(byte)
            case UInt8(ascii: "["):
                stack.append(byte)
            case UInt8(ascii: "}"):
                if stack.last == UInt8(ascii: "{") { stack.removeLast() }
                if let start = candidateStart, stack.count == candidateDepth {
                    candidateStart = nil
                    if let card = ModelCard(json: Data(bytes[start...index])) {
                        cards.append(card)
                        emitted += 1
                    }
                }
            case UInt8(ascii: "]"):
                if stack.last == UInt8(ascii: "[") { stack.removeLast() }
            default:
                break
            }
        }
        return cards
    }
}
