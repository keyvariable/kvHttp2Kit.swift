// swift-tools-version:5.3
//
//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2021 Svyatoslav Popov (info@keyvar.com).
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
//  the License. You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
//  an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
//  specific language governing permissions and limitations under the License.
//
//  SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import PackageDescription


let swiftSettings: [SwiftSetting]? = nil


let package = Package(
    name: "kvServerKit.swift",

    platforms: [ .macOS(.v10_15), .iOS(.v13), ],

    products: [
        .library(name: "kvServerKit", targets: [ "kvServerKit" ]),
        .library(name: "kvHttpKit", targets: [ "kvHttpKit" ]),
        .library(name: "kvHttpKit_NIOHTTP1", targets: [ "kvHttpKit_NIOHTTP1" ]),
    ],

    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.13.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.24.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.6.0"),
        .package(url: "https://github.com/keyvariable/kvKit.swift.git", from: "4.7.0"),
    ],
    
    targets: [
        .target(name: "kvServerKit",
                dependencies: [ "kvHttpKit_NIOHTTP1",
                                .product(name: "kvKit", package: "kvKit.swift"),
                                .product(name: "NIO", package: "swift-nio"),
                                .product(name: "NIOHTTP1", package: "swift-nio"),
                                .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                                .product(name: "NIOSSL", package: "swift-nio-ssl") ],
                swiftSettings: swiftSettings),

        .testTarget(name: "kvServerKitTests",
                    dependencies: [ "kvServerKit" ],
                    resources: [ .copy("Resources/html"),
                                 .copy("Resources/html_status"),
                                 .copy("Resources/https.pem"),
                                 .copy("Resources/sample.txt") ],
                    swiftSettings: swiftSettings),

        .target(name: "kvHttpKit",
                dependencies: [ .product(name: "kvKit", package: "kvKit.swift") ],
                swiftSettings: swiftSettings),

        .target(name: "kvHttpKit_NIOHTTP1",
                dependencies: [ "kvHttpKit",
                                .product(name: "NIOHTTP1", package: "swift-nio") ],
                swiftSettings: swiftSettings),

        .testTarget(name: "kvHttpKitTests",
                    dependencies: [ "kvHttpKit" ],
                    resources: [ .copy("Resources/html"),
                                 .copy("Resources/sample.txt")],
                    swiftSettings: swiftSettings)


    ]
)
