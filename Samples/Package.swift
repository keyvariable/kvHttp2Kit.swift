// swift-tools-version:5.4
//
//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2023 Svyatoslav Popov (info@keyvar.com).
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
//
//  Package.swift
//  kvServerKit/Samples
//
//  Created by Svyatoslav Popov on 03.07.2023.
//

import PackageDescription


let package = Package(
    name: "Samples-kvServerKit",

    platforms: [ .iOS(.v11), .macOS(.v10_15), ],

    products: [ .executable(name: "DeclarativeServer", targets: [ "DeclarativeServer" ]),
                .executable(name: "ImperativeServer", targets: [ "ImperativeServer" ]) ],

    dependencies: [ .package(path: "../") ],

    targets: [
        .executableTarget(
            name: "DeclarativeServer",
            dependencies: [ .product(name: "kvServerKit", package: "kvServerKit.swift") ],
            resources: [ .copy("Resources") ]
        ),
        .executableTarget(
            name: "ImperativeServer",
            dependencies: [ .product(name: "kvServerKit", package: "kvServerKit.swift") ],
            resources: [ .copy("Resources") ]
        ),
    ]
)
