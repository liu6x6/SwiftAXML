
import Foundation

public class ARSCParser {
    private var data: Data
    private var mainStringPool: StringBlock?
    private var packages: [String: Package] = [:]
    
    // Flat map of all resources for fast lookup by ID
    public var resourceMap: [Int: String] = [:]

    public init(data: Data) throws {
        self.data = data
        do {
            try parse()
        } catch {
            // Ignore top level parse failures so that whatever was loaded into resourceMap
            // can still be used, and so the caller doesn't crash when passing arscData
        }
    }

    private func parse() throws {
        var cursor = 0

        // ResTable_header
        _ = try ARSCParser.parseHeader(at: &cursor, data: data, expected: .RES_TABLE_TYPE)
        let packageCount = Int(data.withUnsafeBytes { $0.load(fromByteOffset: cursor, as: UInt32.self).littleEndian })
        cursor += 4

        // Main String Pool
        var stringPoolCursor = cursor
        let stringPoolHeader = try ARSCParser.parseHeader(at: &stringPoolCursor, data: data, expected: .RES_STRING_POOL_TYPE)
        let stringPoolData = data.subdata(in: cursor..<(cursor + Int(stringPoolHeader.size)))
        self.mainStringPool = try StringBlock(data: stringPoolData)
        cursor += Int(stringPoolHeader.size)

        for _ in 0..<packageCount {
            if cursor >= data.count { break }
            do {
                let package = try Package(data: data, offset: &cursor, mainStringPool: mainStringPool)
                packages[package.name] = package
                
                // Populate the fast lookup map
                for (_, type) in package.types {
                    for (locale, values) in type.entries {
                        for value in values {
                            if resourceMap[value.resId] == nil || locale == "" {
                                resourceMap[value.resId] = value.value
                            }
                        }
                    }
                }
            } catch {
                // Stop parsing packages but don't blow up the entire ARSC initialization 
                // if there are malformed packages. Often only the first package contains 
                // the metadata we care about.
                break
            }
        }
    }

    public func getPublicResources(packageName: String, locale: String = "") -> String {
        guard let package = packages[packageName] else { return "" }
        return package.getPublicResources(locale: locale)
    }
    
    public func resolve(resourceId: Int) -> String? {
        return resourceMap[resourceId]
    }

    static func parseHeader(at cursor: inout Int, data: Data, expected: ChunkType? = nil) throws -> (type: ChunkType, headerSize: UInt16, size: UInt32) {
        let typeValue = data.withUnsafeBytes { $0.load(fromByteOffset: cursor, as: UInt16.self).littleEndian }
        let headerSize = data.withUnsafeBytes { $0.load(fromByteOffset: cursor + 2, as: UInt16.self).littleEndian }
        let size = data.withUnsafeBytes { $0.load(fromByteOffset: cursor + 4, as: UInt32.self).littleEndian }

        let type = ChunkType(rawValue: typeValue)

        if let expected = expected, expected != type {
            // Instead of throwing immediately, we just log/return the chunk we found. 
            // In ARSC we might want to be resilient against obfuscated formats.
            // But if it's explicitly expected and doesn't match, we still throw to abort that branch.
            throw ARSCParserError.unexpectedChunkType(expected: expected, actual: type)
        }

        return (type, headerSize, size)
    }
}

public class Package {
    public let packageId: Int
    public let name: String
    private var typeStringPool: StringBlock
    private var keyStringPool: StringBlock
    public var types: [String: ResourceType] = [:]

