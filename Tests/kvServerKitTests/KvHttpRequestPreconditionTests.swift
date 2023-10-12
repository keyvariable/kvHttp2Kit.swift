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
//  KvHttpRequestPreconditionTests.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 12.10.2023.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import XCTest

@testable import kvServerKit

import NIOHTTP1



final class KvHttpRequestPreconditionTests : XCTestCase {

    // MARK: - testEntityTagPreconditionParser()

    func testEntityTagPreconditionParser() async throws {

        func Assert(value: String, options: KvHttpResponseProvider.EntityTag.Options = [ ], input: String, expected: Result<Bool, KvHttpRequestPreconditions.EntityTagParser.ParseError>) {
            XCTAssertEqual(KvHttpRequestPreconditions.EntityTagParser.is(.init(safeValue: value, options: options), in: input),
                           expected,
                           "value: \(value); options: \(options); input: \(input)")
        }

        Assert(value: "", input: "", expected: .success(false))
        Assert(value: "", input: "\"\"", expected: .success(true))
        Assert(value: "", input: "\"\", \"abc\"", expected: .success(true))
        Assert(value: "", input: "\"abc\", \"\", \"\"", expected: .success(true))
        Assert(value: "", input: "\"\", \"abc\", W/\"\"", expected: .success(true))
        Assert(value: "", input: "W/\"\", \"abc\", \"\"", expected: .success(true))
        Assert(value: "", input: "W/\"\", \"abc\", W/\"\"", expected: .success(false))
        Assert(value: "", input: "\"abc\", W/\"\", W/\"\"", expected: .success(false))
        Assert(value: "", input: "*", expected: .success(true))
        Assert(value: "", input: "  *  ", expected: .success(true))

        Assert(value: "abc", input: "", expected: .success(false))
        Assert(value: "abc", input: "\"\"", expected: .success(false))
        Assert(value: "abc", input: "\"abc\"", expected: .success(true))
        Assert(value: "abc", input: "\"aabc\"", expected: .success(false))
        Assert(value: "abc", input: "\" abc\"", expected: .success(false))
        Assert(value: "abc", input: "\"abc \"", expected: .success(false))
        Assert(value: "abc", input: "\"abcc\"", expected: .success(false))
        Assert(value: "abc", input: "  \"abc\"  ", expected: .success(true))
        Assert(value: "abc", input: "  \"a\"  , \"abc\",W/\"ab\"  ", expected: .success(true))
        Assert(value: "abc", input: "  W/\"a\"  , W/\"abc\",W/\"ab\"  ", expected: .success(false))
        Assert(value: "abc", input: "*", expected: .success(true))
        Assert(value: "abc", input: "  *  ", expected: .success(true))

        Assert(value: "abc", options: .weak, input: "", expected: .success(false))
        Assert(value: "abc", options: .weak, input: "\"\"", expected: .success(false))
        Assert(value: "abc", options: .weak, input: "\"abc\"", expected: .success(false))
        Assert(value: "abc", options: .weak, input: "  W/\"abc\"", expected: .success(true))
        Assert(value: "abc", options: .weak, input: "\"aabc\"", expected: .success(false))
        Assert(value: "abc", options: .weak, input: "\"abcc\"", expected: .success(false))
        Assert(value: "abc", options: .weak, input: "  \"a\"  , \"abc\",W/\"ab\"  ", expected: .success(false))
        Assert(value: "abc", options: .weak, input: "  W/\"a\"  , W/\"abc\",W/\"ab\"  ", expected: .success(true))
        Assert(value: "abc", options: .weak, input: "*", expected: .success(true))
        Assert(value: "abc", options: .weak, input: "  *  ", expected: .success(true))

        Assert(value: "xx", input: "   ", expected: .success(false))
        Assert(value: "xx", input: "xx", expected: .failure(.unexpectedLeadingItemCharacter("x")))
        Assert(value: "xx", input: "\"xx", expected: .failure(.unexpectedEnd))
        Assert(value: "xx", input: "\"xx  ", expected: .failure(.unexpectedEnd))
        Assert(value: "xx", input: "xx\"", expected: .failure(.unexpectedLeadingItemCharacter("x")))
        Assert(value: "xx", input: "S/\"xx\"", expected: .failure(.unexpectedLeadingItemCharacter("S")))
        Assert(value: "xx", input: "w/\"xx\"", expected: .failure(.unexpectedLeadingItemCharacter("w")))
        Assert(value: "xx", input: "W\"xx\"", expected: .failure(.expectedSlash("\"")))
        Assert(value: "xx", input: "W/xx", expected: .failure(.expectedLeadingQuote("x")))
        Assert(value: "xx", input: "\"xx\" \"yy\"", expected: .failure(.expectedComma("\"")))
        Assert(value: "xx", input: "\"xx\" yy", expected: .failure(.expectedComma("y")))
        Assert(value: "xx", input: "\"xx\",", expected: .failure(.unexpectedEnd))
        Assert(value: "xx", input: "\"xx\",   ", expected: .failure(.unexpectedEnd))
        Assert(value: "xx", input: "\"xx\"  ,", expected: .failure(.unexpectedEnd))
        Assert(value: "xx", input: "  \"xx\",  ", expected: .failure(.unexpectedEnd))
        Assert(value: "xx", input: "*, \"xx\"", expected: .failure(.invalidWildcard(",")))
        Assert(value: "xx", input: "\"xx\", * ", expected: .failure(.unexpectedLeadingItemCharacter("*")))

        Assert(value: "xx", options: .weak, input: "W /\"xx\"", expected: .failure(.expectedSlash(" ")))
        Assert(value: "xx", options: .weak, input: "W/ \"xx\"", expected: .failure(.expectedLeadingQuote(" ")))
        Assert(value: "xx", options: .weak, input: "W/xx", expected: .failure(.expectedLeadingQuote("x")))
        Assert(value: "xx", options: .weak, input: "W/ xx", expected: .failure(.expectedLeadingQuote(" ")))
        Assert(value: "xx", options: .weak, input: "W/*", expected: .failure(.expectedLeadingQuote("*")))

        Assert(value: "*", input: "", expected: .success(false))
        Assert(value: "*", input: "*", expected: .success(true))
        Assert(value: "*", input: "\"*\"", expected: .success(true))
        Assert(value: "*", input: "   \"*\"   ", expected: .success(true))
        Assert(value: "*", input: "\"*\", \"a\"", expected: .success(true))
        Assert(value: "*", input: "\"a\", \"*\"", expected: .success(true))
        Assert(value: "*", input: "\"*\", *", expected: .failure(.unexpectedLeadingItemCharacter("*")))
        Assert(value: "*", input: "*, \"*\"", expected: .failure(.invalidWildcard(",")))
        Assert(value: "*", input: "* \"*\"", expected: .failure(.invalidWildcard("\"")))
    }



