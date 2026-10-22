import Testing
@testable import VocabKit

@Suite("Markdown outline")
struct MarkdownOutlineTests {

    @Test func leadingH1IsTheTitleAndH2sAreSets() {
        let outline = MarkdownOutline(markdown: """
            # Cell Biology

            Cells are the basic unit of life.

            ## Mitochondria
            Make ATP.

            ## Ribosomes
            Build proteins.
            """, fallbackTitle: "notes")

        #expect(outline.title == "Cell Biology")
        #expect(outline.sections.map(\.title) == ["Cell Biology", "Mitochondria", "Ribosomes"])
        #expect(outline.sections[0].body == "Cells are the basic unit of life.")
        #expect(outline.sections[1].body == "Make ATP.")
    }

    @Test func severalH1sAreSetsAndTheFileNameIsTheTitle() {
        let outline = MarkdownOutline(markdown: """
            # Week 1
            abate
            # Week 2
            candid
            """, fallbackTitle: "vocab")
        #expect(outline.title == "vocab")
        #expect(outline.sections.map(\.title) == ["Week 1", "Week 2"])
    }

    @Test func subheadingsStayInsideTheirSection() {
        let outline = MarkdownOutline(markdown: """
            ## Verbs
            ### abate
            to lessen
            ### cajole
            to coax
            ## Nouns
            ### acumen
            sharpness
            """, fallbackTitle: "f")
        #expect(outline.sections.map(\.title) == ["Verbs", "Nouns"])
        #expect(outline.sections[0].body.contains("### cajole"))
    }

    @Test func noHeadingsIsOneSectionNamedAfterTheFile() {
        let outline = MarkdownOutline(markdown: "Just a paragraph.\n\nAnd another.",
                                      fallbackTitle: "scratch")
        #expect(outline.sections == [.init(title: "scratch", body: "Just a paragraph.\n\nAnd another.")])
    }

    @Test func hashesInCodeFencesAreNotHeadings() {
        let outline = MarkdownOutline(markdown: """
            ## Shell
            ```bash
            # not a heading
            echo hi
            ```
            ## Python
            print(1)
            """, fallbackTitle: "f")
        #expect(outline.sections.map(\.title) == ["Shell", "Python"])
        #expect(outline.sections[0].body.contains("# not a heading"))
    }

    @Test func frontMatterAndCommentsAreDropped() {
        let outline = MarkdownOutline(markdown: """
            ---
            tags: [bio]
            ---
            # Title
            <!-- draft note -->
            ## A
            text
            """, fallbackTitle: "f")
        #expect(outline.title == "Title")
        #expect(outline.sections.map(\.title) == ["A"])
        #expect(!outline.sections[0].body.contains("draft"))
    }

    @Test func headingMarkupIsStrippedFromSetNames() {
        let outline = MarkdownOutline(markdown: "## **Krebs** cycle [ATP](https://x.y) ##\ntext",
                                      fallbackTitle: "f")
        #expect(outline.sections.map(\.title) == ["Krebs cycle ATP"])
    }

    @Test func emptySectionsAreSkippedAndDuplicatesNumbered() {
        let outline = MarkdownOutline(markdown: """
            ## Examples
            one
            ## Empty
            ## Examples
            two
            """, fallbackTitle: "f")
        #expect(outline.sections.map(\.title) == ["Examples", "Examples (2)"])
    }

    @Test func smallSectionsShareAChunk() {
        let outline = MarkdownOutline(markdown: "## A\none\n## B\ntwo\n## C\nthree", fallbackTitle: "f")
        let chunks = outline.chunks(maxTokens: 1500)
        #expect(chunks.count == 1)
        #expect(chunks[0].sections == ["A", "B", "C"])
        #expect(chunks[0].text == "## A\n\none\n\n## B\n\ntwo\n\n## C\n\nthree")
    }

    @Test func aLongSectionSplitsBetweenParagraphsAndKeepsItsHeading() {
        let paragraph = Array(repeating: "word", count: 200).joined(separator: " ")   // ~280 tokens
        let body = (1...6).map { "\($0) \(paragraph)" }.joined(separator: "\n\n")
        let outline = MarkdownOutline(markdown: "## Long\n\(body)", fallbackTitle: "f")
        let chunks = outline.chunks(maxTokens: 700)

        #expect(chunks.count == 3)
        for chunk in chunks {
            #expect(chunk.sections == ["Long"])
            #expect(chunk.text.hasPrefix("## Long\n\n"))
            #expect(MarkdownOutline.estimatedTokens(chunk.text) <= 700)
        }
        // Nothing is lost or duplicated across the cut.
        let rejoined = chunks.map { $0.text.replacingOccurrences(of: "## Long\n\n", with: "") }
        #expect(rejoined.joined(separator: "\n\n") == body)
    }

    @Test func chineseCountsAsRoughlyATokenPerCharacter() {
        #expect(MarkdownOutline.estimatedTokens("线粒体是细胞的能量工厂") == 11)
        #expect(MarkdownOutline.estimatedTokens(String(repeating: "a", count: 100)) == 28)
    }
}
