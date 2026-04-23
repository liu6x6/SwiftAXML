
import Foundation
import SwiftAXML

let arguments = CommandLine.arguments
if arguments.count < 3 {
    print("Usage: swift-axml <axml|arsc|info> <file> [arsc_file_path]")
    exit(1)
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
    var arscData: Data? = nil
    if arguments.count >= 4 {
        let arscPath = arguments[3]
        arscData = try Data(contentsOf: URL(fileURLWithPath: arscPath))
    }

    let manifestParser = try AXMLManifestParser(data: fileData, arscData: arscData)
    let appInfo = manifestParser.getAppInfo()
    print("--- App Info Dictionary ---")
    for (key, value) in appInfo {
        if let dict = value as? [String: Any] {
            print("\(key): \(dict.count) items")
        } else if let arr = value as? [Any] {
            print("\(key): \(arr.count) items")
        } else {
            print("\(key): \(value)")
        }
    }
    
    // Print advanced details if user wants them? We just print the basic ones directly, 
    // and print "X items" for arrays/dicts above to avoid massive output.
    
    print("\n--- Permissions ---")
    let permissions = manifestParser.getPermissions()
    for perm in permissions {
        print(perm)
    }
default:
    print("Unknown type: \(type)")
}
