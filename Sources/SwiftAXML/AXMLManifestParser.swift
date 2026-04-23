import Foundation

public class AXMLManifestParser {
    public var name: String = ""
    public var bundleIdentifier: String = ""
    public var version: String = ""
    public var buildNumber: String = ""
    public var icon: String? = nil
    public var minimumOSVersion: String? = nil
    public var sdkVersion: String? = nil
    public var permissions: [String] = []

    // Advanced parsed data structures to hold "everything"
    public var manifestAttributes: [String: String] = [:]
    public var applicationAttributes: [String: String] = [:]
    public var usesSdkAttributes: [String: String] = [:]
    public var usesFeatures: [[String: String]] = []
    public var metaData: [[String: String]] = []
    public var activities: [[String: String]] = []
    public var services: [[String: String]] = []
    public var receivers: [[String: String]] = []
    public var providers: [[String: String]] = []

    private var arscParser: ARSCParser?

    public init(data: Data, arscData: Data? = nil) throws {
        if let arscData = arscData {
            self.arscParser = try ARSCParser(data: arscData)
        }
        
        let parser = try AXMLParser(data: data)
        var event = try parser.next()

        while event != .endDocument {
            if event == .startTag {
                let tagName = parser.name ?? ""
                
                var attrs: [String: String] = [:]
                for attr in parser.attributes {
                    attrs[attr.name] = resolveValue(attr.value)
                }

                switch tagName {
                case "manifest":
                    manifestAttributes = attrs
                    if let pkg = attrs["package"] { bundleIdentifier = pkg }
                    if let vName = attrs["versionName"] { version = vName }
                    if let vCode = attrs["versionCode"] { buildNumber = vCode }
                case "application":
                    applicationAttributes = attrs
                    if let lbl = attrs["label"] { name = lbl }
                    if let icn = attrs["icon"] { icon = icn }
                case "uses-sdk":
                    usesSdkAttributes = attrs
                    if let minSdk = attrs["minSdkVersion"] { minimumOSVersion = minSdk }
                    if let targetSdk = attrs["targetSdkVersion"] { sdkVersion = targetSdk }
                case "uses-permission":
                    if let perm = attrs["name"] {
                        permissions.append(perm)
                    }
                case "uses-feature":
                    usesFeatures.append(attrs)
                case "activity", "activity-alias":
                    activities.append(attrs)
                case "service":
                    services.append(attrs)
                case "receiver":
                    receivers.append(attrs)
                case "provider":
                    providers.append(attrs)
                case "meta-data":
                    metaData.append(attrs)
                default:
                    break
                }
            }
            event = try parser.next()
        }
    }

    private func resolveValue(_ value: String) -> String {
        guard value.hasPrefix("@"), let arscParser = arscParser else {
            return value
        }
        // Extract hex string, removing the '@'
        let hexString = String(value.dropFirst())
        guard let resId = Int(hexString, radix: 16) else {
            return value
        }
        
        if let resolvedString = arscParser.resolve(resourceId: resId) {
            // It could be another reference!
            if resolvedString.hasPrefix("@") && resolvedString != value {
                return resolveValue(resolvedString)
            }
            return resolvedString
        }
        
        return value
    }

    public func getAppInfo() -> [String: Any] {
        var info: [String: Any] = [
            "name": name,
            "bundleIdentifier": bundleIdentifier,
            "version": version,
            "buildNumber": buildNumber,
            "entitlements": [String: Any](),
            "deviceFamily": [String](),
            "permissions": permissions,
            "manifest": manifestAttributes,
            "application": applicationAttributes,
            "usesSdk": usesSdkAttributes,
            "usesFeatures": usesFeatures,
            "activities": activities,
            "services": services,
            "receivers": receivers,
            "providers": providers,
            "metaData": metaData
        ]
        
        if let icon = icon { info["icon"] = icon }
        if let minimumOSVersion = minimumOSVersion { info["minimumOSVersion"] = minimumOSVersion }
        if let sdkVersion = sdkVersion { info["sdkVersion"] = sdkVersion }
        
        return info
    }

    public func getPermissions() -> [String] {
        return permissions
    }
}