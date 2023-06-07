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
//
//  KvHttp2KitTests.swift
//  kvHttp2Kit
//
//  Created by Svyatoslav Popov on 01.05.2020.
//

import XCTest

@testable import kvHttp2Kit



final class KvHttp2KitTests : XCTestCase {

    static var allTests = [
        ("default", testApplication),
    ]



    func testApplication() async throws {
        try await HttpServer.forEachTestConfiguration { configuration in
            let server = HttpServer(with: configuration)

            try server.start()
            defer { server.stop() }

            let baseURL = (server.endpointURLs?.first(where: { $0.host == "localhost" }))!

            // Just in case...
            try await Task.sleep(nanoseconds: 50_000_000)


            func AssertResponse(_ response: URLResponse, statusCode: KvHttpResponse.Status = .ok, contentType: KvHttpResponse.ContentType, message: String = "") {
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, numericCast(statusCode.code), message)
                XCTAssertEqual((response as? HTTPURLResponse)?.mimeType, contentType.components.mimeType, message)
            }


            let urlSession = URLSession.shared

            // ##  Root
            for url in [ baseURL, URL(string: "/", relativeTo: baseURL)! ] {
                let (data, response) = try await urlSession.data(from: url, delegate: IgnoringCertificateTaskDelegate())

                let message = "\(url.absoluteString), \(configuration.http)"

                AssertResponse(response, contentType: .plainText, message: message)
                XCTAssertEqual(String(data: data, encoding: .utf8), HttpServer.Constants.Greating.content, message)
            }

            // ##  Echo
            do {
                let body = Data((0 ..< Int.random(in: (1 << 16)...(1 << 17))).lazy.map { _ in UInt8.random(in: .min ... .max) })

                var request = URLRequest(url: URL(string: HttpServer.Constants.Echo.path, relativeTo: baseURL)!)
                request.httpMethod = "POST"
                request.httpBody = body

                let (data, response) = try await urlSession.data(for: request, delegate: IgnoringCertificateTaskDelegate())

                let message = "\(request.description), \(configuration.http)"

                AssertResponse(response, contentType: .binary, message: message)
                XCTAssertEqual(data, body, message)
            }

            // ##  Generator
            do {
                typealias T = HttpServer.NumberGeneratorStream.Element

                let range: ClosedRange<T> = T.random(in: -100_000 ... -10_000) ... T.random(in: 10_000 ... 100_000)

                let url: URL
                do {
                    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!

                    components.path = HttpServer.Constants.Generator.path
                    components.queryItems = [ .init(name: HttpServer.Constants.Generator.argFrom, value: String(range.lowerBound)),
                                              .init(name: HttpServer.Constants.Generator.argThrough, value: String(range.upperBound)), ]

                    url = components.url!
                }

                let (data, response) = try await urlSession.data(from: url, delegate: IgnoringCertificateTaskDelegate())

                let message = "\(url.absoluteString), \(configuration.http)"

                AssertResponse(response, contentType: .binary, message: message)

                data.withUnsafeBytes { buffer in
                    XCTAssertTrue(buffer.assumingMemoryBound(to: T.self).elementsEqual(range), message)
                }
            }
        }
    }



    // MARK: .IgnoringCertificateTaskDelegate

    private class IgnoringCertificateTaskDelegate : NSObject, URLSessionTaskDelegate {

        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            //Trust the certificate even if not valid
            let urlCredential = URLCredential(trust: challenge.protectionSpace.serverTrust!)

            completionHandler(.useCredential, urlCredential)
        }

    }



    // MARK: .HttpServer

    private class HttpServer : KvHttpServerDelegate, KvHttpClientDelegate {

        init(with configuration: KvHttpServer.Configuration) {
            httpServer = .init(with: configuration)
            httpServer.delegate = self
        }


        private let httpServer: KvHttpServer


        // MARK: .Constats

        struct Constants {

            struct Greating {

                static let path = "/"
                static var content: String { "Hello! It's a test server on KvHttp2Kit framework" }

            }

            struct Echo {

                static let path = "/echo"

            }

            struct Generator {

                static let path = "/generator"
                static let argFrom = "from"
                static let argThrough = "through"

            }

        }


        // MARK: Managing Life-cycle

        func start(options: KvHttpServer.StartOptions = [ ]) throws {
            try httpServer.start(options: options)
        }


        func stop() {
            httpServer.stop()
        }


        // MARK: Operations

        var configuration: KvHttpServer.Configuration { httpServer.configuration }

        var endpointURLs: [URL]? { httpServer.endpointURLs }


        // MARK: Test Auxiliaries

        static var testConfigurations: [KvHttpServer.Configuration] {
            get throws {
                let ssl = try KvHttpServer.Configuration.SSL(pemPath: Bundle.module.url(forResource: "https", withExtension: "pem", subdirectory: "Resources")!.path)

                return [
                    .init(port: 8080, http: .v1_1(ssl: nil)),
                    .init(port: 8081, http: .v1_1(ssl: ssl)),
                    .init(port: 8082, http: .v2(ssl: ssl)),
                ]
            }
        }


        static func forEachTestConfiguration(_ operation: @escaping (KvHttpServer.Configuration) async throws -> Void) async throws {
            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                try testConfigurations.forEach { configuration in
                    taskGroup.addTask {
                        try await operation(configuration)
                    }
                }
                try await taskGroup.waitForAll()
            }
        }


        // MARK: : KvHttpServerDelegate

        func httpServerDidStart(_ httpServer: KvHttpServer) { }


        func httpServer(_ httpServer: KvHttpServer, didStopWith result: Result<Void, Error>) {
            switch result {
            case .failure(let error):
                XCTFail("Simple test server did stop with error: \(error)")
            case .success:
                break
            }
        }


        func httpServer(_ httpServer: KvHttpServer, didFailToStartWith error: Error) {
            XCTFail("Simple test server did fail to start with error: \(error)")
        }


        func httpServer(_ httpServer: KvHttpServer, didStartClient httpClient: KvHttpServer.Client) {
            httpClient.delegate = self
        }


        func httpServer(_ httpServer: KvHttpServer, didStopClient httpClient: KvHttpServer.Client, with result: Result<Void, Error>) { }


        func httpServer(_ httpServer: KvHttpServer, didCatch error: Error) {
            XCTFail("Simple test server did catch error: \(error)")
        }


        // MARK: : KvHttpClientDelegate

        func httpClient(_ httpClient: KvHttpServer.Client, requestHandlerFor requestHead: KvHttpServer.RequestHead) -> KvHttpRequestHandler? {
            let uri = requestHead.uri

            guard let urlComponents = URLComponents(string: uri) else {
                XCTFail("Failed to parse request URI: \(uri)")
                return KvHttpRequest.HeadOnlyHandler(response: .init(status: .badRequest))
            }

            switch urlComponents.path {
            case "", Constants.Greating.path:
                return KvHttpRequest.HeadOnlyHandler(response: .init(
                    content: .init(type: .plainText, string: Constants.Greating.content)
                ))

            case Constants.Echo.path:
                return KvHttpRequest.CollectingBodyHandler(bodyLimits: 1_048_576 /*1 MiB */) { body in
                    guard let body = body else { return nil }

                    return .init(content: .init(data: body))
                }

            case Constants.Generator.path:
                guard let bodyStream = NumberGeneratorStream(queryItems: urlComponents.queryItems) else { return nil }

                return KvHttpRequest.HeadOnlyHandler(response: .init(content: .init() { buffer in
                    .success(bodyStream.read(buffer))
                }))

            default:
                break
            }

            return KvHttpRequest.HeadOnlyHandler(response: .init(status: .notFound))
        }


        func httpClient(_ httpClient: KvHttpServer.Client, didCatch error: Error) {
            XCTFail("Simple test server did catch client error: \(error)")
        }


        // MARK: .NumberGeneratorStream

        /// Input stream returning memory of array of consequent 32-bit signed numbers.
        fileprivate class NumberGeneratorStream {

            typealias Element = Int32


            init(on range: ClosedRange<Element>) {
                next = range.lowerBound
                count = 1 + UInt32(bitPattern: range.upperBound) &- UInt32(bitPattern: range.lowerBound)

                buffer = .allocate(capacity: 1024)

                slice = buffer.withMemoryRebound(to: UInt8.self, {
                    return .init(start: $0.baseAddress, count: 0)
                })
                cursor = slice.startIndex
            }


            convenience init?(queryItems: [URLQueryItem]?) {

                func TakeValue(from queryItem: URLQueryItem, to dest: inout Element?) {
                    guard let value = queryItem.value.map(Element.init(_:)) else { return }

                    dest = value
                }


                guard let queryItems = queryItems else { return nil }

                var bounds: (from: Element?, through: Element?) = (nil, nil)

                for queryItem in queryItems {
                    switch queryItem.name {
                    case Constants.Generator.argFrom:
                        TakeValue(from: queryItem, to: &bounds.from)
                    case Constants.Generator.argThrough:
                        TakeValue(from: queryItem, to: &bounds.through)
                    default:
                        // Unexpected query items are prohibited
                        return nil
                    }
                }

                guard let from = bounds.from,
                      let through = bounds.through,
                      from <= through
                else { return nil }

                self.init(on: from...through)
            }


            deinit {
                buffer.deallocate()
            }


            /// Next value to write in buffer.
            private var next: Element
            /// Number of values to write in buffer from *next*.
            private var count: UInt32

            private var buffer: UnsafeMutableBufferPointer<Element>

            private var slice: UnsafeMutableBufferPointer<UInt8>
            private var cursor: UnsafeMutableBufferPointer<UInt8>.Index


            // MARK: Operations

            var hasBytesAvailable: Bool { cursor < slice.endIndex || count > 0 }


            func read(_ buffer: UnsafeMutableRawBufferPointer) -> Int {
                updateBufferIfNeeded()

                guard hasBytesAvailable else { return 0 }

                let bytesToCopy = min(buffer.count, slice.endIndex - cursor)

                buffer.copyMemory(from: .init(start: slice.baseAddress, count: bytesToCopy))
                cursor += bytesToCopy

                return bytesToCopy
            }


            private func updateBufferIfNeeded() {
                guard cursor >= slice.endIndex, count > 0 else { return }

                let rangeCount: Int = min(numericCast(count), buffer.count)
                let range = next ..< (next + numericCast(rangeCount))

                _ = buffer.update(fromContentsOf: range)

                slice = .init(start: slice.baseAddress, count: rangeCount * MemoryLayout<Element>.size)

                cursor = slice.startIndex
                next = range.upperBound
                count -= numericCast(rangeCount)
            }

        }

    }

}
