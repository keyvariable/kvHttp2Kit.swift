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



import Foundation
import kvKit
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOSSL



public protocol KvHttpServerDelegate : AnyObject {

    func httpServerDidStart(_ httpServer: KvHttpServer)

    func httpServer(_ httpServer: KvHttpServer, didStopWith result: Result<Void, Error>)

    func httpServer(_ httpServer: KvHttpServer, didStart httpChannelhandler: KvHttpServer.ChannelHandler)

    func httpServer(_ httpServer: KvHttpServer, didCatch error: Error)

}



public protocol KvHttpChannelHandlerDelegate : AnyObject {

    func httpChannelHandler(_ httpChannelHandler: KvHttpServer.ChannelHandler, didReceive requestPart: KvHttpServer.ChannelHandler.RequestPart)

    func httpChannelHandler(_ httpChannelHandler: KvHttpServer.ChannelHandler, didCatch error: Error)

}



/// An HTTP/2 server handling requests in HTTP1 style.
public class KvHttpServer {

    public let configuration: Configuration


    public weak var delegate: KvHttpServerDelegate?



    public init(with configuration: Configuration) {
        self.configuration = configuration
    }



    deinit {
        KvThreadKit.locking(mutationLock) {
            channel = nil
        }
    }



    private let mutationLock = NSRecursiveLock()


    private var channel: Channel? {
        didSet {
            guard channel !== oldValue else { return }

            try! oldValue?.close().wait()

            if let channel = channel {
                delegate?.httpServerDidStart(self)

                channel.closeFuture.whenComplete({ [weak self] (result) in
                    guard let server = self else { return }

                    KvThreadKit.locking(server.mutationLock) {
                        server.channel = nil
                    }

                    server.delegate?.httpServer(server, didStopWith: result)
                })

            } else {
                eventLoopGroup = nil
            }
        }
    }

    private var eventLoopGroup: MultiThreadedEventLoopGroup? {
        didSet {
            guard eventLoopGroup !== oldValue else { return }

            try! oldValue?.syncShutdownGracefully()
        }
    }

}



// MARK: Configuration

extension KvHttpServer {

    public struct Configuration {

        public var host: String
        public var port: Int

        /// Empty value means `.Defaults.protocols` will be applied.
        public var protocols: Protocols

        public var ssl: SSL

        public var connection: Connection


        public init(host: String = Defaults.host,
                    port: Int, protocols: Protocols? = nil,
                    ssl: SSL,
                    connection: Connection? = nil)
        {
            self.host = host
            self.port = port
            self.protocols = protocols ?? Defaults.protocols
            self.ssl = ssl
            self.connection = connection ?? Connection()
        }


        // MARK: .Defaults

        public struct Defaults {

            public static let host: String = "::1"

            public static let protocols: Protocols = [ .http_1_1, .http_2_0 ]

            /// In seconds.
            public static let connectionIdleTimeInterval: TimeInterval = 4.0
            public static let connectionRequestLimit: UInt = 128

        }


        // MARK: .Protocols

        public struct Protocols : OptionSet {

            public static let http_1_1 = Protocols(rawValue: 1 << 1)
            public static let http_2_0 = Protocols(rawValue: 1 << 2)


            public let rawValue: UInt

            public init(rawValue: UInt) {
                self.rawValue = rawValue
            }

        }


        // MARK: .SSL

        public struct SSL {

            public var privateKey: NIOSSLPrivateKey
            public var certificateChain: [NIOSSLCertificate]


            public init(privateKey: NIOSSLPrivateKey, certificateChain: [NIOSSLCertificate]) {
                self.privateKey = privateKey
                self.certificateChain = certificateChain
            }

        }


        // MARK: .Connection

        public struct Connection {

            public var idleTimeInterval: TimeInterval
            public var requestLimit: UInt


            public init(idleTimeInterval: TimeInterval = Defaults.connectionIdleTimeInterval,
                        requestLimit: UInt = Defaults.connectionRequestLimit)
            {
                self.idleTimeInterval = idleTimeInterval
                self.requestLimit = requestLimit
            }

        }


