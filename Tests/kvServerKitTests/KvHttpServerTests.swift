//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2021 Svyatoslav Popov (info@keyvar.com).
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
//  KvHttpServerTests.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 01.05.2020.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)

import XCTest

@testable import kvServerKit



final class KvHttpServerTests : XCTestCase {

    // MARK: - testHttpServer()

    func testHttpServer() async throws {
        let configurations = KvServerTestKit.testConfigurations

        let server = ImperativeHttpServer(with: configurations)

        try server.start()
        defer {
            server.stop()
            try! server.waitUntilStopped().get()
        }

        try await server.forEachChannel { channel in
            try channel.waitWhileStarting().get()
            XCTAssertEqual(channel.state, .running)

            let configuration = channel.configuration
            let baseURL = KvServerTestKit.baseURL(for: configuration)
            let httpDescription = KvServerTestKit.description(of: configuration.http)

            // ##  Root
            for url in [ baseURL, URL(string: "/", relativeTo: baseURL)! ] {
                try await KvServerTestKit.assertResponse(url, contentType: .text(.plain), expecting: ImperativeHttpServer.Constants.Greeting.content, message: httpDescription)
            }

            // ##  Echo
            do {
                let body = Data((0 ..< Int.random(in: (1 << 16)...(1 << 17))).lazy.map { _ in UInt8.random(in: .min ... .max) })

                try await KvServerTestKit.assertResponse(
                    baseURL, method: "POST", path: ImperativeHttpServer.Constants.Echo.path, body: body,
                    contentType: .application(.octetStream), expecting: body, message: httpDescription
                )
            }

            // ##  Generator
            do {
                typealias T = ImperativeHttpServer.NumberGeneratorStream.Element

                let range: ClosedRange<T> = T.random(in: -100_000 ... -10_000) ... T.random(in: 10_000 ... 100_000)
                let queryItems = [ URLQueryItem(name: ImperativeHttpServer.Constants.Generator.argFrom, value: String(range.lowerBound)),
                                   URLQueryItem(name: ImperativeHttpServer.Constants.Generator.argThrough, value: String(range.upperBound)), ]

                try await KvServerTestKit.assertResponse(
                    baseURL, path: ImperativeHttpServer.Constants.Generator.path,
                    query: .items(queryItems),
                    contentType: .application(.octetStream), message: httpDescription
                ) { data, request, message in
                    data.withUnsafeBytes { buffer in
                        XCTAssertTrue(buffer.assumingMemoryBound(to: T.self).elementsEqual(range), message())
                    }
                }
            }
        }
    }

}



// MARK: - Auxiliaries

extension KvHttpServerTests {

    // MARK: .ImperativeHttpServer

    private class ImperativeHttpServer : KvHttpServerDelegate, KvHttpChannelDelegate, KvHttpClientDelegate {

        init<S>(with configurations: S) where S : Sequence, S.Element == KvHttpChannel.Configuration {
            httpServer.delegate = self

            configurations.forEach {
                let channel = KvHttpChannel(with: $0)

                channel.delegate = self

                httpServer.addChannel(channel)
            }
        }


        private let httpServer: KvHttpServer = .init()


        // MARK: .Constats

        struct Constants {

            struct Greeting {

                static let path = "/"
                static var content: String { "Hello! It's a test server on kvServerKit framework" }

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

        func start() throws {
            try httpServer.start()
        }


        func stop() {
            httpServer.stop()
        }


        @discardableResult
        func waitUntilStarted() -> Result<Void, Error> { httpServer.waitWhileStarting() }


        @discardableResult
        func waitUntilStopped() -> Result<Void, Error> { httpServer.waitUntilStopped() }


        // MARK: Operations

        var endpointURLs: [URL]? { httpServer.endpointURLs }


        func forEachChannel(_ body: (KvHttpChannel) async throws -> Void) async rethrows {
            for channel in httpServer.channelIDs.lazy.map({ self.httpServer.channel(with: $0)! }) {
                try await body(channel)
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


        func httpServer(_ httpServer: KvHttpServer, didCatch error: Error) {
            XCTFail("Simple test server did catch error: \(error)")
        }


        // MARK: : KvHttpChannelDelegate

        func httpChannelDidStart(_ httpChannel: KvHttpChannel) { }


        func httpChannel(_ httpChannel: KvHttpChannel, didStopWith result: Result<Void, Error>) {
            switch result {
            case .failure(let error):
                XCTFail("Simple test server did stop channel with error: \(error)")
            case .success:
                break
            }
        }


        func httpChannel(_ httpChannel: KvHttpChannel, didCatch error: Error) {
            XCTFail("Simple test server did catch error on channel \(httpChannel): \(error)")
        }


        func httpChannel(_ httpChannel: KvHttpChannel, didStartClient httpClient: KvHttpChannel.Client) {
            httpClient.delegate = self
        }


        func httpChannel(_ httpChannel: KvHttpChannel, didStopClient httpClient: KvHttpChannel.Client, with result: Result<Void, Error>) {
            switch result {
            case .failure(let error):
                XCTFail("Simple test server did stop client with error: \(error)")
            case .success:
                break
            }
        }


        // MARK: : KvHttpClientDelegate

        func httpClient(_ httpClient: KvHttpChannel.Client, requestHandlerFor requestHead: KvHttpServer.RequestHead) -> KvHttpRequestHandler? {
            let uri = requestHead.uri

            guard let urlComponents = URLComponents(string: uri) else {
                XCTFail("Failed to parse request URI: \(uri)")
                return KvHttpRequest.HeadOnlyHandler(response: .init(status: .badRequest))
            }

            switch urlComponents.path {
            case Constants.Greeting.path:
                return KvHttpRequest.HeadOnlyHandler(response: .string(Constants.Greeting.content))

            case Constants.Echo.path:
                return KvHttpRequest.CollectingBodyHandler(bodyLimits: 262_144 /* 256 KiB */) { body in
                    guard let body = body else { return nil }

                    return .binary(body)
                }

            case Constants.Generator.path:
                guard let bodyStream = NumberGeneratorStream(queryItems: urlComponents.queryItems)
                else { return nil }

                return KvHttpRequest.HeadOnlyHandler(response: .bodyCallback { buffer in
                        .success(bodyStream.read(buffer))
                })

            default:
                break
            }

            return KvHttpRequest.HeadOnlyHandler(response: .init(status: .notFound))
        }


        func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
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



#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
#warning("Tests are not available due to URLCredential.init(trust:) or URLCredential.init(identity:certificates:persistence:) are not available")

#endif // os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
