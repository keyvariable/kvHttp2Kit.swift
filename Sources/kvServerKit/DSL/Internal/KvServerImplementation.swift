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
//  KvServerImplementation.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 23.06.2023.
//

import kvKit



class KvServerImplementation {

    init<S : KvServer>(from declaration: S) {
        let httpScheme = HttpScheme()

        declaration.body.resolvedGroup.insertResponses(to: httpScheme.makeAccumulator())

        httpServer = .init()

        httpScheme.forEachChannel { channelScheme in
            switch channelScheme {
            case let httpChannelScheme as HttpScheme.HttpChannel:
                httpServer.createChannel(httpChannelScheme)

            default:
                KvDebug.pause("Unable to create a channel from unexpected \(channelScheme) scheme")
            }
        }
    }


    private let httpServer: HttpServer



    // MARK: Managing Life-cycle

    func start() throws {
        try httpServer.start()
    }


    func stop(_ completion: ((Result<Void, Error>) -> Void)? = nil) {
        httpServer.stop(completion)
    }


    /// Waits until server and all it's channels are starting.
    @discardableResult
    public func waitWhileStarting() -> Result<Void, Error> {
        httpServer.waitWhileStarting()
    }


    @discardableResult
    func waitUntilStopped() -> Result<Void, Error> {
        httpServer.waitUntilStopped()
    }

}



// MARK: .HttpScheme.ChannelScheme

fileprivate protocol KvServerImplementationChannelScheme : AnyObject {

    /// - Returns: The receiver's clone with dropped endpoints.
    func drop(_ endpoints: Set<KvNetworkEndpoint>) -> Self

}


extension KvServerImplementation.HttpScheme {

    fileprivate typealias ChannelScheme = KvServerImplementationChannelScheme

}



extension KvServerImplementation {

    // MARK: .HttpScheme

