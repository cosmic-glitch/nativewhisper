import Foundation
import XCTest
@testable import NativeWhisper

final class TranscriptionRouteStoreTests: XCTestCase {
    func testDefaultRouteIsHosted() {
        let suiteName = "TranscriptionRouteStoreTests.default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = TranscriptionRouteStore(
            defaults: defaults,
            defaultsKey: "WhisperAnywhere.TranscriptionRoute.Test"
        )

        XCTAssertEqual(store.currentRoute(), .hosted)
    }

    func testSavesAndLoadsDirectRoute() {
        let suiteName = "TranscriptionRouteStoreTests.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = TranscriptionRouteStore(
            defaults: defaults,
            defaultsKey: "WhisperAnywhere.TranscriptionRoute.Test"
        )
        store.saveRoute(.direct)

        XCTAssertEqual(store.currentRoute(), .direct)
    }
}
