import AppKit
import Foundation

// Production vector master shared by SVG, PNG, ICNS and the menu bar mask.
struct Layer: Decodable {
    let id: String
    let fill: String?
    let stroke: String?
    let strokeWidth: Double?
    let cutout: Bool?
    let commands: [[CommandValue]]
}
enum CommandValue: Decodable {
    case name(String), number(Double)
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let number = try? value.decode(Double.self) { self = .number(number) }
        else { self = .name(try value.decode(String.self)) }
    }
    var text: String { switch self { case .name(let name): return name; case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n) } }
    var number: CGFloat { switch self { case .number(let n): return CGFloat(n); case .name: preconditionFailure("Expected path coordinate") } }
}
struct Master: Decodable { let name: String; let viewBox: Double; let layers: [Layer] }

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-icon.swift <AppIcon-1024.png>\n", stderr); exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let brand = output.deletingLastPathComponent().appendingPathComponent("Brand", isDirectory: true)
let master = try JSONDecoder().decode(Master.self, from: Data(contentsOf: brand.appendingPathComponent("mark.json")))

// One full note tile is shared by the app, settings, website and wordmarks.
let appPaper = CGRect(x: 82, y: 82, width: 860, height: 860)
let appCorner: CGFloat = 190
let appHeaderHeight: CGFloat = 230
let appForeground = master.layers
let appForegroundScale: CGFloat = 0.94
let appForegroundInset = CGFloat(master.viewBox) * (1 - appForegroundScale) / 2
// Keep the same sheet/quill composition at 18pt, with room for the menu hop.
let templateScale: CGFloat = 0.82
let templateInset = CGFloat(master.viewBox) * (1 - templateScale) / 2
let templateOutlineWidth: CGFloat = 60
let templateHeaderWidth: CGFloat = 44

func color(_ hex: String) -> CGColor {
    let value = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(red: CGFloat((value >> 16) & 255) / 255,
                   green: CGFloat((value >> 8) & 255) / 255,
                   blue: CGFloat(value & 255) / 255, alpha: 1)
}
// Match the PNG export's color-managed sRGB values in browser SVG rendering.
func svgColor(_ hex: String) -> String {
    let rgb = NSColor(cgColor: color(hex))!.usingColorSpace(.sRGB)!
    return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                  Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
}
func path(_ layer: Layer) -> CGPath {
    let result = CGMutablePath()
    for command in layer.commands {
        switch command[0].text {
        case "M": result.move(to: CGPoint(x: command[1].number, y: command[2].number))
        case "L": result.addLine(to: CGPoint(x: command[1].number, y: command[2].number))
        case "C": result.addCurve(to: CGPoint(x: command[5].number, y: command[6].number),
                                   control1: CGPoint(x: command[1].number, y: command[2].number),
                                   control2: CGPoint(x: command[3].number, y: command[4].number))
        case "Z": result.closeSubpath()
        default: preconditionFailure("Unsupported path command")
        }
    }
    return result
}
func draw(_ context: CGContext, monochrome: Bool) {
    context.setLineCap(.round); context.setLineJoin(.round)
    for layer in appForeground {
        context.saveGState()
        context.addPath(path(layer))
        if monochrome {
            if layer.cutout == true { context.setBlendMode(.clear); context.fillPath() }
            else if layer.id.hasPrefix("rule") {
                context.setStrokeColor(CGColor(gray: 0, alpha: 1)); context.setLineWidth(34); context.strokePath()
            } else { context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fillPath() }
        } else {
            if let fill = layer.fill { context.setFillColor(color(fill)) }
            if let stroke = layer.stroke { context.setStrokeColor(color(stroke)); context.setLineWidth(layer.strokeWidth ?? 1) }
            context.drawPath(using: layer.fill != nil ? (layer.stroke != nil ? .fillStroke : .fill) : .stroke)
        }
        context.restoreGState()
    }
}
func png(to url: URL, pixels: Int, monochrome: Bool = false, logicalSize: CGFloat? = nil) throws {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.scaleBy(x: CGFloat(pixels) / CGFloat(master.viewBox), y: CGFloat(pixels) / CGFloat(master.viewBox))
    context.translateBy(x: 0, y: CGFloat(master.viewBox)); context.scaleBy(x: 1, y: -1)
    if monochrome {
        context.translateBy(x: templateInset, y: templateInset)
        context.scaleBy(x: templateScale, y: templateScale)
    }
    let paper = CGPath(roundedRect: appPaper, cornerWidth: appCorner, cornerHeight: appCorner, transform: nil)
    if monochrome {
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(templateOutlineWidth)
        context.addPath(paper); context.strokePath()
        context.setLineWidth(templateHeaderWidth)
        context.move(to: CGPoint(x: appPaper.minX, y: appPaper.minY + appHeaderHeight))
        context.addLine(to: CGPoint(x: appPaper.maxX, y: appPaper.minY + appHeaderHeight))
        context.strokePath()
    } else {
        context.saveGState()
        context.addPath(paper); context.clip()
        context.setFillColor(color("#FFFDF7")); context.fill(appPaper)
        context.setFillColor(color("#D6AA45"))
        context.fill(CGRect(x: appPaper.minX, y: appPaper.minY, width: appPaper.width, height: appHeaderHeight))
        context.restoreGState()
    }
    context.translateBy(x: appForegroundInset, y: appForegroundInset)
    context.scaleBy(x: appForegroundScale, y: appForegroundScale)
    draw(context, monochrome: monochrome)
    let image = context.makeImage()!
    let bitmap = NSBitmapImageRep(cgImage: image)
    if let logicalSize { bitmap.size = NSSize(width: logicalSize, height: logicalSize) }
    try bitmap.representation(using: .png, properties: [:])!.write(to: url, options: .atomic)
}

