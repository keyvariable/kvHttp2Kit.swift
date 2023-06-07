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
//  KvHttpServer.swift
//  kvHttp2Kit
//
//  Created by Svyatoslav Popov on 15.04.2020.
//

import Foundation

import kvKit
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOSSL



public protocol KvHttpServerDelegate : AnyObject {

    func httpServerDidStart(_ httpServer: KvHttpServer)

    func httpServer(_ httpServer: KvHttpServer, didStopWith result: Result<Void, Error>)

    /// - Note: A client delegate should be provided to *httpClient* or the client should be disconnected.
    func httpServer(_ httpServer: KvHttpServer, didStartClient httpClient: KvHttpServer.Client)

    func httpServer(_ httpServer: KvHttpServer, didStopClient httpClient: KvHttpServer.Client, with result: Result<Void, Error>)

    func httpServer(_ httpServer: KvHttpServer, didCatch error: Error)

}



public protocol KvHttpClientDelegate : AnyObject {

    /// - Returns: Request handler that will be passed with the request body bytes and will produce response.
    func httpClient(_ httpClient: KvHttpServer.Client, requestHandlerFor requestHead: KvHttpServer.RequestHead) -> KvHttpRequestHandler?

    /// - Note: The client will be disconnected.
    func httpClient(_ httpClient: KvHttpServer.Client, didCatch error: Error)

}



/// An HTTP/2 server handling requests in HTTP1 style. HTTP1 is supported.
///
/// This implementation provides ability to implement request handling in structured manner.
public class KvHttpServer {

    public typealias RequestHead = HTTPRequestHead

    public typealias Response = KvHttpResponse



    public let configuration: Configuration

    public weak var delegate: KvHttpServerDelegate?



    public init(with configuration: Configuration) {
        self.configuration = configuration
    }


    deinit {
        stop()
    }



    private let mutationLock = NSRecursiveLock()


    /// - Warning: Access must be protected with `.mutationLock`.
    private var _listeningChannel: Channel? {
        didSet {
            guard _listeningChannel !== oldValue else { return }

            // Assuming listenning channel is never replaced while server is running.
            assert((_listeningChannel == nil) || (oldValue == nil))

            try! oldValue?.close().wait()

            if let channel = _listeningChannel {
                delegate?.httpServerDidStart(self)

                channel.closeFuture.whenComplete({ [weak self] (result) in
                    self?.delegate?.httpServer(self!, didStopWith: result)
                })

            } else {
                _eventLoopGroup = nil
            }
        }
    }

    /// - Warning: Access must be protected with `.mutationLock`.
    private var _eventLoopGroup: MultiThreadedEventLoopGroup? {
        didSet {
            guard _eventLoopGroup !== oldValue else { return }

            try! oldValue?.syncShutdownGracefully()
        }
    }



    // MARK: Configuration

    public struct Configuration {

        public var host: String
        public var port: Int

        public var http: HTTP

        public var connection: Connection


        /// - Parameter host: Host name or IP address the server is listenning connections at. If `nil` is passed then ``Defaults``.host is used.
        /// - Parameter http: Configuration of HTTP protocol. If `nil` is passed then ``Defaults``.http is used.
        public init(host: String? = nil,
                    port: Int,
                    http: HTTP? = nil,
                    connection: Connection? = nil)
        {
            self.host = host ?? Defaults.host
            self.port = port
            self.http = http ?? Defaults.http
            self.connection = connection ?? Connection()
        }


        // MARK: .Defaults

        public struct Defaults {

            public static let host: String = "::1"

            public static let http: HTTP = .v1_1()

            /// In seconds.
            public static let connectionIdleTimeInterval: TimeInterval = 4.0
            public static let connectionRequestLimit: UInt = 128

        }


        // MARK: .HTTP

        /// Configuration of HTTP protocol. E.g. version of HTTP protocol, sequrity settings.
        public enum HTTP {

            case v1_1(ssl: SSL? = nil)
            case v2(ssl: SSL)


            // MARK: Operations

            @inlinable
            public var isSecure: Bool {
                switch self {
                case .v1_1(.some), .v2:
                    return true
                case .v1_1(.none):
                    return false
                }
            }

        }


        // MARK: .SSL

        public struct SSL {

            public var privateKey: NIOSSLPrivateKey
            public var certificateChain: [NIOSSLCertificate]


