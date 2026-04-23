
import Foundation

public class ARSCPrinter {
    private var parser: ARSCParser

    public init(data: Data) throws {
        self.parser = try ARSCParser(data: data)
    }

    public func getXML(packageName: String, locale: String = "\\x00\\x00") -> String {
        return parser.getPublicResources(packageName: packageName, locale: locale)
    }
}
