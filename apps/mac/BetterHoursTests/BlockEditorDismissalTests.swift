import AppKit
import BetterHoursCore
import SwiftUI
import XCTest
@testable import Better_Hours

@MainActor
final class BlockEditorDismissalTests: XCTestCase {
    private func hostedEditor(_ title: String) async throws -> (CalendarModel, NSHostingView<BlockEditorView>, NSWindow) {
        let store = try await SampleData.seeded()
        let calendar = CalendarModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
        let library = LibraryModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
        await calendar.reload()
        await library.reload()
        let id = try XCTUnwrap(calendar.blocks.first { $0.title == title }?.id)
        calendar.openEditor(id: id)
        let draft = try XCTUnwrap(calendar.editing)
        let host = NSHostingView(rootView: BlockEditorView(calendar: calendar, library: library, initial: draft))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 380, height: 520), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderBack(nil)
        try await settle(host)
        return (calendar, host, window)
    }

    private func settle(_ host: NSView) async throws {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
        }
    }

    func testCancelWhileHostedDoesNotTrap() async throws {
        let (calendar, host, window) = try await hostedEditor("Design review")
        defer { window.orderOut(nil) }
        calendar.cancelEditor()
        try await settle(host)
        XCTAssertNil(calendar.editing)
    }

    func testSaveWhileHostedDoesNotTrap() async throws {
        let (calendar, host, window) = try await hostedEditor("Design review")
        defer { window.orderOut(nil) }
        await calendar.saveEditor()
        try await settle(host)
        XCTAssertNil(calendar.editing)
    }

    func testRunningBlockEditorSurvivesDeletion() async throws {
        let (calendar, host, window) = try await hostedEditor("Build editor")
        defer { window.orderOut(nil) }
        let id = try XCTUnwrap(calendar.editing?.id)
        await calendar.deleteBlock(id: id)
        try await settle(host)
        XCTAssertNil(calendar.editing)
    }
}
