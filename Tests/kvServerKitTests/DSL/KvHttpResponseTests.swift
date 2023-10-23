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
//  KvHttpResponseTests.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 10.10.2023.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import XCTest

@testable import kvServerKit



final class KvHttpResponseTests : XCTestCase {

    // MARK: - testRequestBody()

    func testRequestBody() async throws {

        struct RequestBodyServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup(httpMethods: .POST) {
                        KvGroup("echo") {
                            KvHttpResponse.dynamic
                                .requestBody(.data)
                                .content { input in
                                    guard let data: Data = input.requestBody else { return .badRequest }
                                    return .binary { data }
                                }
                        }

                        KvGroup("bytesum") {
                            KvHttpResponse.dynamic
                                .requestBody(.reduce(0 as UInt8, { accumulator, buffer in
                                    buffer.reduce(accumulator, &+)
                                }))
                                .content { input in .string { "0x" + String(input.requestBody, radix: 16, uppercase: true) } }
                        }
                    }
                }
            }

        }

        try await TestKit.withRunningServer(of: RequestBodyServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in
            let payload = Data([ 1, 3, 7, 15, 31, 63, 127, 255 ])
            let sum = payload.reduce(0 as UInt8, &+)

            try await TestKit.assertResponse(baseURL, method: "POST", path: "echo", body: payload,
                                             contentType: .application(.octetStream), expecting: payload)

            try await TestKit.assertResponse(baseURL, method: "POST", path: "bytesum", body: payload,
                                             contentType: .text(.plain), expecting: "0x" + String(sum, radix: 16, uppercase: true))
        }
    }



    // MARK: - testJsonRequestBody()

    func testJsonRequestBody() async throws {

        struct JsonDateServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            static let dateComponents: Set<Calendar.Component> = [ .calendar, .year, .month, .day, .hour, .minute, .second, .nanosecond, .timeZone ]
            let echoDateComponents = Calendar.current.dateComponents(Self.dateComponents, from: Date())

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    if #available(macOS 12.0, *) {
                        KvGroup(httpMethods: .POST) {
                            KvHttpResponse.dynamic
                                .requestBody(.json(of: DateComponents.self))
                                .content {
                                    guard let date = $0.requestBody.date else { return .badRequest }
                                    return .string { ISO8601DateFormatter().string(from: date) }
                                }
                        }
                    }
                    KvGroup(httpMethods: .GET) {
                        KvHttpResponse.static {
                            .json { echoDateComponents }
                        }
                    }
                }
            }

        }

        try await TestKit.withRunningServer(of: JsonDateServer.self, context: { (TestKit.baseURL(for: $0.configuration), $0.echoDateComponents) }) { (baseURL, echoDateComponents) in
            do {
                let date = Date()
                let payload = try JSONEncoder().encode(Calendar.current.dateComponents(JsonDateServer.dateComponents, from: date))
                try await TestKit.assertResponse(baseURL, method: "POST", body: payload, expecting: ISO8601DateFormatter().string(from: date))
            }
            do {
                try await TestKit.assertResponseJSON(baseURL, method: "GET", body: nil, expecting: echoDateComponents)
            }
        }
    }



    // MARK: - testQueryItems()

    /// Tests special kinds of query items. Common query items are tested in other tests.
    func testQueryItems() async throws {

        struct QueryItemServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("boolean") {
                        KvHttpResponse.dynamic
                            .query(.bool("value"))
                            .content { input in .string { "\(input.query)" } }
                    }
                    KvGroup("void") {
                        KvHttpResponse.dynamic
                            .query(.void("value"))
                            .content { _ in .string { "()" } }
                    }
                }
            }

        }

        try await TestKit.withRunningServer(of: QueryItemServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in
            try await TestKit.assertResponse(baseURL, path: "boolean", query: nil, expecting: "false")
            try await TestKit.assertResponse(baseURL, path: "boolean", query: "value", expecting: "true")
            try await TestKit.assertResponse(baseURL, path: "boolean", query: "value=true", expecting: "true")
            try await TestKit.assertResponse(baseURL, path: "boolean", query: "value=false", expecting: "false")

            try await TestKit.assertResponse(baseURL, path: "void", query: "value", expecting: "()")
            try await TestKit.assertResponse(baseURL, path: "void", query: nil, statusCode: .notFound)
            try await TestKit.assertResponse(baseURL, path: "void", query: "value=a", statusCode: .notFound)
        }
    }



    // MARK: - testRequestBodyLimit()

    /// Tests request body limit modifiers in groups and responses.
    func testRequestBodyLimit() async throws {

        struct BodyLimitServer : KvServer {

            static let limits: [UInt] = [ 8, 7, 6, 5 ]
            var limits: [UInt] { Self.limits }

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup(httpMethods: .POST) {
                        KvGroup("no_body") {
                            KvHttpResponse.static { .string { "0" } }
                        }
                        KvGroup("default_limit") {
                            response
                        }

                        KvForEach([ limits[1], nil ]) { limit1 in group(limit: limit1) {
                            KvForEach([ limits[2], nil ]) { limit2 in group(limit: limit2) {
                                KvForEach([ limits[3], nil ]) { limit3 in KvGroup(path("r", limit3)) {
                                    switch limit3 {
                                    case .some(let limit3):
                                        response(limit: limit3)
                                    case .none:
                                        response
                                    }
                                } }
                            } }
                        } }
                    }
                }
            }

            private var response: some KvResponse { response(body: .data) }

            private func response(limit: UInt) -> some KvResponse { response(body: .data.bodyLengthLimit(limit)) }

            private func response(body: KvHttpRequestDataBody) -> some KvResponse {
                KvHttpResponse.dynamic
                    .requestBody(body)
                    .content { input in .string { "\(input.requestBody?.count ?? 0)" } }
            }

            /// - Returns: The response in two groups with given limits.
            @KvResponseGroupBuilder
            private func group<Content>(limit: UInt?, @KvResponseGroupBuilder content: @escaping () -> Content) -> some KvResponseGroup
            where Content : KvResponseGroup {
                let path = self.path("g", limit)

                switch limit {
                case .some(let limit):
                    KvGroup(path, content: content)
                        .httpBodyLengthLimit(limit)
                case .none:
                    KvGroup(path, content: content)
                }
            }

            static func path(_ prefix: String, _ limit: UInt?) -> String { prefix + (limit.map { "\($0)" } ?? "") }

            func path(_ prefix: String, _ limit: UInt?) -> String { Self.path(prefix, limit) }

        }

        try await TestKit.withRunningServer(of: BodyLimitServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(path: String, contentLength: UInt, expectedLimit: UInt) async throws {
                let (statusCode, content): (KvHttpStatus, String)
                = contentLength <= expectedLimit ? (.ok, "\(contentLength)") : (.payloadTooLarge, "")

                try await TestKit.assertResponse(
                    baseURL, method: "POST", path: path, query: nil, body: contentLength > 0 ? Data(count: numericCast(contentLength)) : nil,
                    statusCode: statusCode, contentType: .text(.plain), expecting: content
                )
            }

            func Assert(path: String, expectedLimit: UInt) async throws {
                let limits = [ [ 0, 1 ],
                               Array((BodyLimitServer.limits.min()! - 1)...(BodyLimitServer.limits.max()! + 1)),
                               [ KvHttpRequest.Constants.bodyLengthLimit, KvHttpRequest.Constants.bodyLengthLimit + 1 ]
                ].joined().sorted()

                for limit in limits {
                    try await Assert(path: path, contentLength: limit, expectedLimit: expectedLimit)
                    // Stop after first out-of-limit request due to server drops requests.
                    guard limit <= expectedLimit else { break }
                }
            }

            try await Assert(path: "no_body", expectedLimit: 0)
            try await Assert(path: "default_limit", expectedLimit: KvHttpRequest.Constants.bodyLengthLimit)

            for limit1 in [ BodyLimitServer.limits[1], nil ] {
                for limit2 in [ BodyLimitServer.limits[2], nil ] {
                    for limit3 in [ BodyLimitServer.limits[3], nil ] {
                        let path = "\(BodyLimitServer.path("g", limit1))/\(BodyLimitServer.path("g", limit2))/\(BodyLimitServer.path("r", limit3))"
                        let expectedLimit = [ limit1, limit2, limit3 ].lazy.compactMap({ $0 }).min() ?? KvHttpRequest.Constants.bodyLengthLimit

                        try await Assert(path: path, expectedLimit: expectedLimit)
                    }
                }
            }
        }

    }



    // MARK: - testSubpathResponse()

    func testSubpathResponse() async throws {

        struct SubpathResponseServer : KvServer {

            let configuration = TestKit.insecureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvHttpResponse.static { .string { "-" } }

                    KvGroup("a") {
                        KvHttpResponse.static { .string { "-a" } }

                        KvGroup("b") {
                            KvHttpResponse.static { .string { "-a-b" } }
                        }
                    }

                    KvGroup("c") {
                        KvHttpResponse.dynamic
                            .subpath
                            .content { input in .string { "/" + input.subpath.joined } }
                    }
                    KvGroup("c") {
                        KvHttpResponse.dynamic
                            .query(.required("separator"))
                            .subpath
                            .content { input in
                                let separator = input.query
                                return .string { separator + input.subpath.components.joined(separator: separator) }
                            }
                    }
                }
            }
        }

        try await TestKit.withRunningServer(of: SubpathResponseServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in
            try await TestKit.assertResponse(baseURL, path: "", expecting: "-")
            try await TestKit.assertResponse(baseURL, path: "a", expecting: "-a")
            try await TestKit.assertResponse(baseURL, path: "a/", expecting: "-a")
            try await TestKit.assertResponse(baseURL, path: "a/b", expecting: "-a-b")
            try await TestKit.assertResponse(baseURL, path: "a/b/", expecting: "-a-b")

            try await TestKit.assertResponse(baseURL, path: "a/c", statusCode: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, path: "a/c/", statusCode: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, path: "b", statusCode: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, path: "b/", statusCode: .notFound, expecting: "")

            try await TestKit.assertResponse(baseURL, path: "c", expecting: "/")
            try await TestKit.assertResponse(baseURL, path: "c/", expecting: "/")
            try await TestKit.assertResponse(baseURL, path: "c/a", expecting: "/a")
            try await TestKit.assertResponse(baseURL, path: "c/a/", expecting: "/a")
            try await TestKit.assertResponse(baseURL, path: "///c////a////", expecting: "/a")
            try await TestKit.assertResponse(baseURL, path: "c/a/b/index.html", expecting: "/a/b/index.html")

            do {
                let query: TestKit.Query = .items([ .init(name: "separator", value: "+") ])
                try await TestKit.assertResponse(baseURL, path: "c", query: query, expecting: "+")
                try await TestKit.assertResponse(baseURL, path: "c/", query: query, expecting: "+")
                try await TestKit.assertResponse(baseURL, path: "c/a", query: query, expecting: "+a")
                try await TestKit.assertResponse(baseURL, path: "c/a/", query: query, expecting: "+a")
                try await TestKit.assertResponse(baseURL, path: "///c////a////", query: query, expecting: "+a")
                try await TestKit.assertResponse(baseURL, path: "c/a/b/index.html", query: query, expecting: "+a+b+index.html")
            }
        }
    }



    // MARK: - testSubpathFilter()

    func testSubpathFilter() async throws {

        struct SubpathFilterServer : KvServer {

            let configuration = TestKit.insecureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("profiles") {
                        KvHttpResponse.static { .string { "/" } }

                        KvGroup("top") { KvHttpResponse.static { .string { "/top" } } }

                        KvHttpResponse.dynamic
                            .subpathFilter { $0.components.count == 1 }
                            .subpathFlatMap {
                                UInt($0.components.first!)
                                    .flatMap { Self.profiles[$0] }
                                    .map { .accepted($0) }
                                ?? .rejected
                            }
                            .content { input in .string { input.subpath.uuidString } }
                    }
                    .onHttpIncident { incident, _ in
                        guard incident.defaultStatus == .notFound else { return nil }
                        return .notFound.string { "-" }
                    }
                }
            }

            static let profiles: [UInt : UUID] = [ 1: UUID(), 3: UUID(), 4: UUID() ]

        }

        try await TestKit.withRunningServer(of: SubpathFilterServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in
            try await TestKit.assertResponse(baseURL, path: "profiles", expecting: "/")
            try await TestKit.assertResponse(baseURL, path: "profiles/top", expecting: "/top")

            for (id, value) in SubpathFilterServer.profiles {
                try await TestKit.assertResponse(baseURL, path: "profiles/\(id)", expecting: value.uuidString)
            }

            // Global 404.
            try await TestKit.assertResponse(baseURL, statusCode: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, path: "profile", statusCode: .notFound, expecting: "")
            // Local 404.
            try await TestKit.assertResponse(baseURL, path: "profiles/top_rated", statusCode: .notFound, expecting: "-")
            try await TestKit.assertResponse(baseURL, path: "profiles/0", statusCode: .notFound, expecting: "-")
            try await TestKit.assertResponse(baseURL, path: "profiles/\(SubpathFilterServer.profiles.keys.first!)/summary", statusCode: .notFound, expecting: "-")
        }
    }



    // MARK: - Auxliliaries

    private typealias TestKit = KvServerTestKit

    private typealias NetworkGroup = TestKit.NetworkGroup

}



#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
#warning("Tests are not available due to URLCredential.init(trust:) or URLCredential.init(identity:certificates:persistence:) are not available")

#endif // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
