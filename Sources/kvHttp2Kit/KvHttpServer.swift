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



public protocol KvHttpServerDelegate : class {

    func httpServerDidStart(_ httpServer: KvHttpServer)

    func httpServer(_ httpServer: KvHttpServer, didStopWith result: Result<Void, Error>)

    func httpServer(_ httpServer: KvHttpServer, didStart httpChannelhandler: KvHttpServer.ChannelHandler)

    func httpServer(_ httpServer: KvHttpServer, didCatch error: Error)

}



public protocol KvHttpChannelHandlerDelegate : class {

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

        public var ssl: SSL



        public init(host: String = Defaults.host, port: Int, ssl: SSL) {
            self.host = host
            self.port = port
            self.ssl = ssl
        }



        // MARK: Defaults

        public struct Defaults {

            public static let host: String = "::1"

        }



        // MARK: SSL

        public struct SSL {

            public var privateKey: NIOSSLPrivateKey
            public var certificateChain: [NIOSSLCertificate]



            public init(privateKey: NIOSSLPrivateKey, certificateChain: [NIOSSLCertificate]) {
                self.privateKey = privateKey
                self.certificateChain = certificateChain
            }

        }

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
                guard let server = server else {
                    return NSLog("[KvHttpServer] Error: \(error)")
                }

                server.delegate?.httpServer(server, didCatch: error)
            }

        }


        try KvThreadKit.locking(mutationLock) {
            guard !isStarted else { return }

            let tlsConfiguration = TLSConfiguration.forServer(certificateChain: configuration.ssl.certificateChain.map { .certificate($0) },
                                                              privateKey: .privateKey(configuration.ssl.privateKey),
                                                              applicationProtocols: NIOHTTP2SupportedALPNProtocols)
            // Configure the SSL context that is used by all SSL handlers.
            let sslContext = try NIOSSLContext(configuration: tlsConfiguration)

            let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

            let bootstrap = ServerBootstrap(group: eventLoopGroup)
                .serverChannelOption(ChannelOptions.backlog, value: 256)
                .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)

                .childChannelInitializer({ [weak self] channel in
                    channel.pipeline.addHandler(NIOSSLServerHandler(context: sslContext)).flatMap { [weak self] in
                        channel.configureHTTP2Pipeline(mode: .server) { [weak self] streamChannel in
                            streamChannel.pipeline.addHandler(HTTP2FramePayloadToHTTP1ServerCodec()).flatMap { [weak self] in
                                streamChannel.pipeline.addHandler(InternalChannelHandler(self))
                            }.flatMap { [weak self] in
                                streamChannel.pipeline.addHandler(ErrorHandler(self))
                            }
                        }
                    }.flatMap { [weak self] (_: HTTP2StreamMultiplexer) in
                        channel.pipeline.addHandler(ErrorHandler(self))
                    }
                })

                // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
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



// MARK: : .ChannelHandler

extension KvHttpServer {

    public class ChannelHandler {

        public typealias RequestPart = HTTPServerRequestPart



        public weak var delegate: KvHttpChannelHandlerDelegate?

        public fileprivate(set) weak var httpServer: KvHttpServer!


        public var userInfo: Any?



        fileprivate init(_ httpServer: KvHttpServer?) {
            self.httpServer = httpServer

            httpServer?.delegate?.httpServer(httpServer!, didStart: self)
        }



        fileprivate weak var context: ChannelHandlerContext?



        public func submit(_ response: Response) throws { throw KvError.inconsistency("implementation for \(#function) is missing") }

    }



    fileprivate class InternalChannelHandler : ChannelHandler, ChannelInboundHandler {

        override func submit(_ response: Response) throws {
            guard let context = context else { throw KvError.inconsistency("channel handler has no context") }

            context.eventLoop.execute { [weak self] in
                context.channel.getOption(HTTP2StreamChannelOptions.streamID).flatMap({ [weak self] (streamID) -> EventLoopFuture<Void> in

                    func DataBuffer(_ data: Data) -> ByteBuffer {
                        var buffer = context.channel.allocator.buffer(capacity: data.count)

                        buffer.writeBytes(data)

                        return buffer
                    }


                    guard let channelHandler = self else { return context.close() }

                    let (contentType, contentLength, buffer): (String, UInt64, ByteBuffer) = {
                        switch response {
                        case .json(let data):
                            return ("application/json; charset=utf-8", numericCast(data.count), DataBuffer(data))
                        }
                    }()


                    let headers: HTTPHeaders = [ "Content-Type": contentType,
                                                 "Content-Length": String(contentLength),
                                                 "x-stream-id": String(Int(streamID)), ]

                    context.channel.write(channelHandler.wrapOutboundOut(HTTPServerResponsePart.head(HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok, headers: headers))), promise: nil)
                    context.channel.write(channelHandler.wrapOutboundOut(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)

                    return context.channel.writeAndFlush(channelHandler.wrapOutboundOut(HTTPServerResponsePart.end(nil)))

                }).whenComplete { _ in
                    context.close(promise: nil)
                }
            }
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

            delegate?.httpChannelHandler(self, didReceive: unwrapInboundIn(data))
        }



        func errorCaught(context: ChannelHandlerContext, error: Error) {
            assert(self.context == context)

            delegate?.httpChannelHandler(self, didCatch: error)
        }

    }

}
