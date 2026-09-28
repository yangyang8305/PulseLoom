// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PulseLoomCore", platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [.library(name: "PulseLoomCore", targets: ["PulseLoomCore"])],
    targets: [.target(name: "PulseLoomCore", resources: [.process("Resources")]),
              .testTarget(name: "PulseLoomCoreTests", dependencies: ["PulseLoomCore"])])
