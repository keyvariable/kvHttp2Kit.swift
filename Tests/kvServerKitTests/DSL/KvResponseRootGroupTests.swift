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
//  KvResponseRootGroupTests.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 23.10.2023.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import XCTest

@testable import kvServerKit



final class KvResponseRootGroupTests: XCTestCase {

    // MARK: - testHostAliases()

    func testHostAliases() async throws {

        struct HostAliasServer : KvServer {

            static let host = "localhost"
            static let hostAlias = "[::1]"

            static let uuid = UUID()

            let configuration = TestKit.insecureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup(hosts: Self.host, hostAliases: Self.hostAlias) {
                        KvHttpResponse.dynamic
                            .subpath
                            .content { input in .string { Self.host + "/" + input.subpath.joined  } }
                    }

                    KvGroup(hosts: Self.hostAlias) {
                        KvGroup("uuid") {
                            KvHttpResponse.static { .string { Self.uuid.uuidString } }
                        }
                    }
                }
            }

        }

        try await TestKit.withRunningServer(of: HostAliasServer.self, context: { $0.configuration }) { configuration in

            func Assert(host: String, path: String?, expecting: String) async throws {
                let baseURL = TestKit.baseURL(for: configuration, host: host)
                try await TestKit.assertResponse(baseURL, path: path, expecting: expecting)
            }

            let host = HostAliasServer.host

            try await Assert(host: host, path: "", expecting: host + "/")
            try await Assert(host: host, path: "a", expecting: host + "/a")
            try await Assert(host: host, path: "uuid", expecting: host + "/uuid")

            do {
                let alias = HostAliasServer.hostAlias

                try await Assert(host: alias, path: "", expecting: host + "/")
                try await Assert(host: alias, path: "a", expecting: host + "/a")
                try await Assert(host: alias, path: "uuid", expecting: HostAliasServer.uuid.uuidString)
            }
        }
    }



    // MARK: Auxliliaries

    private typealias TestKit = KvServerTestKit

    private typealias NetworkGroup = TestKit.NetworkGroup

}



#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
#warning("Tests are not available due to URLCredential.init(trust:) or URLCredential.init(identity:certificates:persistence:) are not available")

#endif // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