    // MARK: - testETagPrecondition()

    func testETagPrecondition() async throws {
        typealias ETag = KvHttpResponseProvider.EntityTag

        struct ETagServer : KvServer {

            static let etag = (strong: ETag("s")!, weak: ETag("w", options: .weak)!)

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvHttpResponse.static { .string { "-" } }

                    KvGroup("s") { KvHttpResponse.static { .string({ "s" }).entityTag(Self.etag.strong) } }
                    KvGroup("w") { KvHttpResponse.static { .string({ "w" }).entityTag(Self.etag.weak) } }
                }
            }

        }

        try await TestKit.withRunningServer(of: ETagServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(path: String? = nil, header: (name: String, value: String)?, statusCode: HTTPResponseStatus, content: String)  async throws {
                let urlSession = URLSession(configuration: .ephemeral)
                try await TestKit.assertResponse(
                    urlSession: urlSession, baseURL, path: path,
                    onRequest: header.map { (name, value) in { $0.setValue(value, forHTTPHeaderField: name) } },
                    statusCode: statusCode, expecting: content
                )
            }

            let etag = ETagServer.etag

            try await Assert(header: nil, statusCode: .ok, content: "-")

            try await Assert(header: ("If-Match", ""), statusCode: .preconditionFailed, content: "")
            try await Assert(header: ("If-Match", "*"), statusCode: .preconditionFailed, content: "")
            try await Assert(header: ("If-Match", "\(etag.strong.httpRepresentation), \(etag.weak.httpRepresentation)"), statusCode: .preconditionFailed, content: "")
            try await Assert(header: ("If-Match", "\"a\", *"), statusCode: .ok, content: "-")

            try await Assert(header: ("If-None-Match", ""), statusCode: .ok, content: "-")
            try await Assert(header: ("If-None-Match", "*"), statusCode: .ok, content: "-")
            try await Assert(header: ("If-None-Match", "\(etag.strong.httpRepresentation), \(etag.weak.httpRepresentation)"), statusCode: .ok, content: "-")
            try await Assert(header: ("If-None-Match", "\"a\", *"), statusCode: .ok, content: "-")

            try await Assert(path: "s", header: ("If-Match", ""), statusCode: .preconditionFailed, content: "")
            try await Assert(path: "s", header: ("If-Match", "*"), statusCode: .ok, content: "s")
            try await Assert(path: "s", header: ("If-Match", "\(etag.strong.httpRepresentation)"), statusCode: .ok, content: "s")
            try await Assert(path: "s", header: ("If-Match", "\(ETag(safeValue: etag.strong.value, options: .weak).httpRepresentation)"), statusCode: .preconditionFailed, content: "")
            try await Assert(path: "s", header: ("If-Match", "\(etag.strong.httpRepresentation), \(etag.weak.httpRepresentation)"), statusCode: .ok, content: "s")
            try await Assert(path: "s", header: ("If-Match", "\"a\", *"), statusCode: .ok, content: "s")

            try await Assert(path: "s", header: ("If-None-Match", ""), statusCode: .ok, content: "s")
            try await Assert(path: "s", header: ("If-None-Match", "*"), statusCode: .notModified, content: "")
            try await Assert(path: "s", header: ("If-None-Match", "\(etag.strong.httpRepresentation)"), statusCode: .notModified, content: "")
            try await Assert(path: "s", header: ("If-None-Match", "\(ETag(safeValue: etag.strong.value, options: .weak).httpRepresentation)"), statusCode: .ok, content: "s")
            try await Assert(path: "s", header: ("If-None-Match", "\(etag.strong.httpRepresentation), \(etag.weak.httpRepresentation)"), statusCode: .notModified, content: "")
            try await Assert(path: "s", header: ("If-None-Match", "\"a\", *"), statusCode: .ok, content: "s")

            try await Assert(path: "w", header: ("If-Match", ""), statusCode: .preconditionFailed, content: "")
            try await Assert(path: "w", header: ("If-Match", "*"), statusCode: .preconditionFailed, content: "")
            try await Assert(path: "w", header: ("If-Match", "\(etag.weak.httpRepresentation)"), statusCode: .preconditionFailed, content: "")
            try await Assert(path: "w", header: ("If-Match", "\(ETag(safeValue: etag.weak.value).httpRepresentation)"), statusCode: .preconditionFailed, content: "")
            try await Assert(path: "w", header: ("If-Match", "\(etag.strong.httpRepresentation), \(etag.weak.httpRepresentation)"), statusCode: .preconditionFailed, content: "")
            try await Assert(path: "w", header: ("If-Match", "\"a\", *"), statusCode: .ok, content: "w")

            try await Assert(path: "w", header: ("If-None-Match", ""), statusCode: .ok, content: "w")
            try await Assert(path: "w", header: ("If-None-Match", "*"), statusCode: .notModified, content: "")
            try await Assert(path: "w", header: ("If-None-Match", "\(etag.weak.httpRepresentation)"), statusCode: .notModified, content: "")
            try await Assert(path: "w", header: ("If-None-Match", "\(ETag(safeValue: etag.weak.value).httpRepresentation)"), statusCode: .ok, content: "w")
            try await Assert(path: "w", header: ("If-None-Match", "\(etag.strong.httpRepresentation), \(etag.weak.httpRepresentation)"), statusCode: .notModified, content: "")
            try await Assert(path: "w", header: ("If-None-Match", "\"a\", *"), statusCode: .ok, content: "w")
        }
    }



    // MARK: - testModificationDatePrecondition()

    func testModificationDatePrecondition() async throws {

        struct ModificationDateServer : KvServer {

            static let date = KvRFC9110.makeDateFormatter().date(from: "Thu, 12 Oct 2023 15:05:14 GMT")!

            let configuration = TestKit.secureHttpConfiguration()

            var body: some KvResponseGroup {
                NetworkGroup(with: configuration) {
                    KvHttpResponse.static { .string { "-" } }

                    KvGroup("d") {
                        KvHttpResponse.static { .string({ "d" }).modificationDate(Self.date) }
                    }
                }
            }

        }

        try await TestKit.withRunningServer(of: ModificationDateServer.self, context: { TestKit.baseURL(for: $0.configuration) }) { baseURL in

            func Assert(path: String? = nil, header: (name: String, value: String)?, statusCode: HTTPResponseStatus, content: String)  async throws {
                let urlSession = URLSession(configuration: .ephemeral)
                try await TestKit.assertResponse(
                    urlSession: urlSession, baseURL, path: path,
                    onRequest: header.map { (name, value) in { $0.setValue(value, forHTTPHeaderField: name) } },
                    statusCode: statusCode, expecting: content
                )
            }

            let formatter = KvRFC9110.makeDateFormatter()
            let date = (past: formatter.string(from: ModificationDateServer.date.addingTimeInterval(-1.0)),
                        origin: formatter.string(from: ModificationDateServer.date),
                        future: formatter.string(from: ModificationDateServer.date.addingTimeInterval(1.0)))

            try await Assert(header: ("If-Modified-Since", ""), statusCode: .ok, content: "-")
            try await Assert(header: ("If-Modified-Since", date.past), statusCode: .ok, content: "-")
            try await Assert(header: ("If-Modified-Since", date.origin), statusCode: .ok, content: "-")
            try await Assert(header: ("If-Modified-Since", date.future), statusCode: .ok, content: "-")
            try await Assert(header: ("If-Modified-Since", "  " + date.past + ","), statusCode: .ok, content: "-")
            try await Assert(header: ("If-Modified-Since", date.past + "," + date.future), statusCode: .ok, content: "-")

            try await Assert(header: ("If-Unmodified-Since", ""), statusCode: .ok, content: "-")
            try await Assert(header: ("If-Unmodified-Since", date.past), statusCode: .ok, content: "-")
            try await Assert(header: ("If-Unmodified-Since", date.origin), statusCode: .ok, content: "-")
            try await Assert(header: ("If-Unmodified-Since", date.future), statusCode: .ok, content: "-")
            try await Assert(header: ("If-Unmodified-Since", "  " + date.past + ","), statusCode: .ok, content: "-")
            try await Assert(header: ("If-Unmodified-Since", date.past + "," + date.future), statusCode: .ok, content: "-")

            try await Assert(path: "d", header: ("If-Modified-Since", ""), statusCode: .ok, content: "d")
            try await Assert(path: "d", header: ("If-Modified-Since", date.past), statusCode: .ok, content: "d")
            try await Assert(path: "d", header: ("If-Modified-Since", date.origin), statusCode: .notModified, content: "")
            try await Assert(path: "d", header: ("If-Modified-Since", date.future), statusCode: .notModified, content: "")
            try await Assert(path: "d", header: ("If-Modified-Since", "  " + date.past + ","), statusCode: .ok, content: "d")
            try await Assert(path: "d", header: ("If-Modified-Since", date.past + "," + date.future), statusCode: .ok, content: "d")

            try await Assert(path: "d", header: ("If-Unmodified-Since", ""), statusCode: .ok, content: "d")
            try await Assert(path: "d", header: ("If-Unmodified-Since", date.past), statusCode: .preconditionFailed, content: "")
            try await Assert(path: "d", header: ("If-Unmodified-Since", date.origin), statusCode: .ok, content: "d")
            try await Assert(path: "d", header: ("If-Unmodified-Since", date.future), statusCode: .ok, content: "d")
            try await Assert(path: "d", header: ("If-Unmodified-Since", "  " + date.past + ","), statusCode: .ok, content: "d")
            try await Assert(path: "d", header: ("If-Unmodified-Since", date.past + "," + date.future), statusCode: .ok, content: "d")
        }
    }



    // MARK: Auxliliaries

    private typealias TestKit = KvServerTestKit

    private typealias NetworkGroup = TestKit.NetworkGroup

}



#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
#warning("Tests are not available due to URLCredential.init(trust:) or URLCredential.init(identity:certificates:persistence:) are not available")

#endif // os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
