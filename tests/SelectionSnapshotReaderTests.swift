import Testing
@testable import Quillside

@MainActor @Suite struct SelectionSnapshotReaderTests {
    @Test func toolbarAppearsBeforeSlowFormattingAndNewSelectionDoesNotWaitForOldStyle() {
        var locations: [(Int?) -> Void] = []
        var styles: [(String) -> Void] = []
        var visible: [Int?] = []
        var formatting: [String] = []
        let reader = SelectionSnapshotReader<Int, String>(readGeometry: { locations.append($0) }, readStyle: { _, done in styles.append(done) })
        reader.request(geometry: { visible.append($0) }, style: { formatting.append($0) })
        locations.removeFirst()(10)
        #expect(visible == [10])
        #expect(formatting.isEmpty)
        // The previous rich-text query remains stalled. A second paragraph must still appear.
        reader.request(geometry: { visible.append($0) }, style: { formatting.append($0) })
        locations.removeFirst()(20)
        #expect(visible == [10, 20])
        #expect(styles.count == 1)
        styles.removeFirst()("old style")
        #expect(formatting.isEmpty)
        styles.removeFirst()("current style")
        #expect(formatting == ["current style"])
    }
    @Test func draggingBurstKeepsOnlyNewestSelectionAndCancellationCannotReshowToolbar() {
        var locations: [(Int?) -> Void] = []
        var visible: [Int?] = []
        let reader = SelectionSnapshotReader<Int, String>(readGeometry: { locations.append($0) }, readStyle: { _, done in done("style") })
        for _ in 0..<1000 { reader.request(geometry: { visible.append($0) }, style: { _ in }) }
        #expect(locations.count == 1)
        locations.removeFirst()(1)
        #expect(visible.isEmpty)
        #expect(locations.count == 1)
        locations.removeFirst()(2)
        #expect(visible == [2])
        reader.request(geometry: { visible.append($0) }, style: { _ in })
        reader.cancel(); locations.removeFirst()(3)
        #expect(visible == [2])
    }
}
