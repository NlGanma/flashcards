import XCTest
@testable import VocabKit

/// Covers the layer that puts example sentences, curated corrections, and hand edits onto
/// a parsed card.
final class CardContentTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VocabKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Helpers

    private func bank(_ json: String) throws -> ContentBank {
        try ContentBank.decode(Data(json.utf8))
    }

    private func card(_ word: String, _ senses: [Sense]) -> Flashcard {
        Flashcard(id: TextNormalizer.normalizedKey(word), word: word,
                  senses: senses, sourceSets: ["Practice 1"])
    }

    // MARK: - ContentBank

    func testBankAttachesExampleToMatchingDefinition() throws {
        let bank = try bank("""
        {"v":1,"words":{"keen":{"s":[
          {"m":"敏锐的","ex":[{"en":"Her keen eye caught it.","zh":"她敏锐的眼光发现了它。"}]}
        ]}}}
        """)
        let senses = bank.resolvedSenses(forKey: "keen",
                                         senses: [Sense(partOfSpeech: "adj.", definition: "敏锐的")])
        XCTAssertEqual(senses.count, 1)
        XCTAssertEqual(senses[0].examples.first?.english, "Her keen eye caught it.")
        XCTAssertEqual(senses[0].examples.first?.chinese, "她敏锐的眼光发现了它。")
        // The parsed definition and part of speech survive untouched.
        XCTAssertEqual(senses[0].definition, "敏锐的")
        XCTAssertEqual(senses[0].partOfSpeech, "adj.")
    }

    func testBankMatchesDefinitionIgnoringWhitespace() throws {
        let bank = try bank("""
        {"v":1,"words":{"keen":{"s":[{"m":"敏锐的， 热心的","ex":[{"en":"E","zh":"C"}]}]}}}
        """)
        let senses = bank.resolvedSenses(forKey: "keen",
                                         senses: [Sense(partOfSpeech: "adj.", definition: "敏锐的，热心的")])
        XCTAssertEqual(senses[0].examples.first?.english, "E")
    }

    func testBankMatchesTheOnlySenseEvenIfTheDefinitionDrifted() throws {
        let bank = try bank("""
        {"v":1,"words":{"keen":{"s":[{"m":"敏锐的","ex":[{"en":"E","zh":"C"}]}]}}}
        """)
        let senses = bank.resolvedSenses(forKey: "keen",
                                         senses: [Sense(partOfSpeech: "adj.", definition: "敏锐的（新写法）")])
        XCTAssertEqual(senses[0].examples.first?.english, "E")
    }

    func testBankDoesNotGuessWhenAWordHasSeveralSenses() throws {
        let bank = try bank("""
        {"v":1,"words":{"keen":{"s":[{"m":"敏锐的","ex":[{"en":"E","zh":"C"}]}]}}}
        """)
        let senses = bank.resolvedSenses(forKey: "keen", senses: [
            Sense(partOfSpeech: "adj.", definition: "完全不同的释义"),
            Sense(partOfSpeech: "n.", definition: "挽歌")
        ])
        XCTAssertTrue(senses[0].examples.isEmpty)
        XCTAssertTrue(senses[1].examples.isEmpty)
    }

    func testBankAppliesDefinitionCorrection() throws {
        let bank = try bank("""
        {"v":1,"words":{"keen":{"s":[
          {"m":"锋利的刀","d":"敏锐的","p":"adj.","ex":[{"en":"E","zh":"C"}]}
        ]}}}
        """)
        let senses = bank.resolvedSenses(forKey: "keen",
                                         senses: [Sense(partOfSpeech: "n.", definition: "锋利的刀")])
        XCTAssertEqual(senses[0].definition, "敏锐的")
        XCTAssertEqual(senses[0].partOfSpeech, "adj.")
    }

    func testBankDropsAnUnsupportedDefinition() throws {
        let bank = try bank("""
        {"v":1,"words":{"keen":{"s":[{"m":"敏锐的","ex":[{"en":"E","zh":"C"}]}],"x":["查无此义"]}}}
        """)
        let senses = bank.resolvedSenses(forKey: "keen", senses: [
            Sense(partOfSpeech: "adj.", definition: "敏锐的"),
            Sense(partOfSpeech: "n.", definition: "查无此义")
        ])
        XCTAssertEqual(senses.count, 1)
        XCTAssertEqual(senses[0].definition, "敏锐的")
    }

    /// The safety net on the whole correction mechanism: a bad drop must never leave a
    /// card with nothing on it.
    func testDroppingEveryDefinitionKeepsTheOriginal() throws {
        let bank = try bank("""
        {"v":1,"words":{"keen":{"x":["敏锐的"]}}}
        """)
        let original = [Sense(partOfSpeech: "adj.", definition: "敏锐的")]
        XCTAssertEqual(bank.resolvedSenses(forKey: "keen", senses: original), original)
    }

    func testUnknownWordIsLeftAlone() throws {
        let bank = try bank("""
        {"v":1,"words":{"keen":{"s":[{"m":"敏锐的","ex":[{"en":"E","zh":"C"}]}]}}}
        """)
        let senses = [Sense(partOfSpeech: "n.", definition: "先见之明")]
        XCTAssertEqual(bank.resolvedSenses(forKey: "foresight", senses: senses), senses)
    }

    func testEmptyExampleTextIsTreatedAsNoExample() throws {
        let bank = try bank("""
        {"v":1,"words":{"keen":{"s":[{"m":"敏锐的","ex":[{"en":"","zh":""}]}]}}}
        """)
        let senses = bank.resolvedSenses(forKey: "keen",
                                         senses: [Sense(partOfSpeech: "adj.", definition: "敏锐的")])
        XCTAssertTrue(senses[0].examples.isEmpty)
    }

    func testBankCorrectsAMangledDisplayWord() throws {
        let bank = try bank("""
        {"v":1,"words":{"vicarious (vicarious)":{"w":"vicarious","s":[
          {"m":"间接体验的，代理的","ex":[{"en":"E","zh":"C"}]}
        ]}}}
        """)
        let key = TextNormalizer.normalizedKey("vicarious (vicarious)")
        XCTAssertEqual(bank.displayWord(forKey: key), "vicarious")
        XCTAssertNil(bank.displayWord(forKey: "keen"))

        let resolver = CardContentResolver(bank: bank, edits: nil)
        let fixed = resolver.curated(Flashcard(id: key, word: "vicarious (vicarious)",
                                               senses: [Sense(partOfSpeech: "adj.", definition: "间接体验的，代理的")],
                                               sourceSets: []))
        XCTAssertEqual(fixed.word, "vicarious")
        // The key is the persisted identity and must survive a display fix untouched.
        XCTAssertEqual(fixed.key, key)
    }

    func testBundledBankLoads() {
        // Proves the resource actually ships and parses inside the built product.
        XCTAssertGreaterThan(ContentBank.bundled.wordCount, 0)
        XCTAssertGreaterThan(ContentBank.bundled.exampleCount, 0)
    }

    /// Guards the curated file itself: every record must carry both languages, and a drop
    /// must never be the only thing said about a word.
    func testBundledBankContentIsWellFormed() throws {
        let bank = ContentBank.bundled
        XCTAssertGreaterThan(bank.exampleCount, 400, "the curated file looks truncated")

        let probe = Sense(partOfSpeech: "adj.", definition: "敏锐的，热心的，渴望的")
        let resolved = bank.resolvedSenses(forKey: "keen", senses: [probe])
        XCTAssertEqual(resolved.count, 1)
        XCTAssertFalse(resolved[0].examples.isEmpty, "a known curated word lost its examples")
        XCTAssertFalse(resolved[0].examples.first?.english.isEmpty ?? true)
        XCTAssertFalse(resolved[0].examples.first?.chinese.isEmpty ?? true)
    }

    // MARK: - Glosses

    func testDefinitionSplitsIntoGlosses() {
        XCTAssertEqual(Sense.splitGlosses("恶棍，歹徒；不法的，邪恶的"),
                       ["恶棍", "歹徒", "不法的", "邪恶的"])
        XCTAssertEqual(Sense.splitGlosses("敏锐的"), ["敏锐的"])
        // A separator inside a parenthetical belongs to the gloss, not between glosses.
        XCTAssertEqual(Sense.splitGlosses("没药（一种中药、香料）"), ["没药（一种中药、香料）"])
        XCTAssertEqual(Sense.splitGlosses("（价格等）过高的，奢侈的"), ["（价格等）过高的", "奢侈的"])
        XCTAssertEqual(Sense.splitGlosses(""), [])
    }

    func testBankAttachesOneExamplePerGloss() throws {
        let bank = try bank("""
        {"v":1,"words":{"miscreant":{"s":[{"m":"恶棍，歹徒；不法的，邪恶的","ex":[
          {"g":"恶棍","en":"E1","zh":"Z1恶棍"},
          {"g":"歹徒","en":"E2","zh":"Z2歹徒"},
          {"g":"不法的","en":"E3","zh":"Z3不法的"},
          {"g":"邪恶的","en":"E4","zh":"Z4邪恶的"}
        ]}]}}}
        """)
        let senses = bank.resolvedSenses(forKey: "miscreant",
                                         senses: [Sense(partOfSpeech: "n. / adj.",
                                                        definition: "恶棍，歹徒；不法的，邪恶的")])
        XCTAssertEqual(senses.count, 1)
        XCTAssertEqual(senses[0].examples.count, 4)
        XCTAssertEqual(senses[0].examples.map(\.gloss), ["恶棍", "歹徒", "不法的", "邪恶的"])
        // Every gloss of the definition is covered by exactly one sentence.
        XCTAssertEqual(Set(senses[0].examples.map(\.gloss)), Set(senses[0].glosses))
    }

    /// The card-edit file written before examples became a list must still load.
    func testLegacySingleExampleDecodes() throws {
        let legacy = """
        {"partOfSpeech":"adj.","definition":"敏锐的","example":{"gloss":"","english":"E","chinese":"C"}}
        """
        let sense = try JSONDecoder().decode(Sense.self, from: Data(legacy.utf8))
        XCTAssertEqual(sense.examples.count, 1)
        XCTAssertEqual(sense.examples.first?.english, "E")
    }

    // MARK: - CardEditsStore

    func testEditRoundTripsThroughDisk() {
        let store = CardEditsStore(directory: tempDir)
        let edit = CardEdit(word: "Keen", senses: [
            Sense(partOfSpeech: "adj.", definition: "敏锐的",
                  example: Example(english: "E", chinese: "C"))
        ])
        store.save(edit, for: "keen")
        store.flush()

        let reloaded = CardEditsStore(directory: tempDir)
        XCTAssertEqual(reloaded.edit(for: "keen"), edit)
        XCTAssertEqual(reloaded.count, 1)
    }

    func testRevertRemovesTheEdit() {
        let store = CardEditsStore(directory: tempDir)
        store.save(CardEdit(word: "Keen", senses: [Sense(partOfSpeech: "adj.", definition: "敏锐的")]),
                   for: "keen")
        store.revert(key: "keen")
        store.flush()
        XCTAssertNil(CardEditsStore(directory: tempDir).edit(for: "keen"))
    }

    // MARK: - Resolver

    func testUserEditWinsOverTheBank() throws {
        let bank = try bank("""
        {"v":1,"words":{"keen":{"s":[{"m":"敏锐的","ex":[{"en":"bank sentence","zh":"C"}]}]}}}
        """)
        let edits = CardEditsStore(directory: tempDir)
        edits.save(CardEdit(word: "keen (adj.)", senses: [
            Sense(partOfSpeech: "adj.", definition: "我的释义",
                  example: Example(english: "my sentence", chinese: "我的句子"))
        ]), for: "keen")

        let resolver = CardContentResolver(bank: bank, edits: edits)
        let resolved = resolver.resolve(card("keen", [Sense(partOfSpeech: "adj.", definition: "敏锐的")]))

        XCTAssertEqual(resolved.word, "keen (adj.)")
        XCTAssertEqual(resolved.senses.first?.definition, "我的释义")
        XCTAssertEqual(resolved.senses.first?.examples.first?.english, "my sentence")
        // Identity never moves, so known-word memory keeps matching.
        XCTAssertEqual(resolved.key, "keen")
        // …and the curated view still shows what the file plus the bank say.
        XCTAssertEqual(resolver.curated(card("keen", [Sense(partOfSpeech: "adj.", definition: "敏锐的")]))
                        .senses.first?.examples.first?.english, "bank sentence")
    }

    func testDeckBuilderAppliesTheResolver() throws {
        let bank = try bank("""
        {"v":1,"words":{"keen":{"s":[{"m":"敏锐的","ex":[{"en":"E","zh":"C"}]}]}}}
        """)
        let set = PracticeSet(name: "Practice 1", items: [
            VocabItem(english: "keen", partOfSpeech: "adj.", definition: "敏锐的", setName: "Practice 1"),
            VocabItem(english: "foresight", partOfSpeech: "n.", definition: "远见", setName: "Practice 1")
        ])
        let deck = DeckBuilder().buildOrdered(
            from: [set], filter: .includeKnown, knownKeys: [],
            resolver: CardContentResolver(bank: bank, edits: CardEditsStore(directory: tempDir)))

        XCTAssertEqual(deck.count, 2)
        XCTAssertTrue(deck[0].hasExamples)
        XCTAssertFalse(deck[1].hasExamples)
    }

    // MARK: - Session

    func testReplaceCardSwapsContentWithoutMovingPosition() {
        let session = StudySession(cards: [card("keen", [Sense(partOfSpeech: "adj.", definition: "敏锐的")]),
                                           card("foresight", [Sense(partOfSpeech: "n.", definition: "远见")])],
                                   filter: .includeKnown, selectedSetNames: ["Practice 1"])
        session.goNext()
        session.replaceCard(card("keen", [Sense(partOfSpeech: "adj.", definition: "改过的释义")]))

        XCTAssertEqual(session.currentIndex, 1)
        XCTAssertEqual(session.currentCard?.word, "foresight")
        XCTAssertEqual(session.cards[0].senses.first?.definition, "改过的释义")
    }

    func testFlippingBackClosesTheExamplePanel() {
        let session = StudySession(cards: [card("keen", [Sense(partOfSpeech: "adj.", definition: "敏锐的")])],
                                   filter: .includeKnown, selectedSetNames: ["Practice 1"])
        session.flip()
        session.isShowingSentence = true
        session.flip()
        XCTAssertFalse(session.isShowingBack)
        XCTAssertFalse(session.isShowingSentence)
    }

    func testNavigationClosesTheExamplePanel() {
        let session = StudySession(cards: [card("keen", [Sense(partOfSpeech: "adj.", definition: "敏锐的")]),
                                           card("foresight", [Sense(partOfSpeech: "n.", definition: "远见")])],
                                   filter: .includeKnown, selectedSetNames: ["Practice 1"])
        session.showBack()
        session.isShowingSentence = true
        session.goNext()
        XCTAssertFalse(session.isShowingSentence)

        session.showBack()
        session.isShowingSentence = true
        session.goPrevious()
        XCTAssertFalse(session.isShowingSentence)
    }
}