    init(data: Data, offset: inout Int, mainStringPool: StringBlock?) throws {
        let packageHeaderStart = offset
        var packageCursor = offset
        let packageHeader = try ARSCParser.parseHeader(at: &packageCursor, data: data, expected: .RES_TABLE_PACKAGE_TYPE)
        packageCursor = packageHeaderStart + Int(packageHeader.headerSize)
        
        self.packageId = Int(data.withUnsafeBytes { $0.load(fromByteOffset: packageCursor, as: UInt32.self).littleEndian })
        packageCursor += 4
        
        let nameData = data.subdata(in: packageCursor..<(packageCursor + 256))
        self.name = String(data: nameData, encoding: .utf16LittleEndian)?.trimmingCharacters(in: .init(charactersIn: "\0")) ?? ""
        packageCursor += 256
        
        let typeStringsOffset = Int(data.withUnsafeBytes { $0.load(fromByteOffset: packageCursor, as: UInt32.self).littleEndian })
        packageCursor += 4
        _ = Int(data.withUnsafeBytes { $0.load(fromByteOffset: packageCursor, as: UInt32.self).littleEndian })
        packageCursor += 4
        let keyStringsOffset = Int(data.withUnsafeBytes { $0.load(fromByteOffset: packageCursor, as: UInt32.self).littleEndian })
        packageCursor += 4
        _ = Int(data.withUnsafeBytes { $0.load(fromByteOffset: packageCursor, as: UInt32.self).littleEndian })
        packageCursor += 4


        // Type String Pool
        var typeStringPoolOffset = packageHeaderStart + typeStringsOffset
        let typeStringPoolHeader = try ARSCParser.parseHeader(at: &typeStringPoolOffset, data: data, expected: .RES_STRING_POOL_TYPE)
        let typeStringPoolData = data.subdata(in: (packageHeaderStart + typeStringsOffset)..<(packageHeaderStart + typeStringsOffset + Int(typeStringPoolHeader.size)))
        self.typeStringPool = try StringBlock(data: typeStringPoolData)

        // Key String Pool
        var keyStringPoolOffset = packageHeaderStart + keyStringsOffset
        let keyStringPoolHeader = try ARSCParser.parseHeader(at: &keyStringPoolOffset, data: data, expected: .RES_STRING_POOL_TYPE)
        let keyStringPoolData = data.subdata(in: (packageHeaderStart + keyStringsOffset)..<(packageHeaderStart + keyStringsOffset + Int(keyStringPoolHeader.size)))
        self.keyStringPool = try StringBlock(data: keyStringPoolData)

        packageCursor = packageHeaderStart + Int(packageHeader.headerSize)

        while packageCursor < packageHeaderStart + Int(packageHeader.size) {
            var chunkHeaderOffset = packageCursor
            let chunkHeader = try ARSCParser.parseHeader(at: &chunkHeaderOffset, data: data)
            
            if chunkHeader.type == .RES_TABLE_TYPE_SPEC_TYPE {
                 packageCursor += Int(chunkHeader.size)
            } else if chunkHeader.type == .RES_TABLE_TYPE_TYPE {
                var typeOffset = packageCursor
                do {
                    let type = try ResourceType(data: data, offset: &typeOffset, packageId: packageId, typeStringPool: typeStringPool, keyStringPool: keyStringPool, mainStringPool: mainStringPool)
                    types[type.name] = type
                } catch {
                    // Ignore errors inside obfuscated types to salvage the rest of the file
                }
                packageCursor += Int(chunkHeader.size)
            } else {
                // Unknown chunk, skip it instead of breaking completely to support obfuscated ARSC
                if chunkHeader.size == 0 { break } // Prevent infinite loop
                packageCursor += Int(chunkHeader.size)
            }
        }
        offset = packageHeaderStart + Int(packageHeader.size)
    }

    public func getPublicResources(locale: String) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n"
        for (_, type) in types {
            xml += type.getPublicResources(locale: locale)
        }
        xml += "</resources>\n"
        return xml
    }
}

public class ResourceType {
    public let name: String
    public var entries: [String: [ResourceValue]] = [:]

