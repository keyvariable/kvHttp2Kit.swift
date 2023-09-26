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
//  ImperativeServer.swift
//  ImperativeServer
//
//  Created by Svyatoslav Popov on 06.09.2023.
//

import kvServerKit

import Foundation



/// An example of a server implemented on *kvServerKit* in imperative way.
///
/// Server handles 3 requests:
/// - simple greeting GET request at the root path. It just returns a constant string.
/// - echo POST request at `/echo` path. It returns the same bytes as in the request body. Also it returns customized response for 413 (Payload Too Large) status.
/// - number generator GET request at `/generator` path. It takes `from` and `through` URL query arguments and returns array of 32-bit integers in *from*...*through* range as raw bytes.
///
/// Handling of requests is in ``httpClient(_:requestHandlerFor:)`` method.
class ImperativeServer : KvHttpServerDelegate, KvHttpChannelDelegate, KvHttpClientDelegate {

    /// - Note: Note that a server can have multiple channel configurations. A separate channel is created for each configuration.
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
            static var content: String { "Hello! It's a sample server on imperative API of kvServerKit framework" }

        }

        struct Echo {

            static let path = "/echo"
            static let bodyLimit: UInt = 256 << 10 // 256 KiB

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
    func waitWhileStarting() -> Result<Void, Error> { httpServer.waitWhileStarting() }


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
            print("ImperativeServer did stop with error: \(error)")
        case .success:
            break
        }
    }


    func httpServer(_ httpServer: KvHttpServer, didCatch error: Error) {
        print("ImperativeServer did catch error: \(error)")
    }


    // MARK: : KvHttpChannelDelegate

    func httpChannelDidStart(_ httpChannel: KvHttpChannel) { }


    func httpChannel(_ httpChannel: KvHttpChannel, didStopWith result: Result<Void, Error>) {
        switch result {
        case .failure(let error):
            print("ImperativeServer did stop channel with error: \(error)")
        case .success:
            break
        }
    }


    func httpChannel(_ httpChannel: KvHttpChannel, didCatch error: Error) {
        print("ImperativeServer did catch error on channel \(httpChannel): \(error)")
    }


    func httpChannel(_ httpChannel: KvHttpChannel, didStartClient httpClient: KvHttpChannel.Client) {
        httpClient.delegate = self
    }


    func httpChannel(_ httpChannel: KvHttpChannel, didStopClient httpClient: KvHttpChannel.Client, with result: Result<Void, Error>) {
        switch result {
        case .failure(let error):
            print("ImperativeServer did stop client with error: \(error)")
        case .success:
            break
        }
    }


    // MARK: : KvHttpClientDelegate

    func httpClient(_ httpClient: KvHttpChannel.Client, requestHandlerFor requestHead: KvHttpServer.RequestHead) -> KvHttpRequestHandler? {
        let uri = requestHead.uri

        guard let urlComponents = URLComponents(string: uri) else {
            print("Failed to parse request URI: \(uri)")
            return KvHttpRequest.HeadOnlyHandler(response: .badRequest)
        }

        switch urlComponents.path {
        case Constants.Greeting.path:
            return KvHttpRequest.HeadOnlyHandler(response: .string(Constants.Greeting.content))

        case Constants.Echo.path:
            return EchoRequestHandler()

        case Constants.Generator.path:
            guard let bodyStream = NumberGeneratorStream(queryItems: urlComponents.queryItems)
            else { return nil }

            return KvHttpRequest.HeadOnlyHandler(response: .bodyCallback { buffer in
                return .success(bodyStream.read(buffer))
            })

        default:
            break
        }

        return KvHttpRequest.HeadOnlyHandler(response: .notFound.string("404: resource at «\(urlComponents.path)» not found."))
    }


    func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.ClientIncident) -> KvHttpResponseProvider? { nil }


    func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
        print("ImperativeServer did catch client error: \(error)")
    }


    // MARK: .EchoRequestHandler

    /// Example of a class incapsulating handling of echo request.
    private class EchoRequestHandler : KvHttpRequest.CollectingBodyHandler {

        init() {
            super.init(bodyLengthLimit: Constants.Echo.bodyLimit) { body in
                guard let body = body else { return nil }

                return .binary(body)
            }
        }


        // MARK: : KvHttpRequestHandler

        override func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.RequestIncident) -> KvHttpResponseProvider? {
            switch incident {
            case .byteLimitExceeded:
                return incident.defaultResponse
                    .string("Payload exceeds \(Constants.Echo.bodyLimit) byte limit.")
            case .noResponse:
                return super.httpClient(httpClient, didCatch: incident)
            }
        }

    }


    // MARK: .NumberGeneratorStream

    /// Input stream returning memory of array of consequent 32-bit signed numbers.
    private class NumberGeneratorStream {

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