try png(to: output, pixels: 1024)
try png(to: brand.appendingPathComponent("Quillside-AppIcon.png"), pixels: 1024)
try png(to: brand.appendingPathComponent("Quillside-Mark.png"), pixels: 1024)
try png(to: brand.appendingPathComponent("Quillside-Monochrome.png"), pixels: 1024, monochrome: true)
try png(to: brand.appendingPathComponent("MenuBarTemplate.png"), pixels: 72, monochrome: true, logicalSize: 18)

func svgPaths(_ layers: [Layer]) -> String { layers.map { layer -> String in
    let d = layer.commands.map { $0.map(\.text).joined(separator: " ") }.joined(separator: " ")
    let stroke = layer.stroke.map { " stroke=\"\(svgColor($0))\" stroke-width=\"\(layer.strokeWidth ?? 1)\"" } ?? ""
    return "  <path d=\"\(d)\" fill=\"\(layer.fill.map(svgColor) ?? "none")\"\(stroke)/>"
}.joined(separator: "\n") }
let symbol = """
  <defs><clipPath id="paper"><rect x="\(appPaper.minX)" y="\(appPaper.minY)" width="\(appPaper.width)" height="\(appPaper.height)" rx="\(appCorner)"/></clipPath></defs>
  <g clip-path="url(#paper)">
    <rect x="\(appPaper.minX)" y="\(appPaper.minY)" width="\(appPaper.width)" height="\(appPaper.height)" fill="\(svgColor("#FFFDF7"))"/>
    <rect x="\(appPaper.minX)" y="\(appPaper.minY)" width="\(appPaper.width)" height="\(appHeaderHeight)" fill="\(svgColor("#D6AA45"))"/>
  </g>
  <g transform="translate(\(appForegroundInset),\(appForegroundInset)) scale(\(appForegroundScale))">
\(svgPaths(appForeground))
  </g>
"""
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="Quillside feather and full note mark" stroke-linecap="round" stroke-linejoin="round">
\(symbol)
</svg>

"""
try svg.write(to: brand.appendingPathComponent("Quillside-AppIcon.svg"), atomically: true, encoding: .utf8)
try svg.write(to: brand.appendingPathComponent("Quillside-Mark.svg"), atomically: true, encoding: .utf8)
for (filename, width, suffix) in [
    ("Quillside-Wordmark.svg", 1240, ""),
    ("Quillside-Notes-Lockup.svg", 1730, "<tspan fill=\"#74786E\" font-weight=\"400\" dx=\"28\">Notes</tspan>")
] {
    let lockup = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(width) 320" role="img" aria-label="Quillside\(suffix.isEmpty ? "" : " Notes")" stroke-linecap="round" stroke-linejoin="round">
    <g transform="translate(0,0) scale(0.31)">\(symbol)</g>
    <text x="328" y="214" fill="\(svgColor("#2B3028"))" font-family="-apple-system,BlinkMacSystemFont,Arial,sans-serif" font-size="172" font-weight="600" letter-spacing="-5">Quillside\(suffix)</text>
    </svg>

    """
    try lockup.write(to: brand.appendingPathComponent(filename), atomically: true, encoding: .utf8)
}
print("Generated Quillside vector mark, app icon, and monochrome assets.")
