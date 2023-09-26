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
//  KvHttpServer.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 15.04.2020.
//

import Foundation

import NIO
import NIOHTTP1



public protocol KvHttpServerDelegate : AnyObject {

    func httpServerDidStart(_ httpServer: KvHttpServer)

    func httpServer(_ httpServer: KvHttpServer, didStopWith result: Result<Void, Error>)

    func httpServer(_ httpServer: KvHttpServer, didCatch error: Error)

}



/// *KvHttpServer* class provides ability to implement request handling in imperative paradigm.
///
/// Usually there is no need to subclass *KvHttpServer* or ``KvHttpChannel`` classes.
/// Most of work should be done via delegates and dedicated classes for request handling.
/// See *ImperativeServer* sample in *Samples* package at `/Samples` directory.
///
/// When instance of running *KvHttpServer* is being destroyed, the deinitializer is waiting until server actually stopped.
/// Use async ``KvHttpServer/stop()`` method or sync ``KvHttpServer/stop(_:)`` and ``KvHttpServer/waitUntilStopped()`` methods to wait explicitely.
open class KvHttpServer {

    public typealias RequestHead = HTTPRequestHead
    public typealias RequestHeaders = HTTPHeaders



    public weak var delegate: KvHttpServerDelegate?



    @inlinable public init() { }


    deinit {
        stop()
        waitUntilStopped()
    }



    private let mutationLock = NSRecursiveLock()


    /// - Warning: Access must be protected with `.stateCondition`.
    private var _state: InternalState = .stopped(.success(())) {
        didSet {
            guard State(for: _state) != State(for: oldValue) else { return }

            stateCondition.broadcast()
        }
    }

    private var stateCondition = NSCondition()


    /// - Warning: Access must be protected with `.mutationLock`.
    private var _channels: [KvHttpChannel.ID : KvHttpChannel] = .init()



    // MARK: .ServerError

     public enum ServerError : LocalizedError {

         /// Unable to perform a task due to current server's state doesn't meet the requirements. E.g. attempt to start a running server.
        case unexpectedState(State)

    }



    // MARK: Managing Life-cycle

    internal var eventLoopGroup: MultiThreadedEventLoopGroup? {
        switch stateCondition.withLock({ _state }) {
        case .running(let eventLoopGroup), .starting(.some(let eventLoopGroup)):
            return eventLoopGroup
        case .starting(.none), .stopped(_), .stopping:
            return nil
        }
    }


    /// Starts server and all bound channels.
    ///
    /// See: ``waitWhileStarting()``, ``stop()``, ``stop(_:)``.
    public func start() throws {
        do {
            try stateCondition.withLock {
                guard case .stopped = _state else { throw ServerError.unexpectedState(.init(for: _state)) }

                _state = .starting(nil)
            }
        }
        catch {
            delegate?.httpServer(self, didCatch: error)
            throw error
        }

        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

        stateCondition.withLock {
            _state = .starting(eventLoopGroup)
        }

        // - NOTE:  Registered channels are started before server changes state to `.running`
        //          to prevent case when server is running but a registered channel is in stopped state.

        do {
            let channelDispatchGroup = DispatchGroup()

            mutationLock.withLock {
                _channels.values.forEach { channel in
                    DispatchQueue.global().async(group: channelDispatchGroup) {
                        channel.start()
                    }
                }
            }

            channelDispatchGroup.notify(queue: .global()) {
                self.stateCondition.withLock {
                    self._state = .running(eventLoopGroup)
                }

                self.delegate?.httpServerDidStart(self)
            }
        }
    }


    /// Stops server.
    ///
    /// Server can be stopped at any moment. If server is being started then this method will stop server just after it will be completely started.
    /// This method can be called multiple times. If it is then *completion* is invoked multiple times with the same stop result.
    ///
    /// See: ``waitUntilStopped()``, ``start()``.
    public func stop(_ completion: ((Result<Void, Error>) -> Void)? = nil) {

        /// - Returns: A *Result* instance where `.success(nil)` means that server has been successfuly stopped.
        func CurrentEventLoopGroup() -> Result<MultiThreadedEventLoopGroup?, Error> {
            return stateCondition.withLock {
                // `while true` is used to prevent recursion.
                while true {
                    switch _state {
                    case .running(let eventLoopGroup):
                        _state = .stopping
                        return .success(eventLoopGroup)

                    case .starting, .stopping:
                        stateCondition.wait()

                    case .stopped(let result):
                        return result.map { nil }
                    }
                }
            }
        }


        switch CurrentEventLoopGroup() {
        case .failure(let error):
            return completion?(.failure(error)) ?? ()

        case .success(.none):
            return completion?(.success(())) ?? ()

        case .success(.some(let eventLoopGroup)):
            eventLoopGroup.shutdownGracefully { error in
                let result: Result<Void, Error> = error.map(Result.failure(_:)) ?? .success(())

                self.stateCondition.withLock {
                    self._state = .stopped(result)
                }

                self.delegate?.httpServer(self, didStopWith: result)
                completion?(result)
            }
        }
    }


