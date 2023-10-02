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
//  KvHttpChannel.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 23.06.2023.
//

import Foundation

import kvKit
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOSSL



// MARK: - KvHttpChannelDelegate

public protocol KvHttpChannelDelegate : AnyObject {

    func httpChannelDidStart(_ httpChannel: KvHttpChannel)

    func httpChannel(_ httpChannel: KvHttpChannel, didStopWith result: Result<Void, Error>)

    /// - Note: A client delegate should be provided to *httpClient* or the client should be disconnected.
    func httpChannel(_ httpChannel: KvHttpChannel, didStartClient httpClient: KvHttpChannel.Client)

    func httpChannel(_ httpChannel: KvHttpChannel, didStopClient httpClient: KvHttpChannel.Client, with result: Result<Void, Error>)

    func httpChannel(_ httpChannel: KvHttpChannel, didCatch error: Error)

}



// MARK: - KvHttpClientDelegate

public protocol KvHttpClientDelegate : AnyObject {

    /// - Returns: Request handler that will be passed with the request body bytes and will produce response.
    func httpClient(_ httpClient: KvHttpChannel.Client, requestHandlerFor requestHead: KvHttpServer.RequestHead) -> KvHttpRequestHandler?

    /// - Returns:  Optional custom response for an incident on a client.
    ///             If `nil` is returned then ``KvHttpIncident/defaultStatus`` is submitted to client.
    ///
    /// Use ``KvHttpIncident/defaultStatus`` to compose responses with default status codes for incidents.
    /// Also you can return custom responses depending on default status.
    ///
    /// - Note: Server will close connection to the client just after the response will be submitted.
    func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.ClientIncident) -> KvHttpResponseProvider?

    /// - Note: The client will be disconnected.
    func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error)

}



// MARK: - KvHttpChannel

/// HTTP channels listens for connections and handling connected clients.
open class KvHttpChannel {

    public typealias Response = KvHttpResponseProvider



    public let configuration: Configuration

    public weak var delegate: KvHttpChannelDelegate?


    /// Server the receiver is bound to.
    public internal(set) var server: KvHttpServer? {
        get { mutationLock.withLock { _server } }
        set { mutationLock.withLock { _server = newValue } }
    }



    @inlinable
    public init(with configuration: Configuration) {
        self.configuration = configuration
    }


    deinit {
        stop()
        waitUntilStopped()
    }



    private let mutationLock = NSRecursiveLock()


    /// - Warning: Access must be protected with `.mutationLock`.
    private weak var _server: KvHttpServer?


    /// - Warning: Access must be protected with `.stateCondition`.
    private var _state: InternalState = .stopped(.success(())) {
        didSet {
            guard State(for: _state) != State(for: oldValue) else { return }

            stateCondition.broadcast()
        }
    }

    private var stateCondition = NSCondition()



    // MARK: .Configuration

    public struct Configuration {

        public var endpoint: KvNetworkEndpoint

        public var http: HTTP

        public var connection: Connection


        /// - Parameter http: Configuration of HTTP protocol. If `nil` is passed then  ``Defaults``.``Defaults/http`` is used.
        @inlinable
        public init(endpoint: KvNetworkEndpoint, http: HTTP? = nil, connection: Connection? = nil) {
            self.endpoint = endpoint
            self.http = http ?? Defaults.http
            self.connection = connection ?? Connection()
        }


        /// - Parameter host: Host name or IP address to listen for connections at. If `nil` is passed then ``Defaults``.``Defaults/host`` is used.
        /// - Parameter http: Configuration of HTTP protocol. If `nil` is passed then ``Defaults``.``Defaults/http`` is used.
        @inlinable
        public init(host: String? = nil,
                    port: UInt16,
                    http: HTTP? = nil,
                    connection: Connection? = nil
        ) {
            self.init(endpoint: .init(host ?? Defaults.host, on: port), http: http, connection: connection)
        }