        // MARK: Operations

        var effectiveProtocols: Protocols { !protocols.isEmpty ? protocols : Defaults.protocols }

    }

}



// MARK: Context

extension KvHttpServer {

    public typealias Context = ChannelHandlerContext

}



extension KvHttpServer.Context : Hashable {

    // MARK: : Equatable

    public static func ==(lhs: KvHttpServer.Context, rhs: KvHttpServer.Context) -> Bool { lhs === rhs }



    // MARK: : Hashable

    public func hash(into hasher: inout Hasher) { ObjectIdentifier(self).hash(into: &hasher) }

}



// MARK: Status

extension KvHttpServer {

    public var isStarted: Bool {
        KvThreadKit.locking(mutationLock) { channel != nil }
    }


    public var localAddress: SocketAddress? {
        KvThreadKit.locking(mutationLock) { channel?.localAddress }
    }



    public func start(synchronous isSynchronous: Bool = false) throws {

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


        try KvThreadKit.locking(mutationLock) {
            guard !isStarted else { return }

            let protocols = configuration.effectiveProtocols
            let tlsConfiguration = TLSConfiguration.makeServerConfiguration(certificateChain: configuration.ssl.certificateChain.map { .certificate($0) },
                                                                            privateKey: .privateKey(configuration.ssl.privateKey))
            // Configure the SSL context that is used by all SSL handlers.
            let sslContext = try NIOSSLContext(configuration: tlsConfiguration)

            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

            let bootstrap = ServerBootstrap(group: eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

                .childChannelInitializer({ [weak self] channel in
                    channel.pipeline.addHandler(NIOSSLServerHandler(context: sslContext))
                        .flatMap { [weak self] in

                            func MakeChanelHandler<T : KvHttpServerInternalChannelHandlerInit>(_ type: T.Type, _ server: KvHttpServer?) -> T {
                                let channelHandler = T(server)

                                server?.delegate?.httpServer(server!, didStart: channelHandler)

                                return channelHandler
                            }


                            func ConfigureHttp2(_ server: KvHttpServer?, channel: Channel) -> EventLoopFuture<Void> {
                                let errorHandler = ErrorHandler(server)

                                return channel.configureHTTP2Pipeline(mode: .server) { streamChannel in
                                    streamChannel.pipeline.addHandler(HTTP2FramePayloadToHTTP1ServerCodec())
                                        .flatMap {
                                            streamChannel.pipeline.addHandlers([
                                                MakeChanelHandler(InternalChannelHandlerHttp2.self, server),
                                                errorHandler,
                                            ])
                                        }
                                }
                                .flatMap { _ in channel.pipeline.addHandler(errorHandler) }
                            }


                            func ConfigureHttp1(_ server: KvHttpServer?, channel: Channel) -> EventLoopFuture<Void> {
                                channel.pipeline.configureHTTPServerPipeline().flatMap { _ in
                                    channel.pipeline.addHandlers([
                                        MakeChanelHandler(InternalChannelHandlerHttp1.self, server),
                                        ErrorHandler(server),
                                    ])
                                }
                            }


                            switch protocols {
                            case .http_1_1:
                                return ConfigureHttp1(self, channel: channel)
                            case .http_2_0:
                                return ConfigureHttp2(self, channel: channel)
                            case [ .http_1_1, .http_2_0 ]:
                                return channel.configureHTTP2SecureUpgrade(
                                    h2ChannelConfigurator: { [weak self] channel in ConfigureHttp2(self, channel: channel) },
                                    http1ChannelConfigurator: { [weak self] channel in ConfigureHttp1(self, channel: channel) }
                                )
                            default:
                                return ConfigureHttp1(self, channel: channel)
                            }
                        }
                })

                .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
                .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
                .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

            channel = try bootstrap.bind(host: configuration.host, port: configuration.port).wait()

            self.eventLoopGroup = eventLoopGroup

            if isSynchronous {
                try channel?.closeFuture.wait()
            }
        }
    }



    public func stop() {
        KvThreadKit.locking(mutationLock) {
            channel = nil
        }
    }

}



// MARK: Response

extension KvHttpServer {

