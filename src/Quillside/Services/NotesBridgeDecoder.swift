// Adapted from NotesBridge 91bccb0 (MIT). See THIRD_PARTY_NOTICES.md.
import Foundation
import zlib

struct AppleNotesDecodedNote: Sendable {
    var noteText: String
    var attributeRuns: [AppleNotesDecodedAttributeRun]
    var recognized = false
}

struct AppleNotesDecodedAttributeRun: Sendable {
    var length: Int
    var paragraphStyle: AppleNotesDecodedParagraphStyle?
    var fontWeight: Int?
    var underlined: Bool
    var strikethrough: Bool
    var superscript: Int?
    var link: String?
    var attachmentInfo: AppleNotesDecodedAttachmentInfo?
}

struct AppleNotesDecodedParagraphStyle: Sendable {
    var styleType: Int?
    var indentAmount: Int
    var blockquote: Bool
    var checklist: AppleNotesDecodedChecklist?
}

struct AppleNotesDecodedChecklist: Sendable {
    var done: Bool
}

struct AppleNotesDecodedAttachmentInfo: Sendable {
    var attachmentIdentifier: String
    var typeUti: String
}

private struct AppleNotesDecodedNoteMatch {
    var note: AppleNotesDecodedNote
    var fieldPath: [Int]
}

enum AppleNotesNoteDecodingError: LocalizedError {
    case invalidGzipData
    case invalidProtobuf

    var errorDescription: String? {
        switch self {
        case .invalidGzipData:
            "Apple Notes note data could not be decompressed."
        case .invalidProtobuf:
            "Apple Notes note data could not be decoded."
        }
    }
}

struct AppleNotesNoteProtoDecoder {
    func decodeDocument(from compressedData: Data) throws -> AppleNotesDecodedNote {
        guard let data = AppleNotesProtobufLinkParser.gunzip(compressedData) else { throw AppleNotesNoteDecodingError.invalidGzipData }
        let directDocument = try decodeDocumentMessage(from: data)
        if !directDocument.isEmpty {
            return directDocument
        }

        let wrappedDocument = try decodeNoteStoreProtoMessage(from: data)
        if !wrappedDocument.isEmpty {
            return wrappedDocument
        }

        if let recursiveDocument = try searchForDocument(in: data, remainingDepth: 6)?.note,
           !recursiveDocument.isEmpty
        {
            return recursiveDocument
        }

        throw AppleNotesNoteDecodingError.invalidProtobuf
    }