            @inlinable
            public init(privateKey: NIOSSLPrivateKey, certificateChain: [NIOSSLCertificate]) {
                self.privateKey = privateKey
                self.certificateChain = certificateChain
            }


            /// Initializes instance with contents of PEM file containing private key and certificate chain.
            ///
            /// For example an SSL certificate and the key pair for HTTPS can be created this way:
            /// ```
            /// $ openssl req -newkey rsa:2048 -new -nodes -x509 -days 3650 -keyout private_key.pem -out certificate.pem
            /// $ cat private_key.pem certificate.pem > https.pem
            /// ```
            @inlinable
            public init(pemPath: String) throws {
                self.init(privateKey: try NIOSSLPrivateKey(file: pemPath, format: .pem),
                          certificateChain: try NIOSSLCertificate.fromPEMFile(pemPath))
            }

        }


        // MARK: .Connection

        public struct Connection {

            public var idleTimeInterval: TimeInterval
            public var requestLimit: UInt


            @inlinable
            public init(idleTimeInterval: TimeInterval = Defaults.connectionIdleTimeInterval,
                        requestLimit: UInt = Defaults.connectionRequestLimit)
            {
                self.idleTimeInterval = idleTimeInterval
                self.requestLimit = requestLimit
            }

        }

    }



    // MARK: Status

    public var isStarted: Bool {
        KvThreadKit.locking(mutationLock) { _listeningChannel != nil }
    }


    /// An address new connections are listened at on local machine or in local network.
    public var localAddress: SocketAddress? {
        KvThreadKit.locking(mutationLock) { _listeningChannel?.localAddress }
    }

    /// URLs the receiver is available at on local machine or in local networks.
    public var endpointURLs: [URL]? {
        guard let localAddress = localAddress else { return nil }

        var endpointURLs: [URL] = .init()
        var uniqueHosts: Set<String?> = .init()
        var urlComponents = URLComponents()

        urlComponents.scheme = configuration.http.isSecure ? "https" : "http"
        urlComponents.port = localAddress.port


        func AddEndpoint(absoluteString: String) {
            guard let url = URL(string: absoluteString) else { return print("Warning: endpoint \(absoluteString) is not a valid URL") }

            endpointURLs.append(url)
        }


        func AddEndpoint(host: String?) {
            let urlHost: String? = host.map {
                if $0 == "::" {
                    return "[::1]"

                } else if $0.contains(":") {
                    return "[\($0)]"

                } else {
                    return $0
                }
            }

            guard !uniqueHosts.contains(urlHost) else { return }

            urlComponents.host = urlHost

            guard let url = urlComponents.url else { return print("Warning: unable to encode endpoint URL from components: \(urlComponents)") }

            endpointURLs.append(url)
            uniqueHosts.insert(urlHost)
        }


        // The local machine network interfaces.
        do {
            let host = Host.current()

            host.names.forEach(AddEndpoint(host:))
            host.addresses.forEach(AddEndpoint(host:))
        }

        // The local address.
        switch localAddress {
        case .unixDomainSocket:
            AddEndpoint(absoluteString: "\(localAddress)")
        case .v4, .v6:
            AddEndpoint(host: localAddress.ipAddress)
        }

        return endpointURLs
    }


