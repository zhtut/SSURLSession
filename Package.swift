// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(name: "SSURLSession",
                      products: [
                        .library(name: "SSURLSession", targets: ["SSURLSession"]),
                      ],
                      dependencies: [
                        .package(url: "https://github.com/zhtut/CFURLSessionInterface.git", from: "0.1.0")
                      ],
                      targets: [
                        .target(name: "SSURLSession", dependencies: ["CFURLSessionInterface"]),
                        .testTarget(name: "SSURLSessionTests", dependencies: ["SSURLSession"])
                      ])
