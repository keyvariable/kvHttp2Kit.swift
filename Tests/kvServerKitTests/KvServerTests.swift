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

    // MARK: - testMultichannelServer()

    func testMultichannelServer() async throws {

        /// A server provifing single static response at the root receiving requests on several channels.
        struct MultichannelServer : KvServer {

            static let configurations = KvServerTestKit.testConfigurations

            var body: some KvResponseGroup {
                KvForEach(Self.configurations) { configuration in
                    NetworkGroup(with: configuration) {
                        KvHttpResponse.static {
                            .string(Self.greeting(for: configuration))
                        }
                    }
                }
            }

            static func greeting(for configuration: KvHttpChannel.Configuration) -> String {
                "Hello, \(KvServerTestKit.description(of: configuration.http)) client"
            }

        }

        try await Self.withRunningServer(of: MultichannelServer.self) {
            for configuration in MultichannelServer.configurations {
                let baseURL = KvServerTestKit.baseURL(for: configuration)

                try await KvServerTestKit.assertResponse(baseURL, contentType: .text(.plain), expecting: MultichannelServer.greeting(for: configuration))
            }
        }

    }



    // MARK: - testResponseHierarchy()

    func testResponseHierarchy() async throws {

        /// A server providing non-trivial hierarchy of various responses.
        struct ResponseHierarchyServer : KvServer {

            let configuration = KvServerTestKit.insecureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("a") {
                        KvGroup("b") {
                            KvGroup("c") {
                                KvHttpResponse.static { .string("/a/b/c") }
                            }
                        }
                        KvGroup("б/") {
                            KvHttpResponse.static { .string("/a/б") }
                        }
                    }

                    KvGroup("/a/b/d") {
                        KvGroup(httpMethods: .POST) {
                            KvHttpResponse.static { .string("POST /a/b/d") }
                        }
                    }

                    KvGroup("///b/./c/..//b///e///./f/../") {
                        KvHttpResponse.static { .string("/b/./c/../b/e/./f/..") }
                    }

                    KvHttpResponse.static { .string("/") }
                }
            }

        }

        try await Self.withRunningServer(of: ResponseHierarchyServer.self, context: { KvServerTestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert200(path: String, method: String? = nil) async throws {
                try await KvServerTestKit.assertResponse(baseURL, method: method, path: path, contentType: .text(.plain)) { data, request, message in
                    let expectedBody = [method, request.url?.path].compactMap({ $0 }).joined(separator: " ")
                    XCTAssertEqual(String(data: data, encoding: .utf8), expectedBody, message())
                }
            }

            func Assert404(path: String, method: String? = nil) async throws {
                try await KvServerTestKit.assertResponse(baseURL, method: method, path: path, statusCode: .notFound, contentType: .text(.plain)) { data, request, message in
                    XCTAssertTrue(data.isEmpty, message())
                }
            }

            try await Assert200(path: "/")

            do {
                let variants = [ "a", "b", "c" ]
                let okPath = variants.joined(separator: "/")

                for first in variants {
                    for second in variants {
                        for third in variants {
                            let path = "\(first)/\(second)/\(third)"

                            switch path {
                            case okPath:
                                try await Assert200(path: path)
                            default:
                                try await Assert404(path: path)
                            }
                        }
                    }
                }

                try await Assert200(path: okPath + "/")
            }

            try await Assert404(path: "a")
            try await Assert404(path: "a/b")
            try await Assert404(path: "a/b/c/d")

            try await Assert200(path: "a/б")

            try await Assert404(path: "a/в")
            try await Assert404(path: "a/с")

            try await Assert200(path: "b/./c/../b/e/./f/..")

            try await Assert404(path: "b")
            try await Assert404(path: "b/c")
            try await Assert404(path: "b/b")
            try await Assert404(path: "b/b/e/f")

            try await Assert200(path: "a/b/d", method: "POST")
            try await Assert404(path: "a/b/d", method: "GET")
            try await Assert404(path: "a/b/d", method: "PUT")
        }
    }



    // MARK: - testResponseGroupModifiers()

    func testResponseGroupModifiers() async throws {

        struct ModifiedResponseGroupServer : KvServer {

            let configuration = KvServerTestKit.insecureHttpConfiguration()

            static var greeting: String { "Welcome!" }

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("a") {
                        KvGroup {
                            KvHttpResponse.static { .string(Self.greeting) }
                        }
                        .httpMethods(.DELETE)
                        .httpMethods(.GET, .PUT)
                        .path("/c/")
                        .path("d///e")
                    }
                    .path("//b")
                }
            }

        }

        try await Self.withRunningServer(of: ModifiedResponseGroupServer.self, context: { KvServerTestKit.baseURL(for: $0.configuration) }) { baseURL in
            try await KvServerTestKit.assertResponse(baseURL, path: "a/b/c/d/e", contentType: .text(.plain), expecting: ModifiedResponseGroupServer.greeting)
        }
    }



    // MARK: - testQueryOverloads()

    func testQueryOverloads() async throws {

        struct OverloadedQueryServer : KvServer {

            let configuration = KvServerTestKit.insecureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("entire") {
                        KvGroup("single") {
                            echoResponse(strict: false)
                        }
                        KvGroup("multiple") {
                            echoResponse()
                            namesResponse
                        }
                        KvGroup("ambiguous") {
                            echoResponse(strict: false)
                            namesResponse
                        }
                    }
                    KvGroup("serial") {
                        KvGroup("single") {
                            requiredStringResponse
                        }
                        KvGroup("multiple") {
                            serialResponses
                        }
                        KvGroup("with_empty") {
                            voidResponse
                            requiredStringResponse
                        }
                        KvGroup("ambiguous") {
                            voidResponse
                            optionalIntResponse
                        }
                    }
                    KvGroup("mixed") {          // Custom + empty as serial
                        KvGroup("empty") {
                            voidResponse
                            echoResponse()
                            namesResponse
                        }
                        KvGroup("serial") {     // Custom + serial
                            echoResponse()
                            serialResponses
                        }
                        KvGroup("all") {        // Custom + both serial and empty as serial
                            voidResponse
                            echoResponse()
                            serialResponses
                        }
                        KvGroup("ambiguous") {  // Ambiguous raw and structured responses.
                            echoResponse(strict: false)
                            requiredStringResponse
                        }
                    }
                }
            }

            /// Empty query response.
            private var voidResponse: some KvResponse {
                KvHttpResponse.static { .string("()") }
            }

            @KvResponseGroupBuilder
            private var serialResponses: some KvResponseGroup {
                rangeResponses
                abcAmbiguousResponses
            }

            private var optionalIntResponse: some KvResponse {
                KvHttpResponse.dynamic
                    .query(.optional("int", of: Int.self))
                    .content {
                        .string("\($0.query.map(String.init(_:)) ?? "nil") as Int?")
                    }
            }

            private var requiredStringResponse: some KvResponse {
                KvHttpResponse.dynamic
                    .query(.required("string"))
                    .content { .string("\"\($0.query)\"") }
            }

            /// Produces value of single query item if it's name is `echo`.
            private func echoResponse(strict: Bool = true) -> some KvResponse {
                let r = {
                    switch strict {
                    case false:
                        return KvHttpResponse.dynamic
                            .queryMap { $0?.first.flatMap { $0.name == "echo" ? ($0.value ?? "") : nil } }
                    case true:
                        return KvHttpResponse.dynamic
                            .queryFlatMap { query -> QueryResult<String?> in
                                guard let first = query?.first,
                                      query!.count == 1,
                                      first.name == "echo"
                                else { return .failure }
                                return .success(first.value ?? "")
                            }
                    }
                }()

                return r.content { .string($0.query.map { "\"\($0)\"" } ?? "nil") }
            }

            /// Produces comma-separated list of query item names whether there are 2+ items.
            private var namesResponse: some KvResponse {
                KvHttpResponse.dynamic
                    .queryFlatMap { query -> QueryResult<String> in
                        guard let query = query, query.count > 1 else { return .failure }
                        return .success(query.lazy.map({ $0.name }).joined(separator: ","))
                    }
                    .content { .string($0.query) }
            }

            /// Group of unambiguous responses.
            @KvResponseGroupBuilder
            private var rangeResponses: some KvResponseGroup {
                KvHttpResponse.dynamic
                    .query(.required("from", of: Float.self))
                    .query(.optional("to", of: Float.self))
                    .content {
                        switch $0.query {
                        case (let from, .none):
                            return .string("\(from) ...")
                        case (let from, .some(let to)):
                            return .string("\(from) ..< \(to)")
                        }
                    }

                KvHttpResponse.dynamic
                    .query(.required("to", of: Float.self))
                    .content {
                        .string("..< \($0.query)")
                    }

                KvHttpResponse.dynamic
                    .query(.optional("from", of: Float.self))
                    .query(.required("through", of: Float.self))
                    .content {
                        switch $0.query {
                        case (.none, let through):
                            return .string("... \(through)")
                        case (.some(let from), let through):
                            return .string("\(from) ... \(through)")
                        }
                    }
            }

            // Group of ambiguous responses.
            @KvResponseGroupBuilder
            private var abcAmbiguousResponses: some KvResponseGroup {
                KvHttpResponse.dynamic
                    .query(.required("a"))
                    .query(.required("b"))
                    .content {
                        let (a, b) = $0.query
                        return .string("a: \"\(a)\", b: \"\(b)\"")
                    }

                KvHttpResponse.dynamic
                    .query(.required("a"))
                    .query(.required("c"))
                    .content {
                        let (a, c) = $0.query
                        return .string("a: \"\(a)\", c: \"\(c)\"")
                    }
            }

        }

        try await Self.withRunningServer(of: OverloadedQueryServer.self, context: { KvServerTestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert200(path: String, query: KvServerTestKit.Query?, expectedBody: String) async throws {
                try await KvServerTestKit.assertResponse(baseURL, path: path, query: query, statusCode: .ok, expecting: expectedBody)
            }
            func Assert400(path: String, query: KvServerTestKit.Query?) async throws {
                try await KvServerTestKit.assertResponse(baseURL, path: path, query: query, statusCode: .badRequest, expecting: "")
            }
            func Assert404(path: String, query: KvServerTestKit.Query?) async throws {
                try await KvServerTestKit.assertResponse(baseURL, path: path, query: query, statusCode: .notFound, expecting: "")
            }

            func AssertVoid(path: String) async throws {
                try await Assert200(path: path, query: nil, expectedBody: "()")
            }

            func AssertEcho(path: String) async throws {
                try await Assert200(path: path, query: "echo=Hello!", expectedBody: "\"Hello!\"")
                try await Assert200(path: path, query: "echo", expectedBody: "\"\"")
            }

            func AssertNames(path: String) async throws {
                try await Assert200(path: path, query: "a&a=a&b=2&cde=3&a=1", expectedBody: "a,a,b,cde,a")
            }

            func AssertOptionalInt(path: String) async throws {
                try await Assert200(path: path, query: nil, expectedBody: "nil as Int?")
                try await Assert200(path: path, query: "int=14", expectedBody: "14 as Int?")
            }

            func AssertRequiredString(path: String) async throws {
                try await Assert200(path: path, query: "string=Hello!", expectedBody: "\"Hello!\"")
                try await Assert200(path: path, query: "string", expectedBody: "\"\"")
            }

            func AssertRange(path: String) async throws {
                try await Assert200(path: path, query: "from=1.1", expectedBody: "1.1 ...")
                try await Assert200(path: path, query: "from=2.2&to=3.3", expectedBody: "2.2 ..< 3.3")
                try await Assert200(path: path, query: "from=4.4&through=5.5", expectedBody: "4.4 ... 5.5")
                try await Assert200(path: path, query: "to=6.6", expectedBody: "..< 6.6")
                try await Assert200(path: path, query: "through=7.7", expectedBody: "... 7.7")
            }

            func AssertABC(path: String) async throws {
                try await Assert200(path: path, query: "a=1&b=2", expectedBody: "a: \"1\", b: \"2\"")
                try await Assert200(path: path, query: "a=3&c=4", expectedBody: "a: \"3\", c: \"4\"")
                try await Assert404(path: path, query: "a=5")
                try await Assert404(path: path, query: "a=6&b=7&c=8")
            }

            try await AssertEcho(path: "entire/single")
            try await Assert200(path: "entire/single", query: "echo_", expectedBody: "nil")
            try await Assert200(path: "entire/single", query: nil, expectedBody: "nil")

            try await AssertEcho(path: "entire/multiple")
            try await AssertNames(path: "entire/multiple")

            try await AssertEcho(path: "entire/ambiguous")
            try await Assert200(path: "entire/ambiguous", query: "echo_", expectedBody: "nil")
            try await Assert200(path: "entire/ambiguous", query: nil, expectedBody: "nil")
            try await Assert400(path: "entire/ambiguous", query: "echo=ambiguous&int=3")
            try await Assert400(path: "entire/ambiguous", query: "a&b=2")

            try await AssertRequiredString(path: "serial/single")

            try await AssertRange(path: "serial/multiple")
            try await AssertABC(path: "serial/multiple")

            try await AssertVoid(path: "serial/with_empty")
            try await AssertRequiredString(path: "serial/with_empty")

            try await Assert400(path: "serial/ambiguous", query: nil)
            try await Assert200(path: "serial/ambiguous", query: "int=02", expectedBody: "2 as Int?")

            try await AssertVoid(path: "mixed/empty")
            try await AssertEcho(path: "mixed/empty")
            try await AssertNames(path: "mixed/empty")

            try await AssertEcho(path: "mixed/serial")
            try await AssertRange(path: "mixed/serial")
            try await AssertABC(path: "mixed/serial")

            try await AssertVoid(path: "mixed/all")
            try await AssertEcho(path: "mixed/all")
            try await AssertRange(path: "mixed/all")
            try await AssertABC(path: "mixed/all")

            try await AssertEcho(path: "mixed/ambiguous")
            try await Assert400(path: "mixed/ambiguous", query: "string=Ambiguous!")
        }
    }



    // MARK: - testCascadeNetworkModifiers()

    func testCascadeNetworkModifiers() async throws {

        struct CascadeNetworkModifierServer : KvServer {

            let configuration = KvServerTestKit.insecureHttpConfiguration()

            static let greeting = "cascade"

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    httpsServer
                }
            }

            private var httpsServer: some KvResponseGroup {
                NetworkGroup(with: KvServerTestKit.secureHttpConfiguration()) {
                    KvHttpResponse.static { .string(Self.greeting) }
                }
            }

        }

        try await Self.withRunningServer(of: CascadeNetworkModifierServer.self, context: { KvServerTestKit.baseURL(for: $0.configuration) }) { baseURL in
            try await KvServerTestKit.assertResponse(baseURL, contentType: .text(.plain), expecting: CascadeNetworkModifierServer.greeting)
        }
    }



    // MARK: - testStreamResponse()

    func testStreamResponse() async throws {
        typealias Value = Int

        struct StreamResponseServer : KvServer {

            let configuration = KvServerTestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvHttpResponse.dynamic
                        .query(.required("from", of: Value.self))
                        .query(.required("through", of: Value.self))
                        .queryFlatMap { $0 <= $1 ? .success($0...$1) : .failure }
                        .content { context in
                            var next = context.query.lowerBound
                            var count = 1 + Value.Magnitude(bitPattern: context.query.upperBound) &- Value.Magnitude(bitPattern: next)

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

        try await Self.withRunningServer(of: StreamResponseServer.self, context: { KvServerTestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(from: Value, through: Value) async throws {
                let query = KvServerTestKit.Query.items([
                    .init(name: "from", value: String(from)),
                    .init(name: "through", value: String(through)),
                ])

                switch from <= through {
                case true:
                    try await KvServerTestKit.assertResponse(baseURL, query: query, contentType: .application(.octetStream)) { data, request, message in
                        data.withUnsafeBytes { buffer in
                            XCTAssertTrue(buffer.assumingMemoryBound(to: Value.self).elementsEqual(from ... through), message())
                        }
                    }

                case false:
                    try await KvServerTestKit.assertResponse(baseURL, query: query, statusCode: .notFound, contentType: .text(.plain)) { data, request, message in
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



    // MARK: - testRequestBody()

    func testRequestBody() async throws {

        struct RequestBodyServer : KvServer {

            let configuration = KvServerTestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("echo") {
                        KvHttpResponse.dynamic
                            .requestBody(.data)
                            .content { context in
                                guard let data: Data = context.requestBody else { return .badRequest }
                                return .binary(data)
                            }
                    }

                    KvGroup("bytesum") {
                        KvHttpResponse.dynamic
                            .requestBody(.reduce(0 as UInt8, { accumulator, buffer in
                                buffer.reduce(accumulator, &+)
                            }))
                            .content {
                                .string("0x" + String($0.requestBody, radix: 16, uppercase: true))
                            }
                    }
                }
                .httpMethods(.POST)
            }

        }

        try await Self.withRunningServer(of: RequestBodyServer.self, context: { KvServerTestKit.baseURL(for: $0.configuration) }) { baseURL in
            let payload = Data([ 1, 3, 7, 15, 31, 63, 127, 255 ])
            let sum = payload.reduce(0 as UInt8, &+)

            try await KvServerTestKit.assertResponse(baseURL, method: "POST", path: "echo", body: payload,
                                                     contentType: .application(.octetStream), expecting: payload)

            try await KvServerTestKit.assertResponse(baseURL, method: "POST", path: "bytesum", body: payload,
                                                     contentType: .text(.plain), expecting: "0x" + String(sum, radix: 16, uppercase: true))
        }
    }



    // MARK: - testJSON()

    func testJsonDate() async throws {

        struct JsonDateServer : KvServer {

            let configuration = KvServerTestKit.secureHttpConfiguration()

            static let dateComponents: Set<Calendar.Component> = [ .calendar, .year, .month, .day, .hour, .minute, .second, .nanosecond, .timeZone ]
            let echoDateComponents = Calendar.current.dateComponents(Self.dateComponents, from: Date())

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    if #available(macOS 12.0, *) {
                        KvGroup(httpMethods: .POST) {
                            KvHttpResponse.dynamic
                                .requestBody(.json(of: DateComponents.self))
                                .content {
                                    guard let date = $0.requestBody.date else { return .badRequest }
                                    return .string(ISO8601DateFormatter().string(from: date))
                                }
                        }
                    }
                    KvGroup(httpMethods: .GET) {
                        KvHttpResponse.static {
                            do { return try .json(echoDateComponents) }
                            catch { return .internalServerError.string("\(error)") }
                        }
                    }
                }
            }

        }

        try await Self.withRunningServer(of: JsonDateServer.self, context: { (KvServerTestKit.baseURL(for: $0.configuration), $0.echoDateComponents) }) { (baseURL, echoDateComponents) in
            do {
                let date = Date()
                let payload = try JSONEncoder().encode(Calendar.current.dateComponents(JsonDateServer.dateComponents, from: date))
                try await KvServerTestKit.assertResponse(baseURL, method: "POST", body: payload, expecting: ISO8601DateFormatter().string(from: date))
            }
            do {
                try await KvServerTestKit.assertResponseJSON(baseURL, method: "GET", body: nil, expecting: echoDateComponents)
            }
        }
    }



    // MARK: - testFileStreamResponse()

    func testFileStreamResponse() async throws {

        struct FileStreamServer : KvServer {

            let configuration = KvServerTestKit.secureHttpConfiguration()

            static var url: URL { Bundle.module.url(forResource: "sample", withExtension: "txt", subdirectory: "Resources")! }

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    let url = Self.url

                    KvGroup(url.lastPathComponent) {
                        KvHttpResponse.static {
                            guard let stream = InputStream(url: url) else { return .internalServerError }
                            return .binary(stream).contentType(.text(.plain))
                        }
                    }
                }
            }

        }

        try await Self.withRunningServer(of: FileStreamServer.self, context: { KvServerTestKit.baseURL(for: $0.configuration) }) { baseURL in
            let fileURL = FileStreamServer.url
            try await KvServerTestKit.assertResponse(baseURL, path: fileURL.lastPathComponent, contentType: .text(.plain), expecting: try Data(contentsOf: fileURL))
        }
    }



    // MARK: - testQueryItems()

    /// Tests special kinds of query items. Common query items are tested in other tests.
    func testQueryItems() async throws {

        struct QueryItemServer : KvServer {

            let configuration = KvServerTestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("boolean") {
                        KvHttpResponse.dynamic
                            .query(.bool("value"))
                            .content {
                                .string("\($0.query)")
                            }
                    }
                    KvGroup("void") {
                        KvHttpResponse.dynamic
                            .query(.void("value"))
                            .content { _ in
                                    .string("()")
                            }
                    }
                }
            }

        }

        try await Self.withRunningServer(of: QueryItemServer.self, context: { KvServerTestKit.baseURL(for: $0.configuration) }) { baseURL in
            try await KvServerTestKit.assertResponse(baseURL, path: "boolean", query: nil, expecting: "false")
            try await KvServerTestKit.assertResponse(baseURL, path: "boolean", query: "value", expecting: "true")
            try await KvServerTestKit.assertResponse(baseURL, path: "boolean", query: "value=true", expecting: "true")
            try await KvServerTestKit.assertResponse(baseURL, path: "boolean", query: "value=false", expecting: "false")

            try await KvServerTestKit.assertResponse(baseURL, path: "void", query: "value", expecting: "()")
            try await KvServerTestKit.assertResponse(baseURL, path: "void", query: nil, statusCode: .notFound)
            try await KvServerTestKit.assertResponse(baseURL, path: "void", query: "value=a", statusCode: .notFound)
        }
    }



    // MARK: - testBodyLimit()

    /// Tests request body limit modifiers in groups and responses.
    func testBodyLimit() async throws {

        struct BodyLimitServer : KvServer {

            static let limits: [UInt] = [ 8, 7, 6, 5 ]
            var limits: [UInt] { Self.limits }

            let configuration = KvServerTestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvGroup("no_body") {
                        KvHttpResponse.static { .string("0") }
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
                .httpMethods(.POST)
            }

            private var response: some KvResponse { response(body: .data) }

            private func response(limit: UInt) -> some KvResponse { response(body: .data.bodyLengthLimit(limit)) }

            private func response(body: KvHttpRequestDataBody) -> some KvResponse {
                KvHttpResponse.dynamic
                    .requestBody(body)
                    .content {
                        .string("\($0.requestBody?.count ?? 0)")
                    }
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

        try await Self.withRunningServer(of: BodyLimitServer.self, context: { KvServerTestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(_ urlSession: URLSession, path: String, contentLength: UInt, expectedLimit: UInt) async throws {
                let (statusCode, content): (KvHttpResponseProvider.Status, String)
                = contentLength <= expectedLimit ? (.ok, "\(contentLength)") : (.payloadTooLarge, "")

                try await KvServerTestKit.assertResponse(
                    urlSession: urlSession,
                    baseURL, method: "POST", path: path, query: nil, body: contentLength > 0 ? Data(count: numericCast(contentLength)) : nil,
                    statusCode: statusCode, contentType: .text(.plain), expecting: content
                )
            }

            func Assert(path: String, expectedLimit: UInt) async throws {
                // URL sessions are used to prevent reponses after body limit incidents to be discarded.
                let urlSession = URLSession(configuration: .ephemeral)

                let limits = [ [ 0, 1 ],
                               Array((BodyLimitServer.limits.min()! - 1)...(BodyLimitServer.limits.max()! + 1)),
                               [ KvHttpRequest.Constants.bodyLengthLimit, KvHttpRequest.Constants.bodyLengthLimit + 1 ]
                ].joined().sorted()

                for limit in limits {
                    try await Assert(urlSession, path: path, contentLength: limit, expectedLimit: expectedLimit)
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

}



// MARK: - Auxiliaries

extension KvServerTests {

    private static func withRunningServer<S, T>(of serverType: S.Type, context contextBlock: (S) -> T, body: (T) async throws -> Void) async throws
    where S : KvServer
    {
        let context: T
        let token: KvServerToken
        do {
            let server = serverType.init()

            context = contextBlock(server)
            token = try server.start()
        }


        try token.waitWhileStarting().get()

        try await body(context)
    }


    private static func withRunningServer<S>(of serverType: S.Type, body: () async throws -> Void) async throws
    where S : KvServer
    {
        try await withRunningServer(of: S.self, context: { _ in }, body: body)
    }

}



// MARK: .NetworkGroup

extension KvServerTests {

    /// Applies given configuration to given content.
    fileprivate struct NetworkGroup<Configurations, Content> : KvResponseGroup
    where Configurations : Sequence, Configurations.Element == KvHttpChannel.Configuration,
          Content : KvResponseGroup
    {

        let configurations: Configurations

        @KvResponseGroupBuilder
        let content: () -> Content


        init(with configurations: Configurations, @KvResponseGroupBuilder content: @escaping () -> Content) {
            self.configurations = configurations
            self.content = content
        }


        var body: some KvResponseGroup {
            KvGroup(httpEndpoints: configurations.lazy.map { ($0.endpoint, $0.http) },
                    content: content)
        }

    }

}



// MARK: .NetworkGroup + CollectionOfOne

extension KvServerTests.NetworkGroup where Configurations == CollectionOfOne<KvHttpChannel.Configuration> {

    init(with configuration: KvHttpChannel.Configuration, @KvResponseGroupBuilder content: @escaping () -> Content) {
        self.init(with: CollectionOfOne(configuration), content: content)
    }

}



#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
#warning("Tests are not available due to URLCredential.init(trust:) or URLCredential.init(identity:certificates:persistence:) are not available")

#endif // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
