// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftAXML",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SwiftAXML",
            targets: ["SwiftAXML"]
        ),
        .executable(
            name: "swift-axml",
            targets: ["SwiftAXMLCLI"]
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SwiftAXML"
        ),
        .executableTarget(
            name: "SwiftAXMLCLI",
            dependencies: ["SwiftAXML"]
        ),
        .testTarget(
            name: "SwiftAXMLTests",
            dependencies: ["SwiftAXML"],
            resources: [
                .copy("Data")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