        // MARK: .Defaults

        public struct Defaults {

            @inlinable public static var host: String { "::1" }
            @inlinable public static var port: UInt16 { 80 }
            @inlinable public static var http: HTTP { .v1_1() }

            /// In seconds.
            @inlinable public static var connectionIdleTimeInterval: TimeInterval { 4.0 }
            @inlinable public static var connectionRequestLimit: UInt { 128 }

        }


        // MARK: .HTTP

        /// Configuration of HTTP protocol. E.g. version of HTTP protocol, sequrity settings.
        public enum HTTP : Hashable {

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

        public struct SSL : Hashable {

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

        public struct Connection : Equatable {

            @inlinable
            public var idleTimeInterval: TimeInterval {
                get { _idleTimeInterval ?? Defaults.connectionIdleTimeInterval }
                set { _idleTimeInterval = newValue }
            }
            @usableFromInline
            var _idleTimeInterval: TimeInterval?

            @inlinable
            var requestLimit: UInt {
                get { _requestLimit ?? Defaults.connectionRequestLimit }
                set { _requestLimit = newValue }
            }
            @usableFromInline
            var _requestLimit: UInt?


            /// - Parameter idleTimeInterval: If `nil` then ``KvHttpChannel/Configuration/Defaults/connectionIdleTimeInterval-swift.type.property`` is used.
            /// - Parameter requestLimit: If `nil` then ``KvHttpChannel/Configuration/Defaults/connectionRequestLimit-swift.type.property`` is used.
            @inlinable
            public init(idleTimeInterval: TimeInterval? = nil,
                        requestLimit: UInt? = nil)
            {
                self._idleTimeInterval = idleTimeInterval
                self._requestLimit = requestLimit
            }


            /// Initializes the result of merging *rhs* into *lhs*.
            @usableFromInline
            init(lhs: Self, rhs: Self) {
                self.init(idleTimeInterval: rhs._idleTimeInterval ?? lhs._idleTimeInterval,
                          requestLimit: rhs._requestLimit ?? lhs._requestLimit)
            }

        }

    }



    // MARK: .ChannelError

    public enum ChannelError : LocalizedError {

        /// Unable to perform a task due to reference to server is not valid. Probably channel is not bound to a server.
        case missingServer
        /// Unable to perform a task due to the server is not running.
        case serverIsNotRunning
        /// Unable to perform a task due to current channel's state doesn't meet the requirements. E.g. attempt to start a running channel.
        case unexpectedState(State)

    }



    // MARK: .State

    /// An enumeration of channel states.
    public enum State : Hashable {

        /// Channel has been successfully started and is processing connections.
        case running
        /// Channel is performing initialization but is not ready to processing connections.
        case starting
        /// Channel is stopped.
        case stopped
        /// Channel is performing shutdown tasks.
        case stopping


        init(for internalState: InternalState) {
            switch internalState {
            case .running:
                self = .running
            case .starting:
                self = .starting
            case .stopped:
                self = .stopped
            case .stopping:
                self = .stopping
            }
        }

    }



    // MARK: .InternalState

    enum InternalState {
        case running(listeningChannel: Channel)
        case starting
        /// Associated type is result of last stop operation.
        case stopped(Result<Void, Error>)
        case stopping
    }



    // MARK: Managing Life-cycle

    /// Removes the receiver from server the receiver is bound to. Channel will be stopped.
    ///
    /// See: ``waitUntilStopped()``.
    public func removeFromServer() {
        server?.removeChannel(self)
    }