    fileprivate class HttpScheme {

        typealias HttpEndpoints = KvResponseGroup.Configuration.Network.HttpEndpoints


        private var channels: Channels = .init()


        // MARK: Operations

        func makeAccumulator() -> Accumulator { Accumulator(self) }


        func httpChannels(for configuration: KvResponseGroup.Configuration?) -> [HttpChannel] {
            channels.httpChannels(for: configuration)
        }


        func forEachChannel(_ body: (ChannelScheme) -> Void) {
            channels.elements.values.forEach(body)
        }


        // MARK: .Accumulator

        class Accumulator : KvHttpResponseAccumulator {

            weak var scheme: HttpScheme!

            let responseGroupConfiguration: KvResponseGroup.Configuration?

            let httpChannels: [HttpChannel]


            init(_ scheme: HttpScheme, configuration: KvResponseGroup.Configuration? = nil, httpChannels: [HttpChannel]? = nil) {
                self.scheme = scheme
                self.responseGroupConfiguration = configuration
                self.httpChannels = httpChannels ?? scheme.httpChannels(for: responseGroupConfiguration)

                updateSchemeNode()
            }


            // MARK: : KvHttpResponseAccumulator

            func with(_ configuration: KvResponseGroup.Configuration, body: (Accumulator) -> Void) {
                let newConfiguration = KvResponseGroup.Configuration.overlay(configuration, over: self.responseGroupConfiguration)

                let isHttpConfigurationChanged = newConfiguration.network.httpEndpoints != self.responseGroupConfiguration?.network.httpEndpoints

                let accumulator = Accumulator(scheme,
                                              configuration: newConfiguration,
                                              httpChannels: isHttpConfigurationChanged ? nil : httpChannels)

                body(accumulator)
            }


            func insert<HttpResponse>(_ response: HttpResponse)
            where HttpResponse : KvHttpResponseImplementationProtocol
            {
                forEachDispatchScheme { $0.insert(response, for: responseGroupConfiguration?.dispatching ?? .empty) }
            }


            // MARK: Operations

            @inline(__always)
            private func forEachDispatchScheme(_ body: (KvHttpResponseDispatcher.Scheme) -> Void) {
                httpChannels.forEach { body($0.dispatchScheme) }
            }


            private func updateSchemeNode() {
                guard let responseGroupConfiguration,
                      let attributes = KvHttpResponseDispatcher.Attributes.from(responseGroupConfiguration)
                else { return }

                forEachDispatchScheme { $0.insert(attributes, for: responseGroupConfiguration.dispatching) }
            }

        }


        // MARK: .Channels

        private struct Channels {

            typealias EndpointGroup = Set<KvNetworkEndpoint>
            typealias Channels = [EndpointGroup : ChannelScheme]


            private(set) var elements: Channels = .init()


            private typealias HTTP = KvHttpChannel.Configuration.HTTP


            private var endpointGroups: [EndpointGroup.Element : EndpointGroup] = .init()


            // MARK: .Defaults

            private struct Defaults {

                static var httpEndpoints: HttpEndpoints = [ KvNetworkEndpoint(HTTP.host, on: HTTP.port) : .default ]


                private typealias HTTP = KvHttpChannel.Configuration.Defaults

            }


            // MARK: Operations

            private mutating func fetch<C>(for endpoints: EndpointGroup, fabric: (EndpointGroup) -> C) -> [C]
            where C : ChannelScheme
            {
                guard !endpoints.isEmpty else {
                    KvDebug.pause("Attempt to create a channel for empty group of endpoints. The responses will be ignored")
                    return [ ]
                }

                // First channel.
                guard !elements.isEmpty else {
                    let channel = fabric(endpoints)

                    elements[endpoints] = channel

                    return [ channel ]
                }

                // Exact match case.
                switch elements[endpoints] {
                case .some(let channel):
                    guard let channel = channel as? C else {
                        KvDebug.pause("Incompatible channel types (expected: \(C.self), existing: \(type(of: channel))) for \(endpoints) endpoints. The responses are ignored")
                        return [ ]
                    }
                    return [ channel ]

                case .none:
                    // There is no exact match so merging algorithm is performed.
                    break
                }

                // Merge argorithm.
                do {
                    var endpoints = endpoints
                    /// Mutations are collected to prevent mutation of `channels` while it's iterated.
                    var diff: (deletions: [Channels.Key], insertions: [Channels.Element]) = ([ ], [ ])

                    var result: [C] = .init()
                    var iterator = elements.makeIterator()

                    while !endpoints.isEmpty,
                          let (channelEndpoints, channel) = iterator.next()
                    {
                        let commonEndpoints = channelEndpoints.intersection(endpoints)

                        guard !commonEndpoints.isEmpty else { continue }
                        guard let channel = channel as? C else {
                            KvDebug.pause("Incompatible channel types (expected: \(C.self), existing: \(type(of: channel))) for common \(commonEndpoints) endpoints. The responses on these endpoints are ignored")
                            continue
                        }

                        /// Elements of `channelEndpoints` those are out of `endpoints`.
                        let outterEndpoints = channelEndpoints.subtracting(endpoints)

                        switch outterEndpoints.isEmpty {
                        case false:
                            let newChannel: C = channel.drop(outterEndpoints)

                            result.append(newChannel)

                            diff.deletions.append(channelEndpoints)
                            diff.insertions.append((commonEndpoints, newChannel))
                            diff.insertions.append((outterEndpoints, channel))

                        case true:
                            result.append(channel)
                        }

                        endpoints.subtract(commonEndpoints)
                    }

                    diff.deletions.forEach {
                        elements.removeValue(forKey: $0)
                    }
                    elements.merge(diff.insertions, uniquingKeysWith: { _, new in new })

                    if !endpoints.isEmpty {
                        let channel = fabric(endpoints)

                        elements[endpoints] = channel
                        result.append(channel)
                    }

                    return result
                }
            }


            mutating func httpChannels(for configuration: KvResponseGroup.Configuration?) -> [HttpChannel] {
                let endpoints = {
                    $0?.isEmpty == false ? $0! : Defaults.httpEndpoints
                }(configuration?.network.httpEndpoints)

                return fetch(for: endpoints.elements, fabric: { slice in
                    HttpChannel(for: endpoints.intersection(slice))
                })
            }

        }


        // MARK: .HttpChannel

        final class HttpChannel : ChannelScheme {

            private(set) var configurations: HttpEndpoints.Configurations

            let dispatchScheme: HttpServer.ChannelController.Dispatcher.Scheme


            private init(
                configurations: [KvNetworkEndpoint : HttpEndpoints.Configuration] = [:],
                dispatchScheme: HttpServer.ChannelController.Dispatcher.Scheme = .init()
            ) {
                self.configurations = configurations
                self.dispatchScheme = dispatchScheme
            }


            init(for httpEndpoints: HttpEndpoints) {
                self.configurations = httpEndpoints.configurations
                self.dispatchScheme = .init()
            }


            // MARK: : ChannelScheme

            func drop(_ endpoints: Set<KvNetworkEndpoint>) -> HttpChannel {
                assert(!endpoints.isEmpty, "There is no need to call .drop() method for empty argument")

                let dropped = HttpChannel(configurations: configurations.filter({ endpoints.contains($0.key) }), dispatchScheme: dispatchScheme)

                endpoints.forEach { configurations.removeValue(forKey: $0) }

                return dropped
            }


            // MARK: Operations

            func mergeConfigurations(with rhs: HttpEndpoints.Configurations) {
                typealias Configuration = HttpEndpoints.Configuration


                func Min(_ lhs: Configuration.HTTP, _ rhs: Configuration.HTTP) -> Configuration.HTTP {

                    func Rank(of http: Configuration.HTTP) -> Int {
                        switch http {
                        case .v1_1(.none):
                            return 1100
                        case .v1_1(.some):
                            return 1150
                        case .v2:
                            return 2000
                        }
                    }

                    return Rank(of: lhs) <= Rank(of: rhs) ? lhs : rhs
                }


                func Max(_ lhs: Configuration.Connection, _ rhs: Configuration.Connection) -> Configuration.Connection {
                    .init(idleTimeInterval: max(lhs.idleTimeInterval, rhs.idleTimeInterval),
                          requestLimit: max(lhs.requestLimit, rhs.requestLimit))
                }


                rhs.forEach { (endpoint, configuration) in
                    _ = {
                        guard let lhs = $0 else { return }

                        $0 = .init(http: Min(lhs.http, configuration.http),
                                   connection: Max(lhs.connection, configuration.connection))
                    }(&configurations[endpoint])
                }
            }

        }

    }

}



