import AppKit
import SwiftUI
import XCTest
@testable import Better_Hours

@MainActor
final class SnapshotTests: XCTestCase {
    private static let size = CGSize(width: 1120, height: 720)

    private var outputDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".snapshots", isDirectory: true)
    }

    func testRenderSnapshots() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for mode in [CalendarMode.week, .day] {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let store = try await SampleData.seeded()
                let calendar = CalendarModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
                let library = LibraryModel(store: store)
                calendar.setMode(mode)
                await calendar.reload()
                await library.reload()
                let view = MainWindowView(calendar: calendar, library: library, scrollHour: 8)
                let file = outputDirectory.appendingPathComponent("\(mode == .week ? "week" : "day")-\(name).png")
                try await render(view, appearance: appearance, to: file)
                let size = try XCTUnwrap(try? Data(contentsOf: file)).count
                XCTAssertGreaterThan(size, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
    }

    func testRenderInteractionStates() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let states: [(String, @MainActor (CalendarModel) throws -> Void)] = [
            ("selected", { model in
                model.select(try XCTUnwrap(model.blocks.first { $0.title == "API schema" }?.id))
            }),
            ("creating", { model in
                model.beginCreate(at: SampleData.date(9, 10, 2))
                model.updateDrag(to: SampleData.date(9, 11, 1))
            }),
            ("moving", { model in
                let id = try XCTUnwrap(model.blocks.first { $0.title == "Design review" }?.id)
                model.beginMove(id: id, pointerTime: SampleData.date(5, 9, 20))
                model.updateDrag(to: SampleData.date(9, 14, 22))
            }),
        ]
        for (state, configure) in states {
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let store = try await SampleData.seeded()
                let calendar = CalendarModel(store: store, clock: { SampleData.now }, calendar: SampleData.calendar)
                let library = LibraryModel(store: store)
                await calendar.reload()
                await library.reload()
                try configure(calendar)
                let view = MainWindowView(calendar: calendar, library: library, scrollHour: 8)
                let file = outputDirectory.appendingPathComponent("week-\(state)-\(name).png")
                try await render(view, appearance: appearance, to: file)
                let size = try XCTUnwrap(try? Data(contentsOf: file)).count
                XCTAssertGreaterThan(size, 10_000, "\(file.lastPathComponent) looks empty")
            }
        }
    }

    private func render(_ view: some View, appearance: NSAppearance.Name, to url: URL) async throws {
        let host = NSHostingView(rootView: view.frame(width: Self.size.width, height: Self.size.height))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
        let bounds = host.bounds
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: bounds))
        host.cacheDisplay(in: bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}
