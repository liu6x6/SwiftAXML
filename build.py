import re

with open('Sources/SwiftAXML/ARSCParser.swift', 'r') as f:
    content = f.read()

content = content.replace('private var packages: [String: Package] = [:]', 'public var packages: [String: Package] = [:]')
content = content.replace('class Package {', 'public class Package {')
content = content.replace('let name: String', 'public let name: String\n    public var id: Int = 0')
content = content.replace('private var types: [String: ResourceType] = [:]', 'public var types: [String: ResourceType] = [:]')
content = content.replace('class ResourceType {', 'public class ResourceType {')
content = content.replace('let name: String\n    private var entries', 'public let name: String\n    public var id: Int = 0\n    public var entries')
content = content.replace('struct ResourceValue {', 'public struct ResourceValue {')
content = content.replace('let name: String\n    let resId: Int\n    let value: String', 'public let name: String\n    public var resId: Int\n    public let value: String')

# Fix init for Package to set ID
content = content.replace(
    'let packageHeader = try ARSCParser.parseHeader(at: &packageCursor, data: data, expected: .RES_TABLE_PACKAGE_TYPE)\n        packageCursor = packageHeaderStart + Int(packageHeader.headerSize)\n        \n        _ = Int(data.withUnsafeBytes { $0.load(fromByteOffset: packageCursor, as: UInt32.self).littleEndian })',
    'let packageHeader = try ARSCParser.parseHeader(at: &packageCursor, data: data, expected: .RES_TABLE_PACKAGE_TYPE)\n        packageCursor = packageHeaderStart + Int(packageHeader.headerSize)\n        \n        self.id = Int(data.withUnsafeBytes { $0.load(fromByteOffset: packageCursor, as: UInt32.self).littleEndian })'
)

# Fix init for ResourceType to set ID
content = content.replace(
    'let typeId = Int(data.withUnsafeBytes { $0.load(fromByteOffset: typeCursor, as: UInt8.self) })\n        self.name = typeStringPool.getString(at: typeId - 1) ?? ""',
    'let typeId = Int(data.withUnsafeBytes { $0.load(fromByteOffset: typeCursor, as: UInt8.self) })\n        self.id = typeId\n        self.name = typeStringPool.getString(at: typeId - 1) ?? ""'
)

# Fix ResourceValue to accept resId
content = content.replace(
    'init(data: Data, offset: inout Int, keyStringPool: StringBlock, mainStringPool: StringBlock?) throws {',
    'init(data: Data, offset: inout Int, resId: Int, keyStringPool: StringBlock, mainStringPool: StringBlock?) throws {'
)
content = content.replace(
    'self.resId = 0 // This needs to be calculated properly',
    'self.resId = resId'
)

# Update the call site in ResourceType
content = content.replace(
    'for entryOffset in entryOffsets {',
    'for (index, entryOffset) in entryOffsets.enumerated() {'
)
content = content.replace(
    'let value = try ResourceValue(data: data, offset: &valueOffset, keyStringPool: keyStringPool, mainStringPool: mainStringPool)',
    'let value = try ResourceValue(data: data, offset: &valueOffset, resId: index, keyStringPool: keyStringPool, mainStringPool: mainStringPool)'
)

with open('Sources/SwiftAXML/ARSCParser.swift', 'w') as f:
    f.write(content)
