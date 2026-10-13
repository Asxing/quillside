import Foundation

@main
struct ExportDefaultConfiguration {
    static func main() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(AIConfiguration())
        FileHandle.standardOutput.write(data)
    }
}
