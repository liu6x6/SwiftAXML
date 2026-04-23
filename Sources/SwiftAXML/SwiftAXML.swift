
import Foundation

@main
struct SwiftAXML {
    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count < 3 {
            print("Usage: SwiftAXML <axml|arsc|info> <file>")
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
        case "info":
            let manifestParser = try AXMLManifestParser(data: fileData)
            let appInfo = manifestParser.getAppInfo()
            print("--- App Info Dictionary ---")
            for (key, value) in appInfo {
                print("\(key): \(value)")
            }
            print("\n--- Permissions ---")
            let permissions = manifestParser.getPermissions()
            for perm in permissions {
                print(perm)
            }
        default:
            print("Unknown type: \(type)")
        }
    }
}