    public func start(options: StartOptions = [ ]) throws {

        final class ErrorHandler : ChannelInboundHandler {

            init(_ server: KvHttpServer?) {
                self.server = server
            }


            private weak var server: KvHttpServer?


            typealias InboundIn = Never


            func errorCaught(context: ChannelHandlerContext, error: Error) {
                guard let server = server else { return NSLog("[KvHttpServer] Error: \(error)") }

                server.delegate?.httpServer(server, didCatch: error)

                context.close(promise: nil)
            }

        }


        func MakeSslContext(_ http: Configuration.HTTP) throws -> NIOSSLContext? {
            let ssl: Configuration.SSL
            let supportsHTTP2: Bool

            switch http {
            case .v1_1(.none):
                return nil
            case .v1_1(.some(let sslValue)):
                (ssl, supportsHTTP2) = (sslValue, false)
            case .v2(let sslValue):
                (ssl, supportsHTTP2) = (sslValue, true)
            }

            var tlsConfiguration = TLSConfiguration.makeServerConfiguration(certificateChain: ssl.certificateChain.map { .certificate($0) },
                                                                            privateKey: .privateKey(ssl.privateKey))
            if supportsHTTP2 {
                tlsConfiguration.applicationProtocols = [ "h2", "http/1.1" ]
            }

            return try NIOSSLContext(configuration: tlsConfiguration)
        }


        func ConfigureHttp1(_ server: KvHttpServer?, channel: Channel, channelHandler: InternalChannelHandler) -> EventLoopFuture<Void> {
            channelHandler.httpVersion = .http1_1

            return channel.pipeline.configureHTTPServerPipeline().flatMap { _ in
                channel.pipeline.addHandlers([
                    channelHandler,
                    ErrorHandler(server),
                ])
            }
        }


        func ConfigureHttp2(_ server: KvHttpServer?, channel: Channel, channelHandler: InternalChannelHandler) -> EventLoopFuture<Void> {
            channelHandler.httpVersion = .http2

            let errorHandler = ErrorHandler(server)

            return channel
                .configureHTTP2Pipeline(mode: .server) { streamChannel in
                    streamChannel.pipeline
                        .addHandler(HTTP2FramePayloadToHTTP1ServerCodec())
                        .flatMap {
                            streamChannel.pipeline.addHandlers([
                                channelHandler,
                                errorHandler,
                            ])
                        }
                }
                .flatMap { _ in channel.pipeline.addHandler(errorHandler) }
        }


        let listeningChannelCloseFuture: EventLoopFuture<Void>?

        do {
            mutationLock.lock()
            defer { mutationLock.unlock() }

            guard !isStarted else { return }

            let configuration = configuration
            let sslContext = try MakeSslContext(configuration.http)

            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

            let bootstrap = ServerBootstrap(group: eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

                .childChannelInitializer({ [weak self] channel in
                    let configurationHandler: () -> EventLoopFuture<Void> = { [weak self] in
                        let channelHandler: InternalChannelHandler

                        let future: EventLoopFuture<Void>
                        do {
                            switch configuration.http {
                            case .v1_1:
                                channelHandler = .init(self, httpVersion: .http1_1)
                                future = ConfigureHttp1(self, channel: channel, channelHandler: channelHandler)

                            case .v2:
                                channelHandler = .init(self, httpVersion: .http1_1)
                                future = channel.configureHTTP2SecureUpgrade(
                                    h2ChannelConfigurator: { [weak self] channel in
                                        ConfigureHttp2(self, channel: channel, channelHandler: channelHandler)
                                    },
                                    http1ChannelConfigurator: { [weak self] channel in
                                        ConfigureHttp1(self, channel: channel, channelHandler: channelHandler)
                                    }
                                )
                            }
                        }

                        channelHandler.channel = channel

                        self?.delegate?.httpServer(self!, didStartClient: channelHandler)

                        channel.closeFuture.whenComplete { [weak self] result in
                            self?.delegate?.httpServer(self!, didStopClient: channelHandler, with: result)
                        }

                        return future
                    }

                    switch sslContext {
                    case .none:
                        return configurationHandler()
                    case .some(let sslContext):
                        return channel.pipeline.addHandler(NIOSSLServerHandler(context: sslContext))
                            .flatMap(configurationHandler)
                    }
                })

                .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

            _listeningChannel = try bootstrap.bind(host: configuration.host, port: configuration.port).wait()

            self._eventLoopGroup = eventLoopGroup

            listeningChannelCloseFuture = _listeningChannel?.closeFuture
        }

        if options.contains(.synchronous) {
            try listeningChannelCloseFuture?.wait()
        }
    }


    /// Synchronously stops server.
    public func stop() {
        KvThreadKit.locking(mutationLock) {
            _listeningChannel = nil
        }
    }



    // MARK: .StartOptions

    public struct StartOptions : OptionSet {

        /// Causes start method to wait until the server is stopped.
        public static let synchronous = Self(rawValue: 1 << 0)


        // MARK: : OptionSet

        public let rawValue: UInt

        @inlinable public init(rawValue: UInt) { self.rawValue = rawValue }
    }



    // MARK: .Client

    public class Client {

        public typealias RequestPart = HTTPServerRequestPart


        public weak var delegate: KvHttpClientDelegate?

        public fileprivate(set) weak var httpServer: KvHttpServer? {
            get { locking { _httpServer } }
            set { locking { _httpServer = newValue } }
        }

        public var userInfo: Any? {
            get { locking { _userInfo } }
            set { locking { _userInfo = newValue } }
        }

        public var requestLimit: UInt {
            get { locking { _requestLimit } }
            set { locking { _requestLimit = newValue } }
        }

        fileprivate weak var channel: Channel?


        fileprivate init(_ httpServer: KvHttpServer?) {
            _httpServer = httpServer
            _requestLimit = httpServer?.configuration.connection.requestLimit ?? 0
        }


        private let mutationLock = NSRecursiveLock()

        /// - Warning: Access to this property must be protected with .mutationLock.
        private weak var _httpServer: KvHttpServer?
        /// - Warning: Access to this property must be protected with .mutationLock.
        private var _userInfo: Any?
        /// - Warning: Access to this property must be protected with .mutationLock.
        private var _requestLimit: UInt


        // MARK: Operations

        public func disconnect() { channel?.close(promise: nil) }


        // MARK: Locking

        fileprivate func locking<R>(_ body: () throws -> R) rethrows -> R { try KvThreadKit.locking(mutationLock, body: body) }

        fileprivate func lock() { mutationLock.lock() }

        fileprivate func unlock() { mutationLock.unlock() }

    }



    // MARK: .InternalChannelHandler

    /// - Note: Private additions to public ``Client`` class.
    fileprivate final class InternalChannelHandler : Client, ChannelInboundHandler {

        var httpVersion: HTTPVersion {
            get { locking { _httpVersion } }
            set { locking { _httpVersion = newValue } }
        }

        weak var context: ChannelHandlerContext? {
            didSet {
                guard context !== oldValue, context != nil else { return }

                if locking({ _activeRequestCount <= 0 }) {
                    startIdleTimeoutTask()
                }
            }
        }


        init(_ httpServer: KvHttpServer?, httpVersion: HTTPVersion) {
            self._httpVersion = httpVersion

            super.init(httpServer)
        }


        deinit {
            locking {
                _responseBuffer.clear()
            }
        }


        /// - Warning: Access must be protected by ``ChannelHandler``'s locking methods.
        private var _httpVersion: HTTPVersion

        /// Handler of request that is being received.
        private var requestHandler: KvHttpRequestHandler?

        /// Maximum number of bytes current request handler can process Number of received bytes passed to current `.requestHandler`.
        private var requestByteLimit: ByteLimit = .exact(0)

        /// Number of requests the responses have not been completely sent.
        ///
        /// - Warning: Access must be protected by ``ChannelHandler``'s locking methods.
        private var _activeRequestCount: UInt = 0 {
            didSet {
                switch (_activeRequestCount > 0, oldValue > 0) {
                case (true, false):
                    locking { _idleTimeoutTask = nil }
                case (false, true):
                    startIdleTimeoutTask()
                case (true, true), (false, false):
                    break
                }
            }
        }


        /// - Warning: Access must be protected by ``ChannelHandler``'s locking methods.
        private var _isIdleTimerFired = false

        /// - Warning: Access must be protected by ``ChannelHandler``'s locking methods.
        private var _idleTimeoutTask: Scheduled<Void>? {
            willSet { locking { _idleTimeoutTask?.cancel() } }
        }

        /// - Warning: Access must be protected by ``ChannelHandler``'s locking methods.
        private var _responseBuffer: ByteBuffer = {
            var buffer = ByteBuffer()
            buffer.reserveCapacity(minimumWritableBytes: Constants.responseBufferCapacity)
            return buffer
        }()

        /// Value to insert in next response header for `connection` key.
        ///
        /// - Note: Used in HTTP1 only.
        /// - Note: Assuming there is no request pooling.
        private var nextResponseConnectionHeaderValue: String?


        // MARK: .Constants

        private struct Constants {

            static var responseBufferCapacity: Int { 1 << 14 }

            static let connectionHeaderValues: Set<String> = [ "keep-alive", "close" ]

        }


        // MARK: .ByteLimit

        private enum ByteLimit {

            /// Exact number of bytes are expected to be received. Otherwise request is rejected.
            case exact(UInt)
            /// Maximum number of bytes allowed to be received. If larger number of bytes are received then request is rejected.
            case maximum(UInt)


            // MARK: Operations

            /// A boolean value indicating whether the limit condition is met.
            var isAcceptable: Bool {
                switch self {
                case .exact(let value):
                    return value == 0
                case .maximum:
                    return true
                }
            }

            /// Reduces *lhs* by *rhs* number of bytes.
            ///
            /// - Returns: Resulting limit or `nil` if the limit is exceeded.
            static func -(lhs: Self, rhs: Int) -> Self? {
                assert(rhs >= 0, "Internal inconsistency: number of bytes (\(rhs)) is negative")

                let rhs: UInt = numericCast(rhs)

                switch lhs {
                case .exact(let value):
                    guard value >= rhs else { return nil }
                    return .exact(value - rhs)

                case .maximum(let value):
                    guard value >= rhs else { return nil }
                    return .maximum(value - rhs)
                }
            }

        }


        // MARK: Operations

        override func disconnect() {
            guard let context = context
            else { return super.disconnect() }

            context.close(promise: nil)
        }


        func process(request: InboundIn) {
            switch request {
            case .head(let head):
                guard handleRequestHead(head) else { return disconnect() }

            case .body(var byteBuffer):
                handleRequestBodyBytes(&byteBuffer)

            case .end(_):
                handleRequestEnd()
            }
        }


        /// - Returns: A boolean value indicating whether request is valid.
        private func handleRequestHead(_ head: HTTPRequestHead) -> Bool {
            do {
                let newRequestHandler = delegate?.httpClient(self, requestHandlerFor: head)

                locking {
                    _activeRequestCount += (newRequestHandler != nil ? 1 : 0) - (requestHandler != nil ? 1 : 0)
                    requestHandler = newRequestHandler
                }
            }

            // Clients sending unexpected requests are disconnected immediately.
            guard let requestHandler = requestHandler else { return false }

            do {
                let requestByteLimit: ByteLimit

                switch head.headers.first(name: "Content-Length").flatMap(UInt.init(_:)) {
                case .some(let contentLength):
                    guard contentLength <= requestHandler.contentLengthLimit else { return false }
                    requestByteLimit = .exact(contentLength)

                case .none:
                    requestByteLimit = .maximum(requestHandler.implicitBodyLengthLimit)
                }

                self.requestByteLimit = requestByteLimit
            }

            // Handling of `connection` header.
            switch head.version {
            case .http1_0:
                // In HTTP 1.0 connections are closed by default. So when request has `keep-alive`, it should be mirrored in response.
                nextResponseConnectionHeaderValue = Self.hasConnectionHeaders(head) && head.isKeepAlive ? "keep-alive" : nil

            case .http1_1:
                // In HTTP 1.1 connections are not closed by default. So when request has `close`, it should be mirrored in response.
                nextResponseConnectionHeaderValue = Self.hasConnectionHeaders(head) && !head.isKeepAlive ? "close" : nil

            default:
                break
            }

            return true
        }


        private static func hasConnectionHeaders(_ head: HTTPRequestHead) -> Bool {
            head.headers[canonicalForm: "connection"]
                .lazy.map { $0.lowercased() }
                .contains(where: Constants.connectionHeaderValues.contains(_:))
        }


        private func handleRequestBodyBytes(_ byteBuffer: inout ByteBuffer) {
            guard let requestHandler = requestHandler,
                  let byteLimit = requestByteLimit - byteBuffer.readableBytes
            else { return disconnect() }

            requestByteLimit = byteLimit

            byteBuffer.readWithUnsafeReadableBytes { pointer in
                requestHandler.httpClient(self, didReceiveBodyBytes: pointer)
                return pointer.count
            }
        }


        private func handleRequestEnd() {
            guard let requestHandler = requestHandler,
                  requestByteLimit.isAcceptable
            else { return disconnect() }

            self.requestHandler = nil
            requestByteLimit = .exact(0)

            let connectionHeaderValue = nextResponseConnectionHeaderValue
            nextResponseConnectionHeaderValue = nil

            Task.detached {
                guard let response = await requestHandler.httpClientDidReceiveEnd(self) else {
                    self.locking { self._activeRequestCount -= 1 }
                    return
                }

                // Note: _activeRequestCount will be decreased
                do {
                    guard let context = self.context else { throw KvError.inconsistency("Channel handler has no context") }

                    context.eventLoop.execute {
                        let httpVersion = self.locking { self._httpVersion }

                        switch httpVersion {
                        case .http2:
                            let channel = context.channel

                            channel.getOption(HTTP2StreamChannelOptions.streamID)
                                .whenComplete { result in
                                    guard case .success(let streamID) = result else {
                                        KvDebug.pause("Failed to get HTTP/2.0 stream ID channel option")
                                        self.disconnect()
                                        return
                                    }

                                    self.channelWrite(response: response,
                                                      httpVersion: httpVersion,
                                                      http2StreamID: String(Int(streamID)),
                                                      connectionHeaderValue: connectionHeaderValue)
                                }

                        default:
                            self.channelWrite(response: response,
                                              httpVersion: httpVersion,
                                              http2StreamID: nil,
                                              connectionHeaderValue: connectionHeaderValue)
                        }
                    }
                }
                catch { requestHandler.httpClient(self, didCatch: error) }
            }
        }


        private func channelWrite(response: Response, httpVersion: HTTPVersion, http2StreamID: String?, connectionHeaderValue: String?) {
            guard let context = context else { return KvDebug.pause("Channel handler has no context") }

            let channel = context.channel

            let headers: HTTPHeaders = {
                var headers = HTTPHeaders()

                if let content = response.content {
                    if let contentType = content.type {
                        headers.add(name: "Content-Type", value: contentType.value)
                    }
                    if let contentLength = content.length {
                        headers.add(name: "Content-Length", value: String(contentLength))
                    }

                    content.customHeaderCallback?(&headers)
                }

                if let http2StreamID = http2StreamID {
                    headers.add(name: "x-stream-id", value: http2StreamID)
                }

                return headers
            }()

            // Head
            let head: HTTPResponseHead = {
                var head = HTTPResponseHead(version: httpVersion, status: response.status, headers: headers)

                if let connectionValue = connectionHeaderValue {
                    head.headers.add(name: "Connection", value: connectionValue)
                }

                channel.write(wrapOutboundOut(HTTPServerResponsePart.head(head)), promise: nil)

                return head
            }()

            // Body
            if let bodyCallback = response.content?.bodyCallback {
                do {
                    try locking {
                        while true {
                            _responseBuffer.clear(minimumCapacity: Constants.responseBufferCapacity)

                            let bytesRead = try _responseBuffer.writeWithUnsafeMutableBytes(minimumWritableBytes: 0) { dest in
                                try bodyCallback(dest).get()
                            }

                            guard bytesRead > 0 else { break }

                            channel.writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.body(.byteBuffer(_responseBuffer))), promise: nil)
                        }
                    }
                }
                catch { delegate?.httpClient(self, didCatch: error) }
            }

            // End
            do {
                channel.writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.end(nil)), promise: nil)