    /// Channel have to be registered on a server.
    ///
    /// See: ``waitWhileStarting()``.
    func start() {

        final class ErrorHandler : ChannelInboundHandler {

            init(_ controller: KvHttpChannel?) {
                self.controller = controller
            }


            private weak var controller: KvHttpChannel?


            typealias InboundIn = Never


            func errorCaught(context: ChannelHandlerContext, error: Error) {
                guard let controller = controller else { return NSLog("[KvHttpChannel] Error: \(error)") }

                controller.delegate?.httpChannel(controller, didCatch: error)

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


        func ConfigureHttp1(_ controller: KvHttpChannel?, channel: Channel, channelHandler: InternalChannelHandler) -> EventLoopFuture<Void> {
            channelHandler.httpVersion = .http1_1

            return channel.pipeline.configureHTTPServerPipeline().flatMap { _ in
                channel.pipeline.addHandlers([
                    channelHandler,
                    ErrorHandler(controller),
                ])
            }
        }


        func ConfigureHttp2(_ controller: KvHttpChannel?, channel: Channel, channelHandler: InternalChannelHandler) -> EventLoopFuture<Void> {
            channelHandler.httpVersion = .http2

            let errorHandler = ErrorHandler(controller)

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


        let eventLoopGroup: MultiThreadedEventLoopGroup

        do {
            eventLoopGroup = try mutationLock.withLock {
                guard let server = _server else { throw ChannelError.missingServer }
                guard let eventLoopGroup = server.eventLoopGroup else { throw ChannelError.serverIsNotRunning }

                return eventLoopGroup
            }

            try stateCondition.withLock {
                guard case .stopped = _state else { throw ChannelError.unexpectedState(.init(for: _state)) }

                _state = .starting
            }
        }
        catch {
            delegate?.httpChannel(self, didCatch: error)
            return
        }

        do {
            let configuration = configuration
            let sslContext = try MakeSslContext(configuration.http)

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

                        self?.delegate?.httpChannel(self!, didStartClient: channelHandler)

                        channel.closeFuture.whenComplete { [weak self] result in
                            self?.delegate?.httpChannel(self!, didStopClient: channelHandler, with: result)
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

            bootstrap
                .bind(host: configuration.endpoint.address, port: numericCast(configuration.endpoint.port))
                .whenComplete { [weak self] in
                    self?.didCompleteListeningChannel(with: $0)
                }
        }
        catch {
            delegate?.httpChannel(self, didCatch: error)

            stateCondition.withLock {
                _state = .stopped(.failure(error))
            }
            return
        }
    }


    private func didCompleteListeningChannel(with result: Result<Channel, Error>) {
        do {
            let listeningChannel = try result.get()

            listeningChannel.closeFuture.whenComplete { [weak self] in
                self?.handleStopOfListeningChannel(with: $0)
            }

            stateCondition.withLock {
                _state = .running(listeningChannel: listeningChannel)
            }

            delegate?.httpChannelDidStart(self)
        }
        catch {
            delegate?.httpChannel(self, didCatch: error)

            stateCondition.withLock {
                _state = .stopped(.failure(error))
            }
            return
        }
    }


    /// This method is called by server.
    ///
    /// See: ``waitUntilStopped()``.
    func stop() {

        func CurrentListeningChannel() -> Channel? {
            return stateCondition.withLock {
                // `while true` is used to prevent recursion.
                while true {
                    switch _state {
                    case .running(let listeningChannel):
                        _state = .stopping
                        return listeningChannel

                    case .starting, .stopping:
                        stateCondition.wait()

                    case .stopped(_):
                        return nil
                    }
                }
            }
        }


        guard let listeningChannel = CurrentListeningChannel() else { return }

        // - Note: Close result is handled in completion handler of the channel's `.closeFuture`.
        listeningChannel.close(promise: nil)
    }


    private func handleStopOfListeningChannel(with result: Result<Void, Error>) {
        stateCondition.withLock {
            _state = .stopped(result)
        }

        delegate?.httpChannel(self, didStopWith: result)
    }


    /// This method stops execution until channel is started or stopeed and then returns the result.
    ///
    /// - Note: If the channel's status is not *.running* or *.stopped* then method just returns success or result of last stop.
    ///
    /// See: ``waitUntilStopped()``.
    @discardableResult
    public func waitWhileStarting() -> Result<Void, Error> {
        stateCondition.withLock {
            while true {
                switch _state {
                case .starting, .stopping:
                    stateCondition.wait()

                case .running:
                    return .success(())

                case .stopped(let result):
                    return result
                }
            }
        }
    }


    /// This method stops execution until channel is stopped and then returns result of stop.
    ///
    /// - Note: If the channel is stopped then method just returns result of last stop.
    ///
    /// See: ``waitWhileStarting()``.
    @discardableResult
    public func waitUntilStopped() -> Result<Void, Error> {
        stateCondition.withLock {
            while true {
                switch _state {
                case .running, .starting, .stopping:
                    stateCondition.wait()

                case .stopped(let result):
                    return result
                }
            }
        }
    }



    // MARK: State

    /// Current state of the channel.
    ///
    /// - Note: This property is thread-safe so costs of mutual exclusion should be taken into account.
    public var state: State { stateCondition.withLock { .init(for: _state) } }


    /// An address new connections are listened at on local machine or in local network.
    ///
    /// - Note: This property is thread-safe so costs of mutual exclusion should be taken into account.
    public var localAddress: SocketAddress? {
        guard case .running(let listeningChannel) = stateCondition.withLock({ _state }) else { return nil }

        return listeningChannel.localAddress
    }


    /// URLs the receiver is available at on local machine or in local networks.
    ///
    /// - Note: This property is thread-safe so costs of mutual exclusion should be taken into account.
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


        // The local address.
        switch localAddress {
        case .unixDomainSocket:
            AddEndpoint(absoluteString: "\(localAddress)")
        case .v4, .v6:
            AddEndpoint(host: localAddress.ipAddress)
        }

        return endpointURLs
    }



    // MARK: .ClientIncident

    /// Client specific incidents.
    ///
    /// - Note: Server closes connections with clients after incidents.
    ///
    /// See ``KvHttpClientDelegate/httpClient(_:didCatch:)-9mlo3`` to override responses for incidents.
    public enum ClientIncident : KvHttpChannelIncident {

        /// This incident is emitted when client's delegate returns no handler for a request.
        /// By default `.notFound` (404) status is returned.
        case noRequestHandler


        // MARK: : KvHttpChannelIncident

        /// Default HTTP status code submitted to a client when incident occurs.
        @inlinable
        public var defaultStatus: KvHttpResponseProvider.Status {
            switch self {
            case .noRequestHandler:
                return .notFound
            }
        }


        // MARK: Operations

        fileprivate func response(client: KvHttpChannel.Client) -> KvHttpResponseProvider {
            client.delegate?.httpClient(client, didCatch: self) ?? .status(defaultStatus)
        }

    }



    // MARK: .RequestIncident

    /// Request specific incidents.
    ///
    /// - Note: Server closes connections with clients after incidents.
    ///
    /// See ``KvHttpClientDelegate/httpClient(_:didCatch:)-9mlo3`` to override responses for incidents.
    public enum RequestIncident : KvHttpChannelIncident {

        /// This incident is emitted when a request exceeds provided or default limit for a body.
        /// See ``KvHttpRequestHandler/bodyLengthLimit``, ``KvResponseGroup/httpBodyLengthLimit(_:)``, ``KvHttpRequestRequiredBody/bodyLengthLimit(_:)``.
        /// By default `.payloadTooLarge` (413) status is returned.
        case byteLimitExceeded
        /// This incident is emitted when request handler returns `nil` response from ``KvHttpRequestHandler/httpClientDidReceiveEnd(_:)`` method.
        /// By default `.notFound` (404) status is returned.
        case noResponse


        // MARK: : KvHttpChannelIncident

        /// Default HTTP status code submitted to a client when incident occurs.
        @inlinable
        public var defaultStatus: KvHttpResponseProvider.Status {
            switch self {
            case .byteLimitExceeded:
                return .payloadTooLarge
            case .noResponse:
                return .notFound
            }
        }


        // MARK: Operations

        fileprivate func response(client: KvHttpChannel.Client, requestHandler: KvHttpRequestHandler) -> KvHttpResponseProvider {
            requestHandler.httpClient(client, didCatch: self) ?? .status(defaultStatus)
        }

    }



    // MARK: .Client

    public class Client {

        public typealias RequestPart = HTTPServerRequestPart


        public weak var delegate: KvHttpClientDelegate?

        public fileprivate(set) weak var httpChannel: KvHttpChannel? {
            get { withLock { _httpChannel } }
            set { withLock { _httpChannel = newValue } }
        }

        public var userInfo: Any? {
            get { withLock { _userInfo } }
            set { withLock { _userInfo = newValue } }
        }

        public var requestLimit: UInt {
            get { withLock { _requestLimit } }
            set { withLock { _requestLimit = newValue } }
        }

        fileprivate weak var channel: Channel?


        fileprivate init(_ httpChannel: KvHttpChannel?) {
            _httpChannel = httpChannel
            _requestLimit = httpChannel?.configuration.connection.requestLimit ?? 0
        }


        private let mutationLock = NSRecursiveLock()

        /// - Warning: Access to this property must be protected with .mutationLock.
        private weak var _httpChannel: KvHttpChannel?
        /// - Warning: Access to this property must be protected with .mutationLock.
        private var _userInfo: Any?
        /// - Warning: Access to this property must be protected with .mutationLock.
        fileprivate var _requestLimit: UInt


        // MARK: Operations

        /// Closes connection to the receiver.
        public func disconnect() { disconnect(nil) }

        /// Closes connection via context if avialble.
        @usableFromInline
        internal func disconnect(_ context: ChannelHandlerContext?) {
            context?.close(promise: nil)
            ?? channel?.close(promise: nil)
        }


        // MARK: Locking

        fileprivate func withLock<R>(_ body: () throws -> R) rethrows -> R { try mutationLock.withLock(body) }

        fileprivate func lock() { mutationLock.lock() }

        fileprivate func unlock() { mutationLock.unlock() }

    }



    // MARK: .InternalChannelHandler

    /// - Note: Private additions to public ``Client`` class.
    fileprivate final class InternalChannelHandler : Client, ChannelInboundHandler {

        var httpVersion: HTTPVersion {
            get { withLock { _httpVersion } }
            set { withLock { _httpVersion = newValue } }
        }


        init(_ httpChannel: KvHttpChannel?, httpVersion: HTTPVersion) {
            self._httpVersion = httpVersion

            super.init(httpChannel)
        }


        deinit {
            withLock {
                _responseBuffer.clear()
            }
        }


        /// - Warning: Access must be protected by ``ChannelHandler``'s locking methods.
        private var _httpVersion: HTTPVersion


        /// A dispatch queue to process received requests.
        private let dispatchQueue: DispatchQueue = .init(label: "Channel Response Queue", target: .global())


        private var requestProcessingState: RequestProcessingState = .idle


        /// Number of requests the responses have not been completely sent.
        ///
        /// - Warning: Access must be protected by ``ChannelHandler``'s locking methods.
        private var _activeRequestCount: UInt = 0 {
            didSet {
                switch (_activeRequestCount > 0, oldValue > 0) {
                case (true, false):
                    withLock { _idleTimeoutTask = nil }
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
            willSet { withLock { _idleTimeoutTask?.cancel() } }
        }

        /// - Warning: Access must be protected by ``ChannelHandler``'s locking methods.
        private var _responseBuffer: ByteBuffer = {
            var buffer = ByteBuffer()
            buffer.reserveCapacity(minimumWritableBytes: Constants.responseBufferCapacity)
            return buffer
        }()


        // MARK: .Constants

        private struct Constants {

            static var responseBufferCapacity: Int { 1 << 14 }

            static let connectionHeaderValues: Set<String> = [ "keep-alive", "close" ]

        }


        // MARK: Operations

        private func processIncident(_ incident: ClientIncident, context: ChannelHandlerContext, httpVersion: HTTPVersion, keepAlive: Bool?) {
            processIncident(incident,
                            context: context,
                            httpVersion: httpVersion,
                            keepAlive: keepAlive,
                            responseBlock: { $0.response(client: self) })
        }


        private func processIncident(_ incident: RequestIncident, in channelContext: ChannelHandlerContext, _ requestContext: RequestContext ) {
            processIncident(incident,
                            context: channelContext,
                            httpVersion: requestContext.httpVersion,
                            keepAlive: requestContext.keepAlive,
                            responseBlock: { $0.response(client: self, requestHandler: requestContext.handler) })
        }


        private func processIncident<I>(_ incident: I,
                                        context: ChannelHandlerContext,
                                        httpVersion: HTTPVersion,
                                        keepAlive: Bool?,
                                        responseBlock: @escaping (I) -> KvHttpResponseProvider?
        ) where I : KvHttpChannelIncident {
            requestProcessingState = .stopped

            dispatchQueue.async {
                let response = (responseBlock(incident) ?? .status(incident.defaultStatus))
                    .needsDisconnect()  // Clients are always disconnected after incidents.

                self.channelWrite(response, context: context, httpVersion: httpVersion, keepAlive: keepAlive)
            }
        }


        private func channelWrite(_ response: Response, in channelContext: ChannelHandlerContext, _ requestContext: RequestContext) {
            channelWrite(response, context: channelContext, httpVersion: requestContext.httpVersion, keepAlive: requestContext.keepAlive)
        }


        /// - Parameter keepAlive:  An optional boolean value indicating whether `keep-alive` or `close` value is set for `Connection` header.
        ///                         Note that it's handled differently depending on version of HTTP protocol.
        ///
        /// - Note: This method decreases `_activeRequestCount`.
        private func channelWrite(_ response: Response, context: ChannelHandlerContext, httpVersion: HTTPVersion, keepAlive: Bool?) {
            context.eventLoop.execute {
                let channel = context.channel

                let headers: HTTPHeaders = {
                    var headers = HTTPHeaders()

                    if let contentType = response.contentType {
                        headers.add(name: "Content-Type", value: contentType.value)
                    }
                    if let contentLength = response.contentLength {
                        headers.add(name: "Content-Length", value: String(contentLength))
                    }

                    response.customHeaderCallback?(&headers)

                    return headers
                }()

                // Head
                let head: HTTPResponseHead = {
                    var head = HTTPResponseHead(version: httpVersion, status: response.status, headers: headers)

                    if let keepAlive = keepAlive {
                        head.headers.add(name: "Connection", value: keepAlive ? "close" : "keep-alive")
                    }

                    channel.write(self.wrapOutboundOut(HTTPServerResponsePart.head(head)), promise: nil)

                    return head
                }()

                // Body
                if let bodyCallback = response.bodyCallback {
                    do {
                        try self.withLock {
                            while true {
                                self._responseBuffer.clear(minimumCapacity: Constants.responseBufferCapacity)

                                let bytesRead = try self._responseBuffer.writeWithUnsafeMutableBytes(minimumWritableBytes: 0) { dest in
                                    try bodyCallback(dest).get()
                                }

                                guard bytesRead > 0 else { break }

                                channel.writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.body(.byteBuffer(self._responseBuffer))), promise: nil)
                            }
                        }
                    }
                    catch { self.delegate?.httpClient(self, didCatch: error) }
                }

                // End
                do {
                    channel
                        .writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.end(nil)))
                        .whenComplete { _ in
                            let needsDisconnect: Bool = self.withLock {
                                self._activeRequestCount -= 1

                                return (response.options.contains(.needsDisconnect)
                                        || keepAlive == false
                                        || !head.isKeepAlive
                                        || self.channel?.isActive != true
                                        || (self._activeRequestCount <= 0 && (self._isIdleTimerFired || self._requestLimit <= 0)))
                            }

                            if needsDisconnect {
                                self.disconnect(context)
                            }
                        }
                }
            }
        }


        private func startIdleTimeoutTask() {
            withLock {
                guard !_isIdleTimerFired,
                      let eventLoop = channel?.eventLoop,
                      let idleTimeInterval = httpChannel?.configuration.connection.idleTimeInterval
                else { return }

                _idleTimeoutTask = eventLoop.scheduleTask(in: .nanoseconds(.init(idleTimeInterval * 1e9))) { [weak self] in
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
            if withLock({ _activeRequestCount <= 0 }) {
                startIdleTimeoutTask()
            }
        }


        func handlerRemoved(context: ChannelHandlerContext) { }


        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            switch unwrapInboundIn(data) {
            case .head(let head):
                handleRequestHead(head, in: context)

            case .body(var byteBuffer):
                handleRequestBodyBytes(&byteBuffer, in: context)

            case .end(_):
                handleRequestEnd(in: context)
            }
        }


        func errorCaught(context: ChannelHandlerContext, error: Error) {
            switch requestProcessingState {
            case .idle:
                delegate?.httpClient(self, didCatch: error)

            case .processing(let requestContext):
                requestContext.handler.httpClient(self, didCatch: error)

            case .stopped:
                // Swift-NIO emits some errors when server discards client. So these errors are suppressed in `.stopped` state.
                switch error {
                case HTTPParserError.invalidEOFState:
                    return
                case let error as NIOHTTP2Errors.StreamClosed where error.errorCode == .cancel:
                    return
                default:
                    break
                }

                delegate?.httpClient(self, didCatch: error)
            }

            disconnect(context)
        }


        private func handleRequestHead(_ head: HTTPRequestHead, in context: ChannelHandlerContext) {

            func ExtractKeepAlive(_ head: HTTPRequestHead) -> Bool? {

                func HasConnectionHeaders(_ head: HTTPRequestHead) -> Bool {
                    head.headers[canonicalForm: "connection"]
                        .lazy.map { $0.lowercased() }
                        .contains(where: Constants.connectionHeaderValues.contains(_:))
                }


                // Handling of `connection` header.
                switch head.version {
                case .http1_0:
                    // In HTTP 1.0 connections are closed by default. So when request has `keep-alive`, it should be mirrored in response.
                    return HasConnectionHeaders(head) && head.isKeepAlive ? true : nil

                case .http1_1:
                    // In HTTP 1.1 connections are not closed by default. So when request has `close`, it should be mirrored in response.
                    return HasConnectionHeaders(head) && !head.isKeepAlive ? false : nil

                default:
                    return nil
                }
            }


            switch requestProcessingState {
            case .idle:
                break   // OK
            case .processing(_):
                KvDebug.pause("Warning: new request is received but actual request is not complete")
            case .stopped:
                return  // Requests are ignored
            }

            let httpVersion: HTTPVersion
            do {
                lock()
                defer { unlock() }

                guard _requestLimit > 0 else {
                    // It is not threated as incident due to channel will close connection just after the last response.
                    // So response on incident will not be sent.
                    //
                    // Also `_requestLimit` is not decresed in ``handleRequestEnd(in:)`` to minimize locking of the handler.
                    requestProcessingState = .stopped
                    return
                }

                _requestLimit -= 1
                _activeRequestCount += 1

                httpVersion = _httpVersion
            }

            let keepAlive = ExtractKeepAlive(head)

            guard let requestHandler = delegate?.httpClient(self, requestHandlerFor: head)
            else { return processIncident(.noRequestHandler, context: context, httpVersion: httpVersion, keepAlive: keepAlive) }

            let bodyLengthLimit = requestHandler.bodyLengthLimit

            switch head.headers.first(name: "Content-Length").flatMap(UInt.init(_:)) {
            case .none:
                break
            case .some(let contentLength):
                guard contentLength <= bodyLengthLimit else {
                    return processIncident(RequestIncident.byteLimitExceeded, context: context, httpVersion: httpVersion, keepAlive: keepAlive) {
                        $0.response(client: self, requestHandler: requestHandler)
                    }
                }
            }

            requestProcessingState = .processing(.init(httpVersion: httpVersion,
                                                       handler: requestHandler,
                                                       bodyLengthLimit: bodyLengthLimit,
                                                       keepAlive: keepAlive))
        }


        private func handleRequestBodyBytes(_ byteBuffer: inout ByteBuffer, in context: ChannelHandlerContext) {
            switch requestProcessingState {
            case .processing(var requestContext):
                guard requestContext.bodyLengthLimit >= byteBuffer.readableBytes else { return processIncident(.byteLimitExceeded, in: context, requestContext) }

                let bytesRead: UInt = numericCast(byteBuffer.readWithUnsafeReadableBytes { pointer in
                    requestContext.handler.httpClient(self, didReceiveBodyBytes: pointer)
                    return pointer.count
                })

                assert(requestContext.bodyLengthLimit >= bytesRead)

                requestContext.bodyLengthLimit -= bytesRead

                requestProcessingState = .processing(requestContext)

            case .stopped:
                return  // Requests are ignored

            case .idle:
                return KvDebug.pause("Warning: request body is received while new request is being waited")
            }
        }


        private func handleRequestEnd(in context: ChannelHandlerContext) {
            switch requestProcessingState {
            case .processing(let requestContext):
                dispatchQueue.async {
                    guard let response = requestContext.handler.httpClientDidReceiveEnd(self)
                    else { return self.processIncident(.noResponse, in: context, requestContext) }

                    self.channelWrite(response, in: context, requestContext)
                }

                requestProcessingState = .idle

            case .stopped:
                return  // Requests are ignored

            case .idle:
                return KvDebug.pause("Warning: end of request is received while new request is being waited")
            }
        }


        // MARK: .RequestProcessingState

        private enum RequestProcessingState {
            /// Waiting for a request
            case idle
            /// Processing a request. Waiting for body bytes or the end.
            case processing(RequestContext)
            /// Requests are ignored. E.g. channel handler is in this state after an incident.
            case stopped
        }


        // MARK: .RequestContext

        /// It's used to hold a request related data and process it at once when needed.
        private struct RequestContext {

            let httpVersion: HTTPVersion

            /// Handler of a request.
            let handler: KvHttpRequestHandler

            /// Maximum number of bytes current request handler can process Number of received bytes passed to current `.requestHandler`.
            var bodyLengthLimit: UInt

            /// An optional boolean value indicating whether `keep-alive` or `close` value is set for `Connection` header.
            /// Also it's used to disconnect after submission of response.
            ///
            /// - Note: Actually `Connection` header is submitted in HTTP1 only.
            var keepAlive: Bool?

        }

    }

}



// MARK: : Identifiable

extension KvHttpChannel : Identifiable {

    @inlinable
    public var id: ObjectIdentifier { .init(self) }

}



// MARK: - KvHttpChannelIncident

/// A protocol all channel incidents conform to.
///
/// - Note: Server immediately closes a connection to a client after any channel incident.
public protocol KvHttpChannelIncident : KvHttpIncident { }



// MARK: - ChannelHandlerContext Extenstions

extension ChannelHandlerContext : Hashable {

    // MARK: : Equatable

    public static func ==(lhs: ChannelHandlerContext, rhs: ChannelHandlerContext) -> Bool { lhs === rhs }


    // MARK: : Hashable

    public func hash(into hasher: inout Hasher) { ObjectIdentifier(self).hash(into: &hasher) }

}
