import XCTest
@testable import SpeechEngine

final class SpeechModelCatalogTests: XCTestCase {
    func testCuratedCatalogHasUniqueStableIdentifiers() {
        let choices = SpeechModelChoice.allCases

        XCTAssertEqual(Set(choices.map(\.rawValue)).count, choices.count)
        XCTAssertEqual(SpeechModelChoice.multilingual.rawValue, "parakeet-tdt-0.6b-v3")
        XCTAssertEqual(
            SpeechModelChoice.englishPrecision.rawValue,
            "parakeet-unified-en-0.6b"
        )
    }

    func testFactoryReturnsMatchingProviderMetadata() {
        for choice in SpeechModelChoice.allCases {
            let provider = SpeechModelFactory.make(choice)
            XCTAssertEqual(provider.modelID, choice.rawValue)
        }
    }

    func testCatalogCommunicatesLanguageTradeoff() {
        XCTAssertEqual(
            SpeechModelChoice.multilingual.languageSummary,
            "25 European languages"
        )
        XCTAssertEqual(SpeechModelChoice.englishPrecision.languageSummary, "English")
        XCTAssertFalse(SpeechModelChoice.englishPrecision.detail.isEmpty)
    }

    func testRuntimePolicyForcesFluidAudioOffline() {
        SpeechModelRuntimePolicy.enforceOfflineOnly()

        XCTAssertTrue(SpeechModelRuntimePolicy.fluidAudioOfflineMode)
    }
}