                self.locking {
                    self._activeRequestCount -= 1
                    self.requestLimit = self.requestLimit > 0 ? self.requestLimit - 1 : 0
                }

                let needsClose: Bool = self.locking {
                    // Connections are closed when there are no received request.
                    guard self._activeRequestCount <= 0 else { return false }

                    return (!head.isKeepAlive
                            || self.context == nil
                            || self._isIdleTimerFired
                            || self.requestLimit <= 0)
                }

                if needsClose {
                    context.close(promise: nil)
                }
            }
        }


        private func startIdleTimeoutTask() {
            locking {
                guard !_isIdleTimerFired,
                      let context = context,
                      let idleTimeInterval = httpServer?.configuration.connection.idleTimeInterval
                else { return }

                _idleTimeoutTask = context.eventLoop.scheduleTask(in: .nanoseconds(.init(idleTimeInterval * 1e9))) { [weak self] in
                    self?.handleIdleTimeout()
                }
            }
        }


        private func handleIdleTimeout() {
            do {
                lock()
                defer { unlock() }

                _idleTimeoutTask = nil
                _isIdleTimerFired = true

                guard _activeRequestCount <= 0 else { return }
            }

            disconnect()
        }


        // MARK: : ChannelInboundHandler

        typealias InboundIn = RequestPart
        typealias OutboundOut = HTTPServerResponsePart


        func handlerAdded(context: ChannelHandlerContext) {
            self.context = context
        }


        func handlerRemoved(context: ChannelHandlerContext) {
            assert(self.context == context)

            self.context = nil
        }


        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            assert(self.context == context)

            process(request: unwrapInboundIn(data))
        }


        func errorCaught(context: ChannelHandlerContext, error: Error) {
            assert(self.context == context)

            delegate?.httpClient(self, didCatch: error)

            disconnect()
        }

    }

}



// MARK: .Context Extenstions

extension ChannelHandlerContext : Hashable {

    // MARK: : Equatable

    public static func ==(lhs: ChannelHandlerContext, rhs: ChannelHandlerContext) -> Bool { lhs === rhs }


    // MARK: : Hashable

    public func hash(into hasher: inout Hasher) { ObjectIdentifier(self).hash(into: &hasher) }

}
