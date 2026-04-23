
import Foundation

enum ChunkType: UInt16 {
    case RES_NULL_TYPE = 0x0000
    case RES_STRING_POOL_TYPE = 0x0001
    case RES_TABLE_TYPE = 0x0002
    case RES_XML_TYPE = 0x0003

    // Chunk types in RES_XML_TYPE
    case RES_XML_START_NAMESPACE_TYPE = 0x0100
    case RES_XML_END_NAMESPACE_TYPE = 0x0101
    case RES_XML_START_ELEMENT_TYPE = 0x0102
    case RES_XML_END_ELEMENT_TYPE = 0x0103
    case RES_XML_CDATA_TYPE = 0x0104
    case RES_XML_LAST_CHUNK_TYPE = 0x017f
    // This contains a uint32_t array mapping strings in the string
    // pool back to resource identifiers.  It is optional.
    case RES_XML_RESOURCE_MAP_TYPE = 0x0180

    // Chunk types in RES_TABLE_TYPE
    case RES_TABLE_PACKAGE_TYPE = 0x0200
    case RES_TABLE_TYPE_TYPE = 0x0201
    case RES_TABLE_TYPE_SPEC_TYPE = 0x0202
    case RES_TABLE_LIBRARY_TYPE = 0x0203
}

enum Event {
    case startDocument
    case endDocument
    case startTag
    case endTag
    case text
}

struct Attribute {
    let namespace: String?
    let name: String
    let value: String
}

class AXMLParser {
    private var data: Data
    private var stringBlock: StringBlock
    private var resourceMap: [UInt32] = []
    private var namespaces: [(prefix: String, uri: String)] = []
    private var cursor = 0

    var event: Event = .startDocument
    var name: String?
    var namespace: String?
    var namespaceUriPrefixMap: [String: String] = [:]
    var attributes: [Attribute] = []
    var text: String?

    init(data: Data) throws {
        self.data = data
        
        var headerCursor = 0
        let axmlHeader = try AXMLParser.parseHeader(cursor: &headerCursor, data: data)
        self.cursor = Int(axmlHeader.headerSize)

        // First chunk should be the string pool
        var stringPoolCursor = self.cursor
        let stringPoolHeader = try AXMLParser.parseHeader(cursor: &stringPoolCursor, data: data, expected: .RES_STRING_POOL_TYPE)
        let stringPoolData = data.subdata(in: self.cursor..<(self.cursor + Int(stringPoolHeader.size)))
        self.stringBlock = try StringBlock(data: stringPoolData)
        self.cursor += Int(stringPoolHeader.size)

        // The next chunk can be a resource map
        if self.cursor < data.count {
            var resourceMapCursor = self.cursor
            if let resourceMapHeader = try? AXMLParser.parseHeader(cursor: &resourceMapCursor, data: data, expected: .RES_XML_RESOURCE_MAP_TYPE) {
                let mapSize = Int(resourceMapHeader.size) - Int(resourceMapHeader.headerSize)
                for i in 0..<(mapSize / 4) {
                    let resId = data.withUnsafeBytes { $0.load(fromByteOffset: self.cursor + Int(resourceMapHeader.headerSize) + i * 4, as: UInt32.self).littleEndian }
                    self.resourceMap.append(resId)
                }
                self.cursor += Int(resourceMapHeader.size)
            }
        }
    }