    private func decodeDocumentMessage(from data: Data) throws -> AppleNotesDecodedNote {
        var reader = ProtobufReader(data: data)
        var decodedNote = AppleNotesDecodedNote(noteText: "", attributeRuns: [])

        while let field = try reader.nextField() {
            switch field.number {
            case 3:
                guard field.wireType == 2 else { throw AppleNotesNoteDecodingError.invalidProtobuf }
                decodedNote = try decodeNoteMessage(from: try reader.readLengthDelimited())
                decodedNote.recognized = true
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return decodedNote
    }

    private func decodeNoteStoreProtoMessage(from data: Data) throws -> AppleNotesDecodedNote {
        var reader = ProtobufReader(data: data)
        var decodedNote = AppleNotesDecodedNote(noteText: "", attributeRuns: [])

        while let field = try reader.nextField() {
            switch field.number {
            case 2:
                guard field.wireType == 2 else { throw AppleNotesNoteDecodingError.invalidProtobuf }
                decodedNote = try decodeDocumentMessage(from: try reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return decodedNote
    }

    private func searchForDocument(
        in data: Data,
        remainingDepth: Int,
        fieldPath: [Int] = []
    ) throws -> AppleNotesDecodedNoteMatch? {
        guard remainingDepth > 0, !data.isEmpty else {
            return nil
        }

        let directDocument = try decodeDocumentMessage(from: data)
        if !directDocument.isEmpty {
            return AppleNotesDecodedNoteMatch(note: directDocument, fieldPath: fieldPath)
        }

        var reader = ProtobufReader(data: data)
        while let field = try reader.nextField() {
            guard field.wireType == 2 else {
                try reader.skipField(wireType: field.wireType)
                continue
            }

            let nestedData = try reader.readLengthDelimited()
            let nestedPath = fieldPath + [field.number]
            if let nestedMatch = try searchForDocument(
                in: nestedData,
                remainingDepth: remainingDepth - 1,
                fieldPath: nestedPath
            ) {
                return nestedMatch
            }
        }

        let directNote = try decodeNoteMessage(from: data)
        if !directNote.isEmpty {
            return AppleNotesDecodedNoteMatch(note: directNote, fieldPath: fieldPath)
        }

        return nil
    }

    func decodeNoteMessage(from data: Data) throws -> AppleNotesDecodedNote {
        var reader = ProtobufReader(data: data)
        var noteText = ""
        var attributeRuns: [AppleNotesDecodedAttributeRun] = []
        var recognized = false

        while let field = try reader.nextField() {
            switch field.number {
            case 2:
                guard field.wireType == 2 else { throw AppleNotesNoteDecodingError.invalidProtobuf }
                noteText = try reader.readString()
                recognized = true
            case 5:
                guard field.wireType == 2 else { throw AppleNotesNoteDecodingError.invalidProtobuf }
                attributeRuns.append(try decodeAttributeRunMessage(from: try reader.readLengthDelimited()))
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesDecodedNote(noteText: noteText, attributeRuns: attributeRuns, recognized: recognized)
    }

    private func decodeAttributeRunMessage(from data: Data) throws -> AppleNotesDecodedAttributeRun {
        var reader = ProtobufReader(data: data)
        var run = AppleNotesDecodedAttributeRun(
            length: 0,
            paragraphStyle: nil,
            fontWeight: nil,
            underlined: false,
            strikethrough: false,
            superscript: nil,
            link: nil,
            attachmentInfo: nil
        )

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                run.length = Int(try reader.readInt32())
            case 2:
                run.paragraphStyle = try decodeParagraphStyleMessage(from: try reader.readLengthDelimited())
            case 5:
                run.fontWeight = Int(try reader.readInt32())
            case 6:
                run.underlined = try reader.readInt32() != 0
            case 7:
                run.strikethrough = try reader.readInt32() != 0
            case 8:
                run.superscript = Int(try reader.readInt32())
            case 9:
                run.link = try reader.readString()
            case 12:
                run.attachmentInfo = try decodeAttachmentInfoMessage(from: try reader.readLengthDelimited())
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return run
    }

    private func decodeParagraphStyleMessage(from data: Data) throws -> AppleNotesDecodedParagraphStyle {
        var reader = ProtobufReader(data: data)
        var paragraphStyle = AppleNotesDecodedParagraphStyle(
            styleType: nil,
            indentAmount: 0,
            blockquote: false,
            checklist: nil
        )

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                paragraphStyle.styleType = Int(try reader.readInt32())
            case 4:
                paragraphStyle.indentAmount = Int(try reader.readInt32())
            case 5:
                paragraphStyle.checklist = try decodeChecklistMessage(from: try reader.readLengthDelimited())
            case 8:
                paragraphStyle.blockquote = try reader.readInt32() != 0
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return paragraphStyle
    }

    private func decodeChecklistMessage(from data: Data) throws -> AppleNotesDecodedChecklist {
        var reader = ProtobufReader(data: data)
        var done = false

        while let field = try reader.nextField() {
            switch field.number {
            case 2:
                done = try reader.readInt32() != 0
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesDecodedChecklist(done: done)
    }

    private func decodeAttachmentInfoMessage(from data: Data) throws -> AppleNotesDecodedAttachmentInfo {
        var reader = ProtobufReader(data: data)
        var attachmentIdentifier = ""
        var typeUti = ""

        while let field = try reader.nextField() {
            switch field.number {
            case 1:
                attachmentIdentifier = try reader.readString()
            case 2:
                typeUti = try reader.readString()
            default:
                try reader.skipField(wireType: field.wireType)
            }
        }

        return AppleNotesDecodedAttachmentInfo(
            attachmentIdentifier: attachmentIdentifier,
            typeUti: typeUti
        )
    }
}

private extension AppleNotesDecodedNote {
    var isEmpty: Bool {
        !recognized && noteText.isEmpty && attributeRuns.isEmpty
    }
}

struct ProtobufField {
    var number: Int
    var wireType: Int
}

struct ProtobufReader {
    private let data: Data
    private var index = 0

    init(data: Data) {
        self.data = data
    }

    mutating func nextField() throws -> ProtobufField? {
        guard index < data.count else { return nil }
        let key = try readVarint()
        return ProtobufField(number: Int(key >> 3), wireType: Int(key & 0x07))
    }

    mutating func readLengthDelimited() throws -> Data {
        let rawLength = try readVarint()
        guard rawLength <= UInt64(data.count - index) else { throw AppleNotesNoteDecodingError.invalidProtobuf }
        let length = Int(rawLength)
        guard length >= 0, length <= data.count - index else {
            throw AppleNotesNoteDecodingError.invalidProtobuf
        }

        defer { index += length }
        return data.subdata(in: index ..< index + length)
    }

    mutating func readString() throws -> String {
        let bytes = try readLengthDelimited()
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw AppleNotesNoteDecodingError.invalidProtobuf
        }

        return string
    }

    mutating func readInt32() throws -> Int32 {
        let value = try readVarint()
        return Int32(bitPattern: UInt32(truncatingIfNeeded: value))
    }

    mutating func skipField(wireType: Int) throws {
        switch wireType {
        case 0:
            _ = try readVarint()
        case 1:
            guard index + 8 <= data.count else { throw AppleNotesNoteDecodingError.invalidProtobuf }
            index += 8
        case 2:
            _ = try readLengthDelimited()
        case 5:
            guard index + 4 <= data.count else { throw AppleNotesNoteDecodingError.invalidProtobuf }
            index += 4
        default:
            throw AppleNotesNoteDecodingError.invalidProtobuf
        }
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while index < data.count {
            let byte = data[index]
            index += 1
            guard shift < 63 || byte <= 1 else { throw AppleNotesNoteDecodingError.invalidProtobuf }
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }

            shift += 7
            if shift >= 64 {
                break
            }
        }

        throw AppleNotesNoteDecodingError.invalidProtobuf
    }
}
