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

import kvHttpKit



final class KvHttpResponseTests : XCTestCase {

    // MARK: - testRequestBody()

    func testRequestBody() async throws {

        struct RequestBodyServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup(httpMethods: .post) {
                        KvGroup("echo") {
                            KvHttpResponse.with
                                .requestBody(.data)
                                .content { input in
                                    guard let data: Data = input.requestBody else { return .badRequest }
                                    return .binary { data }
                                }
                        }

                        KvGroup("bytesum") {
                            KvHttpResponse.with
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
                        KvGroup(httpMethods: .post) {
                            KvHttpResponse.with
                                .requestBody(.json(of: DateComponents.self))
                                .content {
                                    guard let date = $0.requestBody.date else { return .badRequest }
                                    return .string { ISO8601DateFormatter().string(from: date) }
                                }
                        }
                    }
                    KvGroup(httpMethods: .get) {
                        KvHttpResponse {
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
                        KvHttpResponse.with
                            .query(.bool("value"))
                            .content { input in .string { "\(input.query)" } }
                    }
                    KvGroup("void") {
                        KvHttpResponse.with
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
            try await TestKit.assertResponse(baseURL, path: "void", query: nil, status: .notFound)
            try await TestKit.assertResponse(baseURL, path: "void", query: "value=a", status: .notFound)
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
                    KvGroup(httpMethods: .post) {
                        KvGroup("no_body") {
                            KvHttpResponse { .string { "0" } }
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
                KvHttpResponse.with
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
                let (status, content): (KvHttpStatus, String) = contentLength <= expectedLimit
                ? (.ok, "\(contentLength)") : (.contentTooLarge, "")

                try await TestKit.assertResponse(
                    baseURL, method: "POST", path: path, query: nil, body: contentLength > 0 ? Data(count: numericCast(contentLength)) : nil,
                    status: status, contentType: .text(.plain), expecting: content
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
                    KvHttpResponse { .string { "-" } }

                    KvGroup("a") {
                        KvHttpResponse { .string { "-a" } }

                        KvGroup("b") {
                            KvHttpResponse { .string { "-a-b" } }
                        }
                    }

                    KvGroup("c") {
                        KvHttpResponse.with
                            .subpath
                            .content { input in .string { "/" + input.subpath.joined } }
                    }
                    KvGroup("c") {
                        KvHttpResponse.with
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

            try await TestKit.assertResponse(baseURL, path: "a/c", status: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, path: "a/c/", status: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, path: "b", status: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, path: "b/", status: .notFound, expecting: "")

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
                        KvHttpResponse { .string { "/" } }

                        KvGroup("top") { KvHttpResponse { .string { "/top" } } }

                        KvHttpResponse.with
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
            try await TestKit.assertResponse(baseURL, status: .notFound, expecting: "")
            try await TestKit.assertResponse(baseURL, path: "profile", status: .notFound, expecting: "")
            // Local 404.
            try await TestKit.assertResponse(baseURL, path: "profiles/top_rated", status: .notFound, expecting: "-")
            try await TestKit.assertResponse(baseURL, path: "profiles/0", status: .notFound, expecting: "-")
            try await TestKit.assertResponse(baseURL, path: "profiles/\(SubpathFilterServer.profiles.keys.first!)/summary", status: .notFound, expecting: "-")
        }
    }



    // MARK: - testBodyCallbackResponse()

    func testBodyCallbackResponse() async throws {
        typealias Value = Int

        struct StreamResponseServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvHttpResponse.with
                        .query(.required("from", of: Value.self))
                        .query(.required("through", of: Value.self))
                        .queryFlatMap { $0 <= $1 ? .success($0...$1) : .failure }
                        .content { input in
                            var next = input.query.lowerBound
                            var count = 1 + Value.Magnitude(bitPattern: input.query.upperBound) &- Value.Magnitude(bitPattern: next)

                            return .bodyCallback { targetBuffer in
                                let targetBuffer = targetBuffer.assumingMemoryBound(to: Value.self)
                                let targetCount: Value.Magnitude = numericCast(targetBuffer.count)

                                func Fill(_ count: Value.Magnitude) {
                                    var target = targetBuffer.baseAddress!
                                    let last = next + numericCast(count - 1)

                                    (next ... last).forEach { value in
                                        target.pointee = value
                                        target = target.successor()
                                    }
                                }

                                switch count < targetCount {
                                case true:
                                    guard count > 0 else { return .success(0) }

                                    Fill(count)
                                    defer { count = 0 }
                                    return .success(numericCast(count) * MemoryLayout<Value>.stride)

                                case false:
                                    Fill(targetCount)
                                    defer {
                                        count -= targetCount
                                        next += targetBuffer.count
                                    }
                                    return .success(targetBuffer.count * MemoryLayout<Value>.stride)
                                }
                            }
                        }
                }
            }

        }

        try await TestKit.withRunningServer(of: StreamResponseServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(from: Value, through: Value) async throws {
                let query = TestKit.Query.items([
                    .init(name: "from", value: String(from)),
                    .init(name: "through", value: String(through)),
                ])

                switch from <= through {
                case true:
                    try await TestKit.assertResponse(baseURL, query: query, contentType: nil) { data, request, message in
                        data.withUnsafeBytes { buffer in
                            XCTAssertTrue(buffer.assumingMemoryBound(to: Value.self).elementsEqual(from ... through), message())
                        }
                    }

                case false:
                    try await TestKit.assertResponse(baseURL, query: query, status: .notFound, contentType: .text(.plain)) { data, request, message in
                        XCTAssertTrue(data.isEmpty, "Non-empty data. " + message())
                    }
                }
            }

            try await Assert(from: 0, through: 10)
            try await Assert(from: -128, through: 128)
            try await Assert(from: 16, through: 16)
            try await Assert(from: 8, through: 7)
            try await Assert(from: 8, through: -8)
            try await Assert(from: -(1 << 15), through: (1 << 15))
            try await Assert(from: .max - (1 << 15), through: .max)
        }
    }



    // MARK: - testFileStreamResponse()

    func testFileStreamResponse() async throws {

        struct FileStreamServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            static var url: URL { Bundle.module.url(forResource: "sample", withExtension: "txt")! }

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    let url = Self.url

                    KvGroup(url.lastPathComponent) {
                        KvHttpResponse {
                            guard let stream = InputStream(url: url) else { return .internalServerError }
                            return .binary(stream).contentType(.text(.plain))
                        }
                    }
                }
            }

        }

        try await TestKit.withRunningServer(of: FileStreamServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in
            let fileURL = FileStreamServer.url
            try await TestKit.assertResponse(baseURL, path: fileURL.lastPathComponent, contentType: .text(.plain), expecting: try Data(contentsOf: fileURL))
        }
    }



