# SwiftAXML

A fast, native Swift implementation for parsing Android's binary XML (AXML) and resource files. It is designed for Apple platforms and Server-Side Swift, providing both low-level XML generation (`AXMLPrinter`) and high-level App Metadata extraction (`AXMLManifestParser`).

Android doesn't speak in plain text XML. To save space and speed up parsing, it uses a compressed, obfuscated binary format (AXML) for its manifests and a complex table (ARSC) for its resources. **SwiftAXML** allows you to read these formats natively on iOS, macOS, or Linux.

## Installation & CLI Usage

You can build and run the Swift tool directly:

```bash
$ cd SwiftAXML
$ swift build -c release

# Parse AXML back into a readable XML string:
$ swift run swift-axml axml /path/to/AndroidManifest.xml

# Quickly extract and print high-level App Info & Permissions:
$ swift run swift-axml info /path/to/AndroidManifest.xml
```

## API Usage

Add `SwiftAXML` as a dependency in your `Package.swift` or use it directly in your workspace.

### 1. Extracting App Metadata (`AXMLManifestParser`)

This is the recommended high-level API if you want to extract standard app properties (like bundle ID, version, etc.) similar to an iOS `Info.plist`.

```swift
import SwiftAXML
import Foundation

let data = try Data(contentsOf: URL(fileURLWithPath: "AndroidManifest.xml"))
let parser = try AXMLManifestParser(data: data)

// Get standard app properties
let appInfo = parser.getAppInfo()

print(appInfo["bundleIdentifier"] as? String ?? "") // e.g. "com.example.app"
print(appInfo["version"] as? String ?? "")          // e.g. "1.0.0"
print(appInfo["buildNumber"] as? String ?? "")      // e.g. "105"
print(appInfo["name"] as? String ?? "")             // e.g. "@7f110032"

// Get all requested Android permissions
let permissions: [String] = parser.getPermissions()
for perm in permissions {
    print(perm) // e.g. "android.permission.INTERNET"
}
```

The `getAppInfo()` dictionary provides the following keys:
- `bundleIdentifier`: Android `package` name.
- `version`: `android:versionName`.
- `buildNumber`: `android:versionCode`.
- `name`: App's label.
- `icon`: App's icon resource ID.
- `minimumOSVersion`: `minSdkVersion`.
- `sdkVersion`: `targetSdkVersion`.
- `permissions`: Array of strings containing all requested `uses-permission` declarations.
- `entitlements`: (Empty dictionary mapped for cross-platform model usage).
- `deviceFamily`: (Empty array mapped for cross-platform model usage).

### 2. Generating XML (`AXMLPrinter`)

If you need the full text of the Android Manifest XML:

```swift
import SwiftAXML
import Foundation

let data = try Data(contentsOf: URL(fileURLWithPath: "AndroidManifest.xml"))
let printer = try AXMLPrinter(data: data)
let xmlString = try printer.getXML()

print(xmlString) // <?xml version="1.0" encoding="utf-8"?>...
```

## reference
https://android.googlesource.com/platform/frameworks/base/+/master/libs/androidfw/include/androidfw/ResourceTypes.h
https://juejin.cn/post/7005944481455439903
https://github.com/senswrong/AndroidBinaryXml
https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/tools/aapt2/ApkInfo.proto
https://github.com/androguard/axml
