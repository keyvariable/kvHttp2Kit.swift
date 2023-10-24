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
//  KvHttpResponseProviderTests.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 10.10.2023.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import XCTest

@testable import kvServerKit



final class KvHttpResponseProviderTests : XCTestCase {

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
                    try await TestKit.assertResponse(baseURL, query: query, statusCode: .notFound, contentType: .text(.plain)) { data, request, message in
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
                        case KvHttpResponseError.fileDoesNotExist(_), KvHttpResponseError.unableToFindIndexFile(_):
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

                switch try? KvDirectory.ResolvedURL(for: fileURL).value {
                case .some(let url):
                    let data = try Data(contentsOf: url)
                    try await TestKit.assertResponse(baseURL, path: path, contentType: nil, expecting: data)
                case .none:
                    try await TestKit.assertResponse(baseURL, path: path, statusCode: .internalServerError, expecting: FileServer.errorMessage)
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