    public enum Response {
        case json(Data)
    }

}



// MARK: KvHttpServerInternalChannelHandler

fileprivate protocol KvHttpServerInternalChannelHandlerInit : KvHttpServer.ChannelHandler {

    init(_ httpServer: KvHttpServer?)

}



// MARK: .ChannelHandler

extension KvHttpServer {

    public class ChannelHandler {

        public typealias RequestPart = HTTPServerRequestPart


        public weak var delegate: KvHttpChannelHandlerDelegate? {
            get { locking { _delegate } }
            set { locking { _delegate = newValue } }
        }

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


        fileprivate init(_ httpServer: KvHttpServer?) {
            _httpServer = httpServer
            _requestLimit = httpServer?.configuration.connection.requestLimit ?? 0
        }


        private let mutationLock = NSRecursiveLock()

        /// - Warning: Access to this property must be protected with .mutationLock.
        private weak var _delegate: KvHttpChannelHandlerDelegate?
        /// - Warning: Access to this property must be protected with .mutationLock.
        private weak var _httpServer: KvHttpServer?
        /// - Warning: Access to this property must be protected with .mutationLock.
        private var _userInfo: Any?
        /// - Warning: Access to this property must be protected with .mutationLock.
        private var _requestLimit: UInt


        // MARK: Operations

        public func submit(_ response: Response) throws { throw KvError.inconsistency("implementation for \(#function) is missing") }


        // MARK: Locking

        fileprivate func locking<R>(_ body: () throws -> R) rethrows -> R { try KvThreadKit.locking(mutationLock, body: body) }

        fileprivate func lock() { mutationLock.lock() }

        fileprivate func unlock() { mutationLock.unlock() }

    }



    // MARK: .InternalChannelHandlerBase

