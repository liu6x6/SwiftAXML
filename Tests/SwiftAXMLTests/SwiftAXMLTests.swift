import XCTest
@testable import SwiftAXML

final class SwiftAXMLTests: XCTestCase {

    func testAppInfoExtraction() throws {
        // Use SPM's resource bundle to correctly locate test data regardless of the working directory
        guard let fileURL = Bundle.module.url(forResource: "AndroidManifest-xmlns", withExtension: "xml", subdirectory: "Data") else {
            XCTFail("Could not locate Data/AndroidManifest-xmlns.xml in the test bundle.")
            return
        }
        
        let data = try Data(contentsOf: fileURL)
        let parser = try AXMLManifestParser(data: data)
        let info = parser.getAppInfo()
        
        XCTAssertEqual(info["bundleIdentifier"] as? String, "com.real.RealPlayer")
        XCTAssertEqual(info["version"] as? String, "0.0.0.61")
        XCTAssertEqual(info["buildNumber"] as? String, "8")
        XCTAssertEqual(info["name"] as? String, "@7f0a0000")
        XCTAssertEqual(info["icon"] as? String, "@7f0200ac")
        XCTAssertEqual(info["minimumOSVersion"] as? String, "4")
        
        guard let permissions = info["permissions"] as? [String] else {
            XCTFail("Missing permissions array in getAppInfo")
            return
        }
        XCTAssertTrue(permissions.contains("android.permission.INTERNET"))
        XCTAssertTrue(permissions.contains("android.permission.WRITE_EXTERNAL_STORAGE"))
        XCTAssertEqual(permissions.count, 12)
        
        // Verify advanced extraction features
        XCTAssertNotNil(info["manifest"] as? [String: String])
        XCTAssertNotNil(info["application"] as? [String: String])
        let activities = info["activities"] as? [[String: String]]
        XCTAssertNotNil(activities)
    }

    func testStandardManifestExtraction() throws {
        guard let fileURL = Bundle.module.url(forResource: "AndroidManifest", withExtension: "xml", subdirectory: "Data") else {
            XCTFail("Could not locate Data/AndroidManifest.xml in the test bundle.")
            return
        }
        
        let data = try Data(contentsOf: fileURL)
        let parser = try AXMLManifestParser(data: data)
        let info = parser.getAppInfo()
        
        XCTAssertEqual(info["bundleIdentifier"] as? String, "org.t0t0.androguard.TC")
        XCTAssertEqual(info["version"] as? String, "1.0")
        XCTAssertEqual(info["buildNumber"] as? String, "1")
        
        guard let permissions = info["permissions"] as? [String] else {
            XCTFail("Missing permissions array in getAppInfo")
            return
        }
        XCTAssertEqual(permissions.count, 0)
    }
}
