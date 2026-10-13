import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: pack-icns.swift <iconset-directory> <output.icns>\n", stderr)
    exit(1)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let chunks: [(type: String, filename: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic14", "icon_256x256@2x.png"),
]

func bigEndianData(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
}

var body = Data()
for chunk in chunks {
    let data = try Data(contentsOf: iconsetURL.appendingPathComponent(chunk.filename))
    body.append(chunk.type.data(using: .ascii)!)
    body.append(bigEndianData(UInt32(data.count + 8)))
    body.append(data)
}

var icns = Data("icns".utf8)
icns.append(bigEndianData(UInt32(body.count + 8)))
icns.append(body)
try icns.write(to: outputURL, options: .atomic)
