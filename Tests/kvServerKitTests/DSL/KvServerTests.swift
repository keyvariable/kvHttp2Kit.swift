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
//  KvServerTests.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 04.07.2023.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import XCTest

@testable import kvServerKit



final class KvServerTests : XCTestCase {

    // MARK: - testHeadMethod()

    func testHeadMethod() async throws {

        struct HeadMethodServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("a") {
                        KvHttpResponse { .string { "a" } }
                    }
                    KvGroup("b") {
                        KvHttpResponse { .string({ "b" }).contentLength(1) }
                    }
                    .httpMethods(.get)
                }
            }

        }

        try await TestKit.withRunningServer(of: HeadMethodServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(path: String, response: String) async throws {
                try await TestKit.assertResponse(
                    baseURL, method: "HEAD", path: path,
                    contentType: .text(.plain), expecting: ""
                )
                try await TestKit.assertResponse(
                    baseURL, path: path,
                    contentType: .text(.plain), expecting: response
                )
            }

            try await Assert(path: "a", response: "a")
            try await Assert(path: "b", response: "b")
        }
    }



    // MARK: Auxliliaries

    private typealias TestKit = KvServerTestKit

    private typealias NetworkGroup = TestKit.NetworkGroup

}



#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
#warning("Tests are not available due to URLCredential.init(trust:) or URLCredential.init(identity:certificates:persistence:) are not available")

#endif // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
