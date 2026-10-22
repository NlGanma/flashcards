import Foundation
import Testing
@testable import VocabKit

@Suite("Card stream parser")
struct CardStreamParserTests {

    /// Feed a reply in pieces of `size` characters and collect every card.
    private func parse(_ reply: String, pieceSize size: Int = 7) -> [ModelCard] {
        var parser = CardStreamParser()
        var cards: [ModelCard] = []
        var rest = Substring(reply)
        while !rest.isEmpty {
            cards += parser.consume(String(rest.prefix(size)))
            rest = rest.dropFirst(size)
        }
        return cards + parser.finish()
    }

    let reply = #"""
        {"cards":[
          {"front":"osmosis","back":"Diffusion of water across a membrane.","tag":"n.","section":"Cells"},
          {"front":"ATP","back":"The cell's energy currency {not a brace}.","example":"Muscles burn \"ATP\"."}
        ]}
        """#

    @Test func cardsArriveAsSoonAsTheirObjectCloses() {
        var parser = CardStreamParser()
        let firstClose = reply.range(of: "\"Cells\"}")!.upperBound
        let head = String(reply[..<firstClose])
        let tail = String(reply[firstClose...])

        let early = parser.consume(head)
        #expect(early.map(\.front) == ["osmosis"])
        #expect(early.first?.section == "Cells")
        #expect(parser.consume(tail).map(\.front) == ["ATP"])
    }

    @Test(arguments: [1, 2, 3, 5, 13, 1000])
    func everySplitPointGivesTheSameCards(size: Int) {
        let cards = parse(reply, pieceSize: size)
        #expect(cards.map(\.front) == ["osmosis", "ATP"])
        #expect(cards[1].back == "The cell's energy currency {not a brace}.")
        #expect(cards[1].example == "Muscles burn \"ATP\".")
    }

    @Test func aBareArrayAndAMarkdownFenceBothWork() {
        #expect(parse(#"[{"front":"a","back":"b"}]"#).map(\.front) == ["a"])
        #expect(parse("Here you go:\n```json\n{\"cards\":[{\"front\":\"a\",\"back\":\"b\"}]}\n```").map(\.back) == ["b"])
    }

    @Test func arraysInsideACardDontSplitIt() {
        let cards = parse(#"{"cards":[{"front":"a","back":"b","extra":[{"x":1}]},{"front":"c","back":"d"}]}"#)
        #expect(cards.map(\.front) == ["a", "c"])
    }

    @Test func thinkingIsSkippedEvenWithBracesInIt() {
        let cards = parse("<think>maybe {\"front\":\"no\",\"back\":\"no\"} in [a list]</think>\n"
                          + #"{"cards":[{"front":"yes","back":"ok"}]}"#, pieceSize: 4)
        #expect(cards.map(\.front) == ["yes"])
    }

    @Test func cardsMissingAFaceAreDropped() {
        let cards = parse(#"{"cards":[{"front":"a","back":""},{"front":"","back":"b"},{"front":"c","back":"d"}]}"#)
        #expect(cards.map(\.front) == ["c"])
    }

    @Test func commonFieldNamesAreAccepted() {
        let cards = parse(#"[{"term":"cajole","definition":"to coax","partOfSpeech":"v.","sentence":"She cajoled him.","translation":"她哄他。","id":"c4"}]"#)
        let card = try! #require(cards.first)
        #expect(card == ModelCard(ref: "c4", front: "cajole", back: "to coax", tag: "v.",
                                  example: "She cajoled him.", exampleNote: "她哄他。"))
    }

    @Test func emphasisMarkersAreRemoved() {
        #expect(parse(#"[{"front":"**osmosis**","back":"`water` moves"}]"#).first?.front == "osmosis")
        #expect(parse(#"[{"front":"**osmosis**","back":"`water` moves"}]"#).first?.back == "water moves")
    }

    @Test func aSingleBareObjectIsRecoveredAtTheEnd() {
        var parser = CardStreamParser()
        #expect(parser.consume(#"{"front":"a","back":"b"}"#).isEmpty)
        #expect(parser.finish().map(\.front) == ["a"])
    }

    @Test func chineseTextSurvivesByteLevelScanning() {
        let cards = parse(#"[{"front":"线粒体","back":"细胞的“能量工厂”"}]"#, pieceSize: 1)
        #expect(cards.first?.back == "细胞的“能量工厂”")
    }

    @Test func aGeneratedCardBecomesOneSenseWithItsExample() {
        let card = GeneratedCard(front: "cajole", back: "to coax", tag: "v.",
                                 example: "She cajoled him.", exampleNote: "她哄他。")
        #expect(card.sense == Sense(partOfSpeech: "v.", definition: "to coax",
                                    examples: [Example(english: "She cajoled him.", chinese: "她哄他。")]))
        #expect(GeneratedCard(front: "a", back: "b").sense.examples.isEmpty)
    }

    @Test func savedCardsDecodeWithMissingOptionalFields() throws {
        let card = try JSONDecoder().decode(GeneratedCard.self, from: Data(#"{"front":"a","back":"b"}"#.utf8))
        #expect(card.front == "a" && card.tag.isEmpty && card.section.isEmpty)
    }
}
