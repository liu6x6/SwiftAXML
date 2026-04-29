import Foundation

extension ARSCParser {
    public func resolveString(resId: UInt32) -> String? {
        let targetPP = Int((resId >> 24) & 0xFF)
        let targetTT = Int((resId >> 16) & 0xFF)
        let targetEEEE = Int(resId & 0xFFFF)
        
        for (_, package) in packages {
            if package.id == targetPP {
                for (_, type) in package.types {
                    if type.id == targetTT {
                        var foundLocales: [String: String] = [:]
                        for (locale, values) in type.entries {
                            if let val = values.first(where: { $0.resId == targetEEEE })?.value {
                                foundLocales[locale] = val
                            }
                        }
                        
                        let preferredLocales = ["zh-CN", "zh", "en-US", "en", "default", ""]
                        for loc in preferredLocales {
                            if let val = foundLocales[loc] {
                                return val
                            }
                        }
                        return foundLocales.values.first
                    }
                }
            }
        }
        return nil
    }
}
