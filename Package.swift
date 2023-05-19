// swift-tools-version:5.2
//
//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2021 Svyatoslav Popov.
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


let targets: [Target] = [
    .target(name: "kvHttp2Kit",
            dependencies: [ .product(name: "kvKit", package: "kvKit-Swift"),
                            .product(name: "NIO", package: "swift-nio"),
                            .product(name: "NIOHTTP1", package: "swift-nio"),
                            .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                            .product(name: "NIOSSL", package: "swift-nio-ssl") ]),
    .testTarget(name: "kvHttp2KitTests", dependencies: [ "kvHttp2Kit" ]),
]

let package = Package(
    name: "kvHttp2Kit-Swift",
    platforms: [ .iOS(.v11), ],
    products: [
        .library(name: "kvHttp2Kit", targets: [ "kvHttp2Kit" ]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.13.0"),
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.9.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.6.0"),
        .package(url: "https://github.com/keyvariable/kvKit-Swift.git", from: "3.0.0"),
    ],
    targets: targets
)