    /// - Note: Fileprivate additions to public ``ChannelHandler`` class.
    fileprivate class InternalChannelHandlerBase : ChannelHandler, ChannelInboundHandler {

        let httpVersion: HTTPVersion


        weak var context: ChannelHandlerContext? {
            didSet {
                guard context !== oldValue, context != nil else { return }

                if locking({ _activeRequestCount <= 0 }) {
                    startIdleTimeoutTask()
                }
            }
        }



        init(_ httpServer: KvHttpServer?, httpVersion: HTTPVersion) {
            self.httpVersion = httpVersion

            super.init(httpServer)
        }



        /// - Warning: Access must be protected by ``ChannelHandler``'s locking methods.
        private var _activeRequestCount: UInt = 0 {
            didSet {
                switch (_activeRequestCount > 0, oldValue > 0) {
                case (true, false):
                    startIdleTimeoutTask()
                case (false, true):
                    locking {
                        _idleTimeoutTask = nil
                    }
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



        // MARK: Operations

        func process(request: InboundIn) {
            locking {
                _activeRequestCount += 1
            }

            delegate?.httpChannelHandler(self, didReceive: request)
        }


        /// Override it to mutate head part of the response.
        func willWrite(head: inout HTTPResponseHead) { }


        func channelWrite(response: Response, http2StreamID: String?) {
            guard let context = context else { return KvDebug.pause("Channel handler has no context") }

            let channel = context.channel


            func DataBuffer(_ data: Data) -> ByteBuffer {
                var buffer = channel.allocator.buffer(capacity: data.count)

                buffer.writeBytes(data)

                return buffer
            }


            let (contentType, contentLength, buffer): (String?, UInt64?, ByteBuffer?) = {
                switch response {
                case .json(let data):
                    return ("application/json; charset=utf-8", numericCast(data.count), DataBuffer(data))
                }
            }()

            let headers: HTTPHeaders = {
                var headers = HTTPHeaders()

                if let contentType = contentType {
                    headers.replaceOrAdd(name: "Content-Type", value: contentType)
                }
                if let contentLength = contentLength {
                    headers.replaceOrAdd(name: "Content-Length", value: String(contentLength))
                }

                if let http2StreamID = http2StreamID {
                    headers.add(name: "x-stream-id", value: http2StreamID)
                }

                return headers
            }()

            let head: HTTPResponseHead = {
                var head = HTTPResponseHead(version: httpVersion, status: .ok, headers: headers)
                willWrite(head: &head)
                return head
            }()
            channel.write(wrapOutboundOut(HTTPServerResponsePart.head(head)), promise: nil)

            if let buffer = buffer {
                channel.write(wrapOutboundOut(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
            }

            channel
                .writeAndFlush(wrapOutboundOut(HTTPServerResponsePart.end(nil)))
                .whenComplete { _ in
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

                    guard needsClose else { return }

                    context.close(promise: nil)
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

            context?.close(promise: nil)
        }



        // MARK: .Options

        struct Options : OptionSet {

            static let writesStreamID = Options(rawValue: 1 << 0)


            let rawValue: UInt

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

            delegate?.httpChannelHandler(self, didCatch: error)

            context.close(promise: nil)
        }

    }



    // MARK: .InternalChannelHandlerHttp1

    fileprivate class InternalChannelHandlerHttp1 : InternalChannelHandlerBase, KvHttpServerInternalChannelHandlerInit {

        required init(_ httpServer: KvHttpServer?) {
            super.init(httpServer, httpVersion: .http1_1)
        }


        /// - Note: Assuming there is no request pooling.
        /// - Warning: Access must be protected by ``ChannelHandler``'s locking methods.
        private var _requestHead: HTTPRequestHead?


        // MARK: Opertions

        override func process(request: InboundIn) {
            if case .head(let head) = request {
                locking {
                    _requestHead = head
                }
            }

            super.process(request: request)
        }


        override func willWrite(head: inout HTTPResponseHead) {
            defer { super.willWrite(head: &head) }

            let requestHead: HTTPRequestHead
            do {
                lock()
                defer { unlock() }

                switch _requestHead {
                case .none:
                    return
                case .some(let wrapped):
                    requestHead = wrapped
                }

                _requestHead = nil
            }


            struct Constants { static let connectionValues: Set = [ "keep-alive", "close" ] }


            let hasConnectionHeaders = requestHead.headers[canonicalForm: "connection"]
                .lazy.map { $0.lowercased() }
                .contains(where: Constants.connectionValues.contains(_:))

            guard !hasConnectionHeaders else { return }

            switch (requestHead.isKeepAlive, requestHead.version) {
            case (true, .http1_0):
                // In HTTP 1.0 connections are closed by default.
                // So when request has `keep-alive`, it should be mirrored in response.
                head.headers.add(name: "Connection", value: "keep-alive")
            case (false, .http1_1):
                // In HTTP 1.1 connections are not closed by default.
                // So when request has `close`, it should be mirrored in response.
                head.headers.add(name: "Connection", value: "close")
            default:
                break
            }
        }


        override func submit(_ response: Response) throws {
            guard let context = context else { throw KvError.inconsistency("Channel handler has no context") }

            context.eventLoop.execute { [weak self] in
                self?.channelWrite(response: response, http2StreamID: nil)
            }
        }

    }


    // MARK: .InternalChannelHandlerHttp2

    fileprivate class InternalChannelHandlerHttp2 : InternalChannelHandlerBase, KvHttpServerInternalChannelHandlerInit {

        required init(_ httpServer: KvHttpServer?) {
            super.init(httpServer, httpVersion: .http2)
        }


        // MARK: Opertions

        override func submit(_ response: Response) throws {
            guard let context = context else { throw KvError.inconsistency("Channel handler has no context") }

            context.eventLoop.execute { [weak self] in
                let channel = context.channel

                channel.getOption(HTTP2StreamChannelOptions.streamID)
                    .whenComplete { [weak self] result in
                        guard case .success(let streamID) = result else {
                            KvDebug.pause("Failed to get HTTP/2.0 stream ID channel option")
                            context.close(promise: nil)
                            return
                        }

                        self?.channelWrite(response: response, http2StreamID: String(Int(streamID)))
                    }
            }
        }

    }

}
