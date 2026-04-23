
import Foundation

@main
struct SwiftAXML {
    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count < 3 {
            print("Usage: SwiftAXML <axml|arsc> <file>")
            return
        }

        let type = arguments[1]
        let filePath = arguments[2]
        let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))

        switch type {
        case "axml":
            let printer = try AXMLPrinter(data: fileData)
            print(try printer.getXML())
        case "arsc":
            let printer = try ARSCPrinter(data: fileData)
            // You might need to specify the package name here
            print(printer.getXML(packageName: ""))
        default:
            print("Unknown type: \(type)")
        }
    }
}
