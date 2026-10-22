// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VocabFlashcards",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VocabFlashcards", targets: ["VocabFlashcards"]),
        .library(name: "VocabKit", targets: ["VocabKit"])
    ],
    dependencies: [
        // Pure-Swift, read-only .xlsx parser (handles zip container, shared strings, worksheets).
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.2")
    ],
    targets: [
        // Core, UI-agnostic logic: parsing, models, storage, deck building, study session.
        .target(
            name: "VocabKit",
            dependencies: [
                .product(name: "CoreXLSX", package: "CoreXLSX")
            ],
            resources: [
                // Curated SAT example sentences and definition corrections.
                .copy("Resources/curated_content.json")
            ]
        ),
        // The SwiftUI macOS application.
        .executableTarget(
            name: "VocabFlashcards",
            dependencies: ["VocabKit"]
        ),
        // Unit tests for the core logic, exercised against generated .xlsx fixtures.
        .testTarget(
            name: "VocabKitTests",
            dependencies: ["VocabKit"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "VocabFlashcardsTests",
            dependencies: ["VocabFlashcards", "VocabKit"]
        ),
        // Card generation from Markdown with a local model. Written with Swift Testing,
        // which (unlike XCTest) ships with the Command Line Tools.
        .testTarget(
            name: "VocabGenTests",
            dependencies: ["VocabKit"]
        ),
        // The app side of generation: opening decks and Markdown, and the studio.
        .testTarget(
            name: "VocabFlashcardsGenTests",
            dependencies: ["VocabFlashcards", "VocabKit"]
        )
    ]
)