    // MARK: - testFileResponse()

    func testFileResponse() async throws {

        struct FileServer : KvServer {

            let configuration = TestKit.secureHttpConfiguration()

            static var errorMessage: String { "Error message" }

            static var sampleURL: URL { Bundle.module.url(forResource: "sample", withExtension: "txt")! }
            static var missingURL: URL { sampleURL.appendingPathExtension("missing") }

            var body: some KvResponseRootGroup {
                NetworkGroup(with: configuration) {
                    KvGroup {
                        do {
                            let sampleURL = Self.sampleURL
                            KvGroup(sampleURL.lastPathComponent) {
                                KvHttpResponse { try .file(at: sampleURL) }
                            }
                        }
                        do {
                            let missingURL = Self.missingURL
                            KvGroup(missingURL.lastPathComponent) {
                                KvHttpResponse { try .file(at: missingURL) }
                            }
                        }
                    }
                    .onHttpIncident { incident, _ in
                        guard case KvHttpChannel.RequestIncident.requestProcessingError(let error) = incident else { return nil }
                        switch error {
                        case KvHttpKitError.File.fileDoesNotExist(_), KvHttpKitError.File.unableToFindIndexFile(_):
                            return .status(incident.defaultStatus).string { Self.errorMessage }
                        default:
                            return nil
                        }
                    }
                }
            }

        }

        try await TestKit.withRunningServer(of: FileServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(path: String? = nil, fileName: String? = nil, expected fileURL: URL) async throws {
                let path = (path ?? "") + "/" + (fileName ?? fileURL.lastPathComponent)

                switch try? KvResolvedFileURL(for: fileURL).value {
                case .some(let url):
                    let data = try Data(contentsOf: url)
                    try await TestKit.assertResponse(baseURL, path: path, contentType: nil, expecting: data)
                case .none:
                    try await TestKit.assertResponse(baseURL, path: path, status: .internalServerError, expecting: FileServer.errorMessage)
                }
            }

            try await Assert(expected: FileServer.sampleURL)

            XCTAssertFalse(FileManager.default.fileExists(atPath: FileServer.missingURL.path))
            try await Assert(expected: FileServer.missingURL)
        }
    }



    // MARK: - Auxliliaries

    private typealias TestKit = KvServerTestKit

    private typealias NetworkGroup = TestKit.NetworkGroup

}



#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
#warning("Tests are not available due to URLCredential.init(trust:) or URLCredential.init(identity:certificates:persistence:) are not available")

#endif // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
