
import Foundation

class AXMLPrinter {
    private var parser: AXMLParser
    private var indent = 0

    init(data: Data) throws {
        self.parser = try AXMLParser(data: data)
    }

    func getXML() throws -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        var event = try parser.next()

        while event != .endDocument {
            switch event {
            case .startTag:
                xml += indentString() + "<"
                if let namespace = parser.namespace, !namespace.isEmpty {
                    xml += namespace + ":"
                }
                xml += parser.name ?? ""

                for attr in parser.attributes {
                    xml += " "
                    if let attrNs = attr.namespace, !attrNs.isEmpty {
                        xml += attrNs + ":"
                    }
                    xml += attr.name + "=\"" + escape(attr.value) + "\""
                }
                xml += ">\n"
                indent += 1
            case .endTag:
                indent -= 1
                xml += indentString() + "</"
                if let namespace = parser.namespace, !namespace.isEmpty {
                    xml += namespace + ":"
                }
                xml += parser.name ?? ""
                xml += ">\n"
            case .text:
                xml += indentString() + (parser.text ?? "") + "\n"
            default:
                break
            }
            event = try parser.next()
        }
        return xml
    }

    private func indentString() -> String {
        return String(repeating: "  ", count: indent)
    }

    private func escape(_ string: String) -> String {
        return string.replacingOccurrences(of: "&", with: "&")
                     .replacingOccurrences(of: "<", with: "<")
                     .replacingOccurrences(of: ">", with: ">")
                     .replacingOccurrences(of: "\\\"", with: "\"")
                     .replacingOccurrences(of: "'", with: "'")
    }
}