// MARK: .HttpServer

extension KvServerImplementation {

    fileprivate class HttpServer : KvHttpServerDelegate {

        init() {
            underlying.delegate = self
        }


        private let underlying: KvHttpServer = .init()

        /// Channel controllers are stored here to revent release.
        private var channelControllers: [ChannelController] = .init()


        // MARK: Managing Channels

        func createChannel(_ channelScheme: HttpScheme.HttpChannel) {
            guard let controller = ChannelController(from: channelScheme) else { return }

            channelScheme.configurations.forEach { (endpoint, configuration) in
                let channel = KvHttpChannel(with: .init(endpoint: endpoint, http: configuration.http, connection: configuration.connection))

                channel.delegate = controller

                underlying.addChannel(channel)
            }

            channelControllers.append(controller)
        }


        // MARK: Managing Life-cycle

        func start() throws {
            try underlying.start()
        }


        func stop(_ completion: ((Result<Void, Error>) -> Void)? = nil) {
            underlying.stop(completion)
        }


        /// Waits while server and all it's channels are starting.
        @discardableResult
        public func waitWhileStarting() -> Result<Void, Error> {
            underlying.waitWhileStarting().flatMap {
                for channelID in underlying.channelIDs {
                    guard let channel = underlying.channel(with: channelID) else { return .failure(KvServerError.internal(.missingHttpChannel)) }

                    let result = channel.waitWhileStarting()
                    guard case .success = result else { return result }
                }

                return .success(())
            }
        }


        @discardableResult
        func waitUntilStopped() -> Result<Void, Error> {
            underlying.waitUntilStopped()
        }


        // MARK: : KvHttpServerDelegate

        func httpServerDidStart(_ httpServer: KvHttpServer) { }


        // TODO: pass error to user-declared handler.
        func httpServer(_ httpServer: KvHttpServer, didStopWith result: Result<Void, Error>) { }


        // TODO: pass error to user-declared handler.
        func httpServer(_ httpServer: KvHttpServer, didCatch error: Error) { }

    }

}



