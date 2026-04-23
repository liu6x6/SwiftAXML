
import Foundation

public class AXMLPrinter {
    private var parser: AXMLParser
    private var indent = 0

    public init(data: Data) throws {
        self.parser = try AXMLParser(data: data)
    }

    public func getXML() throws -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        var event = try parser.next()
        var tagStack: [(prefix: String?, name: String)] = []
        var isRoot = true

        while event != .endDocument {
            switch event {
            case .startTag:
                xml += indentString() + "<"
                let prefix = getPrefix(for: parser.namespace)
                if let prefix = prefix, !prefix.isEmpty {
                    xml += prefix + ":"
                }
                let tagName = parser.name ?? ""
                xml += tagName
                tagStack.append((prefix: prefix, name: tagName))

                if isRoot {
                    for (uri, pfx) in parser.namespaceUriPrefixMap {
                        xml += " xmlns:" + pfx + "=\"" + uri + "\""
                    }
                    isRoot = false
                }

                for attr in parser.attributes {
                    xml += " "
                    let attrPrefix = getPrefix(for: attr.namespace)
                    if let attrPrefix = attrPrefix, !attrPrefix.isEmpty {
                        xml += attrPrefix + ":"
                    }
                    xml += attr.name + "=\"" + escape(attr.value) + "\""
                }
                xml += ">\n"
                indent += 1
            case .endTag:
                indent -= 1
                xml += indentString() + "</"
                if let lastTag = tagStack.popLast() {
                    if let prefix = lastTag.prefix, !prefix.isEmpty {
                        xml += prefix + ":"
                    }
                    xml += lastTag.name
                } else {
                    let prefix = getPrefix(for: parser.namespace)
                    if let prefix = prefix, !prefix.isEmpty {
                        xml += prefix + ":"
                    }
                    xml += parser.name ?? ""
                }
                xml += ">\n"
            case .text:
                if let text = parser.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    xml += indentString() + text + "\n"
                }
            default:
                break
            }
            event = try parser.next()
        }
        return xml
    }

    private func getPrefix(for uri: String?) -> String? {
        guard let uri = uri, !uri.isEmpty else { return nil }
        return parser.namespaceUriPrefixMap[uri]
    }

    private func indentString() -> String {
        return String(repeating: "  ", count: indent)
    }

    private func escape(_ string: String) -> String {
        return string.replacingOccurrences(of: "&", with: "&amp;")
                     .replacingOccurrences(of: "<", with: "&lt;")
                     .replacingOccurrences(of: ">", with: "&gt;")
                     .replacingOccurrences(of: "\\\"", with: "&quot;")
                     .replacingOccurrences(of: "'", with: "&apos;")
    }
}