    /// Async wrapper around ``stop(completion:)`` method.
    ///
    /// See: ``start()``.
    @inlinable
    public func stop() async throws {
        try await withCheckedThrowingContinuation { continuation in
            stop(continuation.resume(with:))
        }
    }


    /// This method stops execution until server is started or stopeed and then returns the result.
    ///
    /// - Note: If the server's status is not *.running* or *.stopped* then method just returns success or result of last stop.
    ///
    /// - Note: When server's status becomes *.running* it's channels can be in start process. Use ``KvHttpChannel/waitWhileStarting()`` to wait until channels are started.
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


    /// This method stops execution until server and it's channels are stopped and then returns result of stop.
    ///
    /// - Note: If the server is stopped then method just returns result of last stop.
    ///
    /// See: ``waitWhileStarting()``.
    @discardableResult
    public func waitUntilStopped() -> Result<Void, Error> {
        let serverResult = stateCondition.withLock {
            while true {
                switch _state {
                case .running, .starting, .stopping:
                    stateCondition.wait()

                case .stopped(let result):
                    return result
                }
            }
        }

        return serverResult.flatMap {
            for channelID in channelIDs {
                guard let channel = channel(with: channelID) else { continue }

                let result = channel.waitUntilStopped()
                guard case .success = result else { return result }
            }

            return .success(())
        }
    }



    // MARK: .State

    /// An enumeration of server states.
    public enum State : Hashable {

        /// Server has been successfully started.
        case running
        /// Server is performing initialization.
        case starting
        /// Server is stopped.
        case stopped
        /// Server is performing shutdown tasks.
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
        case running(MultiThreadedEventLoopGroup)
        /// Event loop group can become available before server is completely started.
        case starting(MultiThreadedEventLoopGroup?)
        /// Associated type is result of last stop operation.
        case stopped(Result<Void, Error>)
        case stopping
    }



    // MARK: State

    /// Currect state of the receiver.
    ///
    /// - Note: This property is thread-safe so costs of mutual exclusion should be taken into account.
    ///
    /// See: ``State-swift.enum``.
    public var state: State { stateCondition.withLock { .init(for: _state) } }


    /// URLs the receiver is available at on local machine or in local networks. It's a joined list all ``KvHttpChannel/endpointURLs``.
    ///
    /// - Note: This property is thread-safe so costs of mutual exclusion should be taken into account.
    public var endpointURLs: [URL]? {
        return mutationLock.withLock {
            _channels.values.reduce(into: nil as [URL]?) { urls, channel in
                guard let channelURLs = channel.endpointURLs else { return }

                // Assuming channes always have distinct URLs.
                urls?.append(contentsOf: channelURLs)
                ?? (urls = channelURLs)
            }
        }
    }



    // MARK: Managing Channels

    /// Number of registered channels.
    ///
    /// - Note: This property is thread-safe so costs of mutual exclusion should be taken into account.
    public var numberOfChannels: Int { mutationLock.withLock { _channels.count } }


    /// A copy of the receiver's channels.
    ///
    /// - Note: This property is thread-safe so costs of mutual exclusion should be taken into account.
    public var channelIDs: Set<KvHttpChannel.ID> { mutationLock.withLock { .init(_channels.keys) } }


    /// - Returns: Regustered channel having given *id* or `nil`.
    ///
    /// - Note: This property is thread-safe so costs of mutual exclusion should be taken into account.
    public func channel(with id: KvHttpChannel.ID) -> KvHttpChannel? { mutationLock.withLock { _channels[id] } }

    /// - Returns: A boolean value indicating whether given *channel* has been added to the receiver.
    ///
    /// - Note: This property is thread-safe so costs of mutual exclusion should be taken into account.
    ///
    /// See: ``addChannel``, ``KvHttpChannel/removeFromServer()``.
    public func contains(channelWith id: KvHttpChannel.ID) -> Bool { mutationLock.withLock { _channels[id] != nil } }


    /// Bound channel to the server.
    ///
    /// If the server is running then the channel is started.
    ///
    /// If the channel is bound to other server it's first removed from other server.
    /// Note that is the channel is running then the method will wait until the channel is stopped.
    ///
    /// If the channel has already been bound to the server then nothing is done.
    public func addChannel(_ channel: KvHttpChannel) {
        if let server = channel.server {
            guard server !== self else { return }

            channel.removeFromServer()
            channel.waitUntilStopped()
        }

        mutationLock.withLock {
            _channels[channel.id] = channel
        }

        channel.server = self

        guard state == .running else { return }

        channel.start()
    }


    /// - Note: It's internal. Public ``KvHttpChannel/removeFromServer()`` method must be used to remove channels.
    func removeChannel(_ channel: KvHttpChannel) {
        guard mutationLock.withLock({ _channels.removeValue(forKey: channel.id) === channel }) else { return }

        channel.stop()
        channel.server = nil
    }

}
