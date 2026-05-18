import Foundation
import Testing
@testable import CashRunwayCore

@Test func appModelTimelineLoadingStateIntegration() throws {
    // Test TimelineReloadState integration directly
    // since AppModel just wraps these methods

    var state = TimelineReloadState()
    var isTimelineLoading = false

    // Simulate beginReload
    let reloadID = state.beginReload()
    isTimelineLoading = state.isLoading

    #expect(isTimelineLoading == true)

    // Simulate finishReload with correct ID
    state.finishReload(reloadID: reloadID)
    isTimelineLoading = state.isLoading

    #expect(isTimelineLoading == false)
}

@Test func appModelTimelineLoadingIgnoresStaleReload() throws {
    var state = TimelineReloadState()
    var isTimelineLoading = false

    // Start first reload
    let firstID = state.beginReload()
    isTimelineLoading = state.isLoading
    #expect(isTimelineLoading == true)

    // Start second reload (supersedes first)
    let secondID = state.beginReload()
    #expect(state.isLoading == true)

    // Finish first reload (stale - should be ignored)
    state.finishReload(reloadID: firstID)
    isTimelineLoading = state.isLoading
    #expect(isTimelineLoading == true)

    // Finish second reload (current - should update)
    state.finishReload(reloadID: secondID)
    isTimelineLoading = state.isLoading
    #expect(isTimelineLoading == false)
}