    func next() throws -> Event {
        if event == .endDocument || cursor >= data.count {
            event = .endDocument
            return .endDocument
        }

        var headerCursor = cursor
        let header = try AXMLParser.parseHeader(cursor: &headerCursor, data: data)
        let chunkContentStart = cursor + Int(header.headerSize)

        switch header.type {
        case .RES_XML_START_NAMESPACE_TYPE:
            let prefixIndex = Int(data.withUnsafeBytes { $0.load(fromByteOffset: chunkContentStart, as: UInt32.self).littleEndian })
            let uriIndex = Int(data.withUnsafeBytes { $0.load(fromByteOffset: chunkContentStart + 4, as: UInt32.self).littleEndian })
            let prefix = stringBlock.getString(at: prefixIndex) ?? ""
            let uri = stringBlock.getString(at: uriIndex) ?? ""
            namespaces.append((prefix, uri))
            namespaceUriPrefixMap[uri] = prefix
            cursor += Int(header.size)
            return try next()

        case .RES_XML_END_NAMESPACE_TYPE:
            cursor += Int(header.size)
            namespaces.removeLast()
            return try next()

        case .RES_XML_START_ELEMENT_TYPE:
            event = .startTag
            let nsIndex = Int(data.withUnsafeBytes { $0.load(fromByteOffset: chunkContentStart, as: UInt32.self).littleEndian })
            let nameIndex = Int(data.withUnsafeBytes { $0.load(fromByteOffset: chunkContentStart + 4, as: UInt32.self).littleEndian })
            let attributeStart = Int(data.withUnsafeBytes { $0.load(fromByteOffset: chunkContentStart + 8, as: UInt16.self).littleEndian })
            let attributeSize = Int(data.withUnsafeBytes { $0.load(fromByteOffset: chunkContentStart + 10, as: UInt16.self).littleEndian })
            let attributeCountRaw = data.withUnsafeBytes { $0.load(fromByteOffset: chunkContentStart + 12, as: UInt32.self).littleEndian }
            let attributeCount = Int(attributeCountRaw & 0xFFFF)

            self.namespace = (nsIndex == 0xFFFFFFFF) ? nil : stringBlock.getString(at: nsIndex)
            self.name = (nameIndex == 0xFFFFFFFF) ? nil : stringBlock.getString(at: nameIndex)

            var attributesStart = chunkContentStart + attributeStart
            self.attributes = []
            for _ in 0..<attributeCount {
                let attrNsIndex = Int(data.withUnsafeBytes { $0.load(fromByteOffset: attributesStart, as: UInt32.self).littleEndian })
                let attrNameIndex = Int(data.withUnsafeBytes { $0.load(fromByteOffset: attributesStart + 4, as: UInt32.self).littleEndian })
                let attrValueStringIndex = Int(data.withUnsafeBytes { $0.load(fromByteOffset: attributesStart + 8, as: UInt32.self).littleEndian })
                let attrValueType = Int(data.withUnsafeBytes { $0.load(fromByteOffset: attributesStart + 12, as: UInt32.self).littleEndian } >> 24)
                let attrValueData = Int(data.withUnsafeBytes { $0.load(fromByteOffset: attributesStart + 16, as: UInt32.self).littleEndian })

                let attrNs = (attrNsIndex == 0xFFFFFFFF) ? nil : stringBlock.getString(at: attrNsIndex)
                
                var attrName = (attrNameIndex == 0xFFFFFFFF) ? nil : stringBlock.getString(at: attrNameIndex)
                var resId: UInt32? = nil
                
                // Use resourceMap to look up system attribute names
                if attrNameIndex >= 0 && attrNameIndex != 0xFFFFFFFF && attrNameIndex < self.resourceMap.count {
                    resId = self.resourceMap[attrNameIndex]
                    if let resId = resId, let sysName = SystemResources.attributes[resId] {
                        let sysNameAdjusted = sysName.replacingOccurrences(of: "_", with: ":")
                        // Prefer system resource name if string block is empty or missing
                        if attrName == nil || attrName?.isEmpty == true || attrName == ":" {
                            attrName = sysNameAdjusted
                        } else if attrName != sysNameAdjusted {
                            // If StringBlock name doesn't match SystemResource name, system resource name is usually correct due to packer tools
                            attrName = sysNameAdjusted
                        }
                    }
                }
                
                if attrName == nil || attrName == ":" {
                    if let resId = resId {
                        attrName = String(format: "UNKNOWN_SYSTEM_ATTRIBUTE_%08x", resId)
                    } else {
                        attrName = ""
                    }
                }

                // If attribute value type is TYPE_STRING, we must lookup the string index, not data
                let attrValue: String?
                if attrValueType == 0x03 /* TYPE_STRING */ {
                    attrValue = (attrValueStringIndex == 0xFFFFFFFF) ? "" : stringBlock.getString(at: attrValueStringIndex)
                } else {
                    attrValue = formatValue(type: attrValueType, data: attrValueData)
                }

                self.attributes.append(Attribute(namespace: attrNs, name: attrName ?? "", value: attrValue ?? ""))
                attributesStart += attributeSize
            }
            cursor += Int(header.size)
            return .startTag

        case .RES_XML_END_ELEMENT_TYPE:
            event = .endTag
            let nsIndex = Int(data.withUnsafeBytes { $0.load(fromByteOffset: chunkContentStart, as: UInt32.self).littleEndian })
            let nameIndex = Int(data.withUnsafeBytes { $0.load(fromByteOffset: chunkContentStart + 4, as: UInt32.self).littleEndian })
            self.namespace = (nsIndex == 0xFFFFFFFF) ? nil : stringBlock.getString(at: nsIndex)
            self.name = (nameIndex == 0xFFFFFFFF) ? nil : stringBlock.getString(at: nameIndex)
            cursor += Int(header.size)
            return .endTag

        case .RES_XML_CDATA_TYPE:
            event = .text
            let textIndex = Int(data.withUnsafeBytes { $0.load(fromByteOffset: chunkContentStart + 4, as: UInt32.self).littleEndian })
            self.text = stringBlock.getString(at: textIndex)
            cursor += Int(header.size)
            return .text

        default:
            // End of document
            event = .endDocument
            return .endDocument
        }
    }

    private static func parseHeader(cursor: inout Int, data: Data, expected: ChunkType? = nil) throws -> (type: ChunkType, headerSize: UInt16, size: UInt32) {
        let typeValue = data.withUnsafeBytes { $0.load(fromByteOffset: cursor, as: UInt16.self).littleEndian }
        let headerSize = data.withUnsafeBytes { $0.load(fromByteOffset: cursor + 2, as: UInt16.self).littleEndian }
        let size = data.withUnsafeBytes { $0.load(fromByteOffset: cursor + 4, as: UInt32.self).littleEndian }

        guard let type = ChunkType(rawValue: typeValue) else {
            throw AXMLParserError.unknownChunkType(typeValue)
        }

        if let expected = expected, expected != type {
            throw AXMLParserError.unexpectedChunkType(expected: expected, actual: type)
        }

        return (type, headerSize, size)
    }

    private func formatValue(type: Int, data: Int) -> String? {
        // This is a simplified version. A full implementation would handle all types.
        switch type {
        case 0x01: // TYPE_REFERENCE
            return String(format: "@%08x", data)
        case 0x03: // TYPE_STRING
            return stringBlock.getString(at: data)
        case 0x10: // TYPE_INT_DEC
            return String(data)
        case 0x11: // TYPE_INT_HEX
            return String(format: "0x%08x", data)
        case 0x12: // TYPE_INT_BOOLEAN
            return data == 0 ? "false" : "true"
        default:
            return String(format: "<0x%x, type 0x%02x>", data, type)
        }
    }
}

enum AXMLParserError: Error {
    case unexpectedChunkType(expected: ChunkType, actual: ChunkType)
    case unknownChunkType(UInt16)
}
