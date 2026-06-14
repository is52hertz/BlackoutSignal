//
//  BlackoutSignalTests.swift
//  BlackoutSignalTests
//

import Foundation
import Testing
@testable import BlackoutSignal

struct BrightnessStoreTests {

    private func makeTempStore() -> BrightnessStore {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BlackoutSignalTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("session.json", isDirectory: false)
        return BrightnessStore(fileURL: url)
    }

    @Test func emptyStoreHasNoSession() {
        let store = makeTempStore()
        #expect(store.hasPendingSession == false)
        #expect(store.load() == nil)
    }

    @Test func savesAndLoadsSession() throws {
        let store = makeTempStore()
        defer { store.clear() }

        let session = BlackoutSession(brightness: ["1:2:3": 75, "uuid-abc": 40])
        store.save(session)

        #expect(store.hasPendingSession == true)
        let loaded = try #require(store.load())
        #expect(loaded.brightness == session.brightness)
    }

    @Test func clearRemovesSession() {
        let store = makeTempStore()
        store.save(BlackoutSession(brightness: ["a": 10]))
        #expect(store.hasPendingSession == true)

        store.clear()
        #expect(store.hasPendingSession == false)
        #expect(store.load() == nil)
    }
}