    init(data: Data, offset: inout Int, packageId: Int, typeStringPool: StringBlock, keyStringPool: StringBlock, mainStringPool: StringBlock?) throws {
        let typeChunkStart = offset
        var typeCursor = offset
        let typeChunkHeader = try ARSCParser.parseHeader(at: &typeCursor, data: data, expected: .RES_TABLE_TYPE_TYPE)
        typeCursor = typeChunkStart + Int(typeChunkHeader.headerSize)
        
        let typeId = Int(data.withUnsafeBytes { $0.load(fromByteOffset: typeCursor, as: UInt8.self) })
        self.name = typeStringPool.getString(at: typeId - 1) ?? ""
        typeCursor += 4
        
        let entryCount = Int(data.withUnsafeBytes { $0.load(fromByteOffset: typeCursor, as: UInt32.self).littleEndian })
        typeCursor += 4
        
        let entriesStart = Int(data.withUnsafeBytes { $0.load(fromByteOffset: typeCursor, as: UInt32.self).littleEndian })
        typeCursor += 4

        let config = try ResTableConfig(data: data, offset: &typeCursor)
        let locale = config.getLocale()

        var entryOffsets: [Int] = []
        for _ in 0..<entryCount {
            let entryOffset = Int(data.withUnsafeBytes { $0.load(fromByteOffset: typeCursor, as: UInt32.self).littleEndian })
            entryOffsets.append(entryOffset)
            typeCursor += 4
        }
        
        for (entryId, entryOffset) in entryOffsets.enumerated() {
            if entryOffset == 0xFFFFFFFF { continue }

            var valueOffset = typeChunkStart + entriesStart + entryOffset
            let resId = (packageId << 24) | (typeId << 16) | entryId
            
            let value = try ResourceValue(data: data, offset: &valueOffset, calculatedResId: resId, keyStringPool: keyStringPool, mainStringPool: mainStringPool)
            if entries[locale] == nil {
                entries[locale] = []
            }
            entries[locale]?.append(value)
        }
        offset = typeChunkStart + Int(typeChunkHeader.size)
    }

    public func getPublicResources(locale: String) -> String {
        var xml = ""
        guard let values = entries[locale] else { return "" }
        for value in values {
            let id = String(format: "%08x", value.resId)
            xml += "  <public type=\"\(name)\" name=\"\(value.name)\" id=\"0x\(id)\" />\n"
        }
        return xml
    }
}

public struct ResourceValue {
    public let name: String
    public let resId: Int
    public let value: String

    init(data: Data, offset: inout Int, calculatedResId: Int, keyStringPool: StringBlock, mainStringPool: StringBlock?) throws {
        _ = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self).littleEndian })
        offset += 2
        _ = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self).littleEndian })
        offset += 2
        let keyIndex = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian })
        self.name = keyStringPool.getString(at: keyIndex) ?? ""
        offset += 4

        _ = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt16.self).littleEndian })
        offset += 2
        let valueType = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt8.self) })
        offset += 1 // res0
        let valueData = Int(data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian })
        offset += 4

        self.resId = calculatedResId
        self.value = ARSCParser.formatValue(type: valueType, data: valueData, stringPool: mainStringPool)
    }
}

struct ResTableConfig {
    let language: String
    let country: String

    init(data: Data, offset: inout Int) throws {
        let size = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self).littleEndian }
        
        var lang = ""
        var country = ""
        
        if size >= 8 {
            let langBytes = [data[offset + 4], data[offset + 5]]
            lang = String(bytes: langBytes.filter { $0 != 0 }, encoding: .ascii) ?? ""
            
            let countryBytes = [data[offset + 6], data[offset + 7]]
            country = String(bytes: countryBytes.filter { $0 != 0 }, encoding: .ascii) ?? ""
        }
        
        self.language = lang
        self.country = country
        
        offset += Int(size)
    }

    func getLocale() -> String {
        if !language.isEmpty && !country.isEmpty {
            return "\(language)-r\(country)"
        } else if !language.isEmpty {
            return language
        }
        return ""
    }
}

enum ARSCParserError: Error {
    case unexpectedChunkType(expected: ChunkType, actual: ChunkType)
    case unknownChunkType(UInt16)
}

extension ARSCParser {
    static func formatValue(type: Int, data: Int, stringPool: StringBlock?) -> String {
        switch type {
        case 0x01: // TYPE_REFERENCE
            return String(format: "@%08x", data)
        case 0x03: // TYPE_STRING
            return stringPool?.getString(at: data) ?? ""
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
