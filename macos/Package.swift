// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "O2MailGuardian",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "O2MailGuardianApp", targets: ["O2MailGuardianApp"]),
    ],
    targets: [
        .executableTarget(name: "O2MailGuardianApp"),
        .testTarget(name: "O2MailGuardianAppTests", dependencies: ["O2MailGuardianApp"]),
    ]
)
