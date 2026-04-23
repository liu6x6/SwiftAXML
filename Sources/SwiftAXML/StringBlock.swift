
import Foundation

enum StringBlockError: Error {
    case badStringLength
}

class StringBlock {
    private var stringOffsets: [Int] = []
    private var strings: Data
    private var isUTF8: Bool
    private var cache: [Int: String] = [:]

    init(data: Data) throws {
        let header = data.subdata(in: 0..<28)
        let stringCount = Int(header.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self).littleEndian })
        let styleCount = Int(header.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self).littleEndian })
        let flags = Int(header.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt32.self).littleEndian })
        let stringsOffset = Int(header.withUnsafeBytes { $0.load(fromByteOffset: 20, as: UInt32.self).littleEndian })
        let stylesOffset = Int(header.withUnsafeBytes { $0.load(fromByteOffset: 24, as: UInt32.self).littleEndian })

        self.isUTF8 = (flags & 256) != 0

        var offset = 28
        for _ in 0..<stringCount {
            let stringOffset = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian })
            self.stringOffsets.append(stringOffset)
            offset += 4
        }

        let stringsStart = stringsOffset
        let stringsEnd = (stylesOffset == 0) ? data.count : stylesOffset
        self.strings = data.subdata(in: stringsStart..<stringsEnd)
    }

    func getString(at index: Int) -> String? {
        if let cached = cache[index] {
            return cached
        }

        guard index >= 0 && index < stringOffsets.count else {
            return nil
        }

        let offset = stringOffsets[index]
        let result: String?
        if isUTF8 {
            result = decodeUTF8String(at: offset)
        } else {
            result = decodeUTF16String(at: offset)
        }

        if let result = result {
            cache[index] = result
        }
        return result
    }

    private func decodeUTF8String(at offset: Int) -> String? {
        let (len, lenSize) = decodeLength(at: offset, isUTF8: true)
        let dataOffset = offset + lenSize
        guard dataOffset + len < strings.count else { return nil }
        let data = strings.subdata(in: dataOffset..<(dataOffset + len))
        return String(data: data, encoding: .utf8)
    }

    private func decodeUTF16String(at offset: Int) -> String? {
        let (len, lenSize) = decodeLength(at: offset, isUTF8: false)
        let dataOffset = offset + lenSize
        let byteLength = len * 2
        guard dataOffset + byteLength < strings.count else { return nil }
        let data = strings.subdata(in: dataOffset..<(dataOffset + byteLength))
        return String(data: data, encoding: .utf16LittleEndian)
    }

    private func decodeLength(at offset: Int, isUTF8: Bool) -> (Int, Int) {
        if isUTF8 {
            let length = Int(strings[offset])
            if (length & 0x80) != 0 {
                let nextByte = Int(strings[offset + 1])
                return (((length & 0x7F) << 8) | nextByte, 2)
            }
            return (length, 1)
        } else {
            let length = Int(strings.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self) })
            if (length & 0x8000) != 0 {
                let nextBytes = Int(strings.withUnsafeBytes { $0.load(fromByteOffset: offset + 2, as: UInt16.self) })
                return (((length & 0x7FFF) << 16) | nextBytes, 4)
            }
            return (length, 2)
        }
    }
}