// MARK: .ChannelController

extension KvServerImplementation.HttpServer {

    fileprivate class ChannelController : KvHttpChannelDelegate, KvHttpClientDelegate {

        typealias Dispatcher = KvHttpResponseDispatcher


        init?(from scheme: KvServerImplementation.HttpScheme.HttpChannel) {
            guard let dispatcher = Dispatcher(from: scheme.dispatchScheme) else { return nil }

            self.dispatcher = dispatcher
        }


        private let dispatcher: Dispatcher


        // MARK: : KvHttpChannelDelegate

        func httpChannelDidStart(_ httpChannel: KvHttpChannel) { }


        // TODO: pass error to user-declared handler.
        func httpChannel(_ httpChannel: KvHttpChannel, didStopWith result: Result<Void, Error>) { }


        // TODO: pass error to user-declared handler.
        func httpChannel(_ httpChannel: KvHttpChannel, didCatch error: Error) { }


        func httpChannel(_ httpChannel: KvHttpChannel, didStartClient httpClient: KvHttpChannel.Client) {
            httpClient.delegate = self
        }


        // TODO: pass error to user-declared handler.
        func httpChannel(_ httpChannel: KvHttpChannel, didStopClient httpClient: KvHttpChannel.Client, with result: Result<Void, Error>) { }


        // MARK: : KvHttpClientDelegate

        func httpClient(_ httpClient: KvHttpChannel.Client, requestHandlerFor requestHead: KvHttpServer.RequestHead) -> KvHttpRequestHandler? {
            guard let requestContext = KvHttpRequestContext(httpClient, requestHead)
            else { return KvHttpHeadOnlyRequestHandler { .badRequest } }

            let requestProcessor: KvHttpRequestProcessorProtocol

            // Dispatching request
            let dispatchingResult = dispatcher.requestProcessor(in: requestContext)
            var onIncident = dispatchingResult.resolvedAttributes?.clientCallbacks?.onHttpIncident


            func RequestHandler(for incident: KvHttpResponse.Incident, callback: KvResponseGroupConfiguration.ClientCallbacks.IncidentCallback?) -> KvHttpRequestHandler {
                KvHttpHeadOnlyRequestHandler { callback?(incident, requestContext) ?? .status(incident.defaultStatus) }
            }


            switch dispatchingResult.match {
            case .unambiguous(let value):
                requestProcessor = value
                onIncident = requestProcessor.onIncident(_:_:)
            case .notFound:
                return RequestHandler(for: .responseNotFound, callback: onIncident)
            case .ambiguous:
                return RequestHandler(for: .ambiguousRequest, callback: onIncident)
            }

            // Custom processing of headers
            switch requestProcessor.process(requestHead.headers) {
            case .success:
                break
            case .failure(let error):
                return RequestHandler(for: .invalidHeaders(error), callback: onIncident)
            }

            // Creation of a request processor
            switch requestProcessor.makeRequestHandler(requestContext) {
            case .success(let requestHandler):
                return requestHandler
            case .failure(let error):
                return RequestHandler(for: .processingFailed(error), callback: onIncident)
            }
        }


        func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.ClientIncident) -> KvHttpResponseProvider? {
            // TODO: Pass to provided handler of channel incidents when implemented.
            return nil
        }


        func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
            // TODO: Pass to provided handler of channel errors when implemented.
        }

    }

}
