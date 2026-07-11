import Foundation
import Testing
@testable import CashRunwayCore

@Suite struct ProtectedDataCacheTests {
    @Test func freshCacheReadsNil() {
        let cache = ProtectedDataCache()
        #expect(cache.read() == nil)
    }

    @Test func writeThenReadReturnsValue() {
        let cache = ProtectedDataCache()
        cache.write(true)
        #expect(cache.read() == true)
        cache.write(false)
        #expect(cache.read() == false)
    }

    @Test func invalidateClearsCachedValue() {
        let cache = ProtectedDataCache()
        cache.write(true)
        #expect(cache.read() == true)
        cache.invalidate()
        #expect(cache.read() == nil)
    }

    @Test func concurrentWritesConverge() async {
        let cache = ProtectedDataCache()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask { cache.write(i % 2 == 0) }
            }
        }
        let final = cache.read()
        #expect(final != nil)
    }
}