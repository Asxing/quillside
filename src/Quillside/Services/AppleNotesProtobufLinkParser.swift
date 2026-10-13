import Foundation
import zlib

enum AppleNotesProtobufLinkParser {
    private static let maximumDecompressedSize = 16 * 1_024 * 1_024
    // Verified against Apple Notes on macOS 14. Apple does not publish this schema.
    private static let documentField: UInt64 = 2
    private static let noteField: UInt64 = 3
    private static let attributeRunField: UInt64 = 5
    private static let linkField: UInt64 = 9

    static func identifiers(inCompressedNoteData data: Data) -> [String] {
        guard
            let decompressed = gunzip(data),
            let document = lengthDelimitedFields(
                in: decompressed,
                number: documentField
            ).first,
            let note = lengthDelimitedFields(
                in: document,
                number: noteField
            ).first
        else {
            return []
        }

        var identifiers = Set<String>()
        for attributeRun in lengthDelimitedFields(
            in: note,
            number: attributeRunField
        ) {
            for linkData in lengthDelimitedFields(
                in: attributeRun,
                number: linkField
            ) {
                guard let link = String(data: linkData, encoding: .utf8) else {
                    continue
                }
                identifiers.formUnion(NativeNoteLinkParser.identifiers(in: link))
            }
        }
        return identifiers.sorted()
    }

    static func gunzip(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }

        var stream = z_stream()
        guard inflateInit2_(
            &stream,
            MAX_WBITS + 32,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }

        return data.withUnsafeBytes { inputBuffer -> Data? in
            guard let input = inputBuffer.bindMemory(to: Bytef.self).baseAddress else {
                return nil
            }

            stream.next_in = UnsafeMutablePointer(mutating: input)
            stream.avail_in = uInt(data.count)

            let chunkSize = 32_768
            var chunk = [UInt8](repeating: 0, count: chunkSize)
            var output = Data()
            var status = Z_OK

            repeat {
                status = chunk.withUnsafeMutableBytes { outputBuffer in
                    stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }

                guard status == Z_OK || status == Z_STREAM_END else {
                    return nil
                }

                let produced = chunkSize - Int(stream.avail_out)
                guard
                    produced <= maximumDecompressedSize,
                    output.count <= maximumDecompressedSize - produced
                else {
                    return nil
                }
                output.append(contentsOf: chunk.prefix(produced))
            } while status != Z_STREAM_END

            return output
        }
    }

    private static func lengthDelimitedFields(
        in data: Data,
        number targetNumber: UInt64
    ) -> [Data] {
        var offset = 0
        var matches: [Data] = []

        while offset < data.count {
            guard let tag = readVarint(data, offset: &offset) else {
                return matches
            }

            let fieldNumber = tag >> 3
            let wireType = tag & 0x07

            switch wireType {
            case 0:
                guard readVarint(data, offset: &offset) != nil else {
                    return matches
                }
            case 1:
                guard advance(&offset, by: 8, within: data.count) else {
                    return matches
                }
            case 2:
                guard
                    let length = readVarint(data, offset: &offset),
                    length <= UInt64(Int.max),
                    advance(&offset, by: Int(length), within: data.count)
                else {
                    return matches
                }

                if fieldNumber == targetNumber {
                    let start = offset - Int(length)
                    matches.append(data.subdata(in: start..<offset))
                }
            case 5:
                guard advance(&offset, by: 4, within: data.count) else {
                    return matches
                }
            default:
                return matches
            }
        }

        return matches
    }

    private static func readVarint(_ data: Data, offset: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0

        while offset < data.count, shift < 64 {
            let byte = data[offset]
            offset += 1
            guard shift < 63 || byte <= 1 else {
                return nil
            }
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return value
            }
            shift += 7
        }
        return nil
    }

    private static func advance(
        _ offset: inout Int,
        by count: Int,
        within dataCount: Int
    ) -> Bool {
        guard count >= 0, offset <= dataCount - count else {
            return false
        }
        offset += count
        return true
    }
}
