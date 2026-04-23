
import Foundation

class ARSCPrinter {
    private var parser: ARSCParser

    init(data: Data) throws {
        self.parser = try ARSCParser(data: data)
    }

    func getXML(packageName: String, locale: String = "") -> String {
        return parser.getPublicResources(packageName: packageName, locale: locale)
    }
}
