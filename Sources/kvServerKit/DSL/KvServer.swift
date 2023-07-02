//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2023 Svyatoslav Popov.
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
//  KvServer.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 09.06.2023.
//


/// A type that represents behaviour of a server.
///
/// Below is an example of simple server:
///
///     @main
///     struct ExampleServer : KvServer {
///         var body: some KvResponseGroup {
///             KvGroup(http: .v2(ssl: ssl), at: Host.current().addresses, on: [ 8080 ]) {
///                 KvHttpResponse.static { .string("Hello, client") }
///
///                 KvGroup("echo") {
///                     KvHttpResponse.dynamic
///                         .requestBody(.data)
///                         .content { .binary($0.requestBody ?? Data()) }
///                 }
///                 .httpMethods(.POST)
///
///                 KvGroup("uuid") {
///                     KvHttpResponse.static
///                         .content { .string(UUID().uuidString) }
///                 }
///             }
///             .hosts("example.com")
///             .subdomains(optional: "www")
///         }
///     }
///
/// Note `@main` attribute in the exapmle above. This attribute makes the server's ``main()`` method to be the entry point of application.
///
/// Servers can be launched manually. See ``start()`` for details.
public protocol KvServer {

    /// The type of connection and request dispatcher.
    ///
    /// It's inferred from your implementation of the required property ``body-swift.property``.
    associatedtype Body : KvResponseGroup


    /// The behavior of the server.
    ///
    /// It's a place to define server's configuration, routing of requests and responses.
    @KvResponseGroupBuilder
    var body: Self.Body { get }


    /// Implementation have to provide default initializer.
    /// It's recommended to implement server as a structure so implementation of default initializer is synthesized by Swift.
    init()

}



// MARK: Automatic Launch

extension KvServer {

    /// Initializes and runs the server.
    ///
    /// It's automatically called when application is launched if server implementation is annotated with
    /// [@main](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/attributes/#main) attribute.
    ///
    ///     @main
    ///     struct ExampleServer : KvServer
    ///
    /// See: ``start()``.
    public static func main() {
        let token: KvServerToken

        do { token = try Self().start() }
        catch { return print("Unable to start \(Self.self). \(error)") }

        switch token.waitUntilStopped() {
        case .success:
            break
        case .failure(let error):
            print("\(Self.self) stopped with error. \(error)")
        }
    }

}



// MARK: Launch

extension KvServer {

    /// Starts the server and returns a token. The token provides life-cycle management of started server instance.
    ///
    /// For example:
    ///
    ///     let token = try ExampleServer().start()
    ///
    ///     try token.waitWhileStarting().get()
    ///     CustomActions()
    ///
    ///     try token.waitUntilStopped().get()
    ///     CustomCompletion()
    ///
    /// See: ``main()``.
    public func start() throws -> KvServerToken {
        let server = KvServerImplementation(from: self)

        try server.start()

        return .init(for: server)
    }

}



// MARK: Auxiliaries

extension KvServer {

    public typealias QueryResult = KvUrlQueryParseResult

}



// TODO: .catch(_:) modifier for all server errors.



// MARK: - KvServerToken

/// Provides life-cycle management of a server instance.
///
/// - Note: Server is stopped when token is released.
public class KvServerToken {

    fileprivate init(for server: KvServerImplementation) {
        self.server = server
    }


    deinit {
        server.stop()
        server.waitUntilStopped()
    }


    private let server: KvServerImplementation


    // MARK: Operations

    /// Intiates stop of the server. Given *completion* is invoked when the server is stopped and passed with the result.
    public func stop(_ completion: ((Result<Void, Error>) -> Void)? = nil) {
        server.stop(completion)
    }


    /// This method stops execution until server is started or stopeed and then returns the result.
    @discardableResult
    public func waitWhileStarting() -> Result<Void, Error> {
        server.waitWhileStarting()
    }


    /// This method stops execution until server is stopped and returns the result.
    ///
    /// - Note: If the server has already stopped then last stop result is returned.
    @discardableResult
    func waitUntilStopped() -> Result<Void, Error> {
        server.waitUntilStopped()
    }

}
