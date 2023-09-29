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
//  KvResponseGroup.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 09.06.2023.
//

import Foundation

import kvKit
import NIOHTTP1



// MARK: - KvResponseGroup

/// A type that represents hierarchical structure of responses.
///
/// Groups are used to manage their contents as a single entity and to customize handling of responses in the group.
/// Customizations are declared via modifiers of response groups. Also there are various overloads of `KvGroup`() method providing the same functionality in convenient way.
///
/// Below is an example where response group is used to provide some responses on two hosts with optional subdomain "www".
///
/// ```swift
/// KvGroup(hosts: "example.com", "example.org") {
///     Response1()
///     Response2()
/// }
/// .subdomains(optional: "www")
/// ```
///
/// Below is a more complicated example where response group is used to incapsulate some part of response hierarchy with options.
///
/// ```swift
/// struct TestableServer : KvServer {
///     var body: some KvResponseGroup {
///         RootResponseGroup(options: [ ])
///         RootResponseGroup(options: .testMode)
///     }
///
///     private struct RootResponseGroup : KvResponseGroup {
///         let options: Options
///
///         var body: some KvResponseGroup {
///             let hostPrefix = options.contains(.testMode) ? "test." : ""
///
///             KvGroup(hosts: [ "example.com", "example.org" ].lazy.map { hostPrefix + $0 ) {
///                 KvGroup("a") {
///                     SomeTestableResponse(options: options)
///                 }
///
///                 SomeResponse()
///             }
///             .subdomains(optional: "www")
///         }
///     }
/// }
/// ```
public protocol KvResponseGroup {

    /// It's inferred from your implementation of the required property ``KvResponseGroup/body-swift.property-79vqj``.
    associatedtype Body : KvResponseGroup


    /// Incapsulated responses and response groups.
    ///
    /// It's a place to define group's contents.
    @KvResponseGroupBuilder
    var body: Body { get }

}



extension KvResponseGroup {

    // MARK: Auxiliaries

    public typealias QueryResult = KvUrlQueryParseResult



    // MARK: Accumulation

    internal func insertResponses<A : KvResponseAccumulator>(to accumulator: A) {
        switch self {
        case let group as any KvResponseGroupInternalProtocol:
            group.insertResponses(to: accumulator)
        default:
            body.insertResponses(to: accumulator)
        }
    }



    // MARK: Modifiers

    public typealias HTTP = KvHttpConfiguration

    public typealias HttpMethod = HTTPMethod


    @usableFromInline
    typealias Configuration = KvModifiedResponseGroup.Configuration


    @inline(__always)
    @usableFromInline
    func modified(_ transform: (inout Configuration) -> Void) -> some KvResponseGroup {
        ((self as? KvModifiedResponseGroup) ?? KvModifiedResponseGroup(source: { self })).modified(transform)
    }


    /// Declares parameters of HTTP connections for HTTP responses in the group contents.
    ///
    /// - Parameter httpEndpoints: Sequence of network addresses (IP addresses or host names), ports and HTTP protocol configurations.
    ///
    /// Existing values of the contents are replaced with provided values.
    /// Arguments of cascade invocations of the modifier are merged. Existing configurations are replaced with new values on the same endponts.
    ///
    /// Below is an example where the contents of `SomeResposeGroup` are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
    ///
    /// ```swift
    /// SomeResposeGroup()
    ///     .http(Host.current().addresses.lazy.map { (.init($0, on: 8080), .v2(ssl: ssl)) })
    /// ```
    ///
    /// See: ``KvHttpConfiguration``, ``KvGroup(httpEndpoints:content:)``, ``http(_:at:)``, ``http(_:at:on:)``.
    ///
    /// - Note: By default HTTP responses are available at IPv6 local machine address `::1`, on port 80, via insecure HTTP/1.1.
    @inlinable
    public func http<HttpEndpoints>(_ httpEndpoints: HttpEndpoints) -> some KvResponseGroup
    where HttpEndpoints : Sequence, HttpEndpoints.Element == (KvNetworkEndpoint, HTTP)
    {
        modified { configuration in
            configuration.network.insert(httpEndpoints)
        }
    }


    /// A shorthand for ``http(_:)`` providing the same HTTP configuration on given *endpoints*. See it's documentation for details.
    ///
    /// Below is an example where the contents of `SomeResposeGroup` are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
    ///
    /// ```swift
    /// SomeResposeGroup()
    ///     .http(.v2(ssl: ssl), at: Host.current().addresses.lazy.map { .init($0, on: 8080) })
    /// ```
    ///
    /// See: ``KvHttpConfiguration``, ``KvGroup(http:at:content:)``.
    @inlinable
    public func http<Endpoints>(_ http: HTTP = .init(), at endpoints: Endpoints) -> some KvResponseGroup
    where Endpoints : Sequence, Endpoints.Element == KvNetworkEndpoint
    {
        self.http(endpoints.lazy.map { ($0, http) })
    }


    /// A shorthand for ``http(_:)`` providing the same HTTP configuration on all combinations of *addresses* and *ports*. See it's documentation for details.
    ///
    /// Below is an example where the contents of `SomeResposeGroup` are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
    ///
    /// ```swift
    /// SomeResposeGroup()
    ///     .http(.v2(ssl: ssl), at: Host.current().addresses, on: [ 8080 ])
    /// ```
    ///
    /// See: ``KvHttpConfiguration``, ``KvGroup(http:at:on:content:)``.
    @inlinable
    public func http<Addresses, Ports>(
        _ http: HTTP = .init(),
        at addresses: Addresses,
        on ports: Ports
    ) -> some KvResponseGroup
    where Addresses : Sequence, Addresses.Element == String,
          Ports : Sequence, Ports.Element == UInt16
    {
        self.http(http, at: KvCartesianProductSequence(addresses, ports).lazy.map { KvNetworkEndpoint($0.0, on: $0.1) })
    }


    /// Adds given values into list of HTTP methods.
    ///
    /// The result is the same as ``KvResponseGroup/httpMethods(_:)-6fbma``. See it's documentation for details.
    @inlinable
    public func httpMethods<Methods>(_ httpMethods: Methods) -> some KvResponseGroup
    where Methods : Sequence, Methods.Element == HttpMethod
    {
        modified {
            $0.dispatching.httpMethods.formUnion(httpMethods.lazy.map { $0.rawValue })
        }
    }


    /// Adds given values into list of HTTP methods.
    ///
    /// HTTP method lists of nested response groups are united. Nested lists of HTTP methods are resolved for each HTTP response and used to filter HTTP requests.
    /// If the resolved list is empty then the response available for any HTTP method.
    ///
    /// Below is a simple example:
    ///
    /// ```swift
    /// SomeResponseGroup()
    ///     .httpMethods(.GET, .PUT, .DELETE)
    /// ```
    ///
    /// See: ``KvGroup(httpMethods:content:)-29gzp``.
    @inlinable
    public func httpMethods(_ httpMethods: HttpMethod...) -> some KvResponseGroup {
        self.httpMethods(httpMethods)
    }


    /// Adds given values into list of users.
    ///
    /// The result is the same as ``KvResponseGroup/users(_:)-48ll0``. See it's documentation for details.
    @inlinable
    public func users<Users>(_ users: Users) -> some KvResponseGroup
    where Users : Sequence, Users.Element == String
    {
        modified {
            $0.dispatching.users.formUnion(users)
        }
    }


    /// Adds given values into list of users.
    ///
    /// User lists of nested response groups are united. Nested lists of users are resolved for each response and used to filter requests.
    /// If the resolved list is empty then the response available for any or no user.
    ///
    /// Usually user is provided as a component of an URL and separated from domain component by "@" character.
    ///
    /// Below is a simple example:
    ///
    /// ```swift
    /// SomeResponseGroup()
    ///     .users("user1", "user2")
    /// ```
    ///
    /// See: ``KvGroup(users:content:)-3140o``.
    @inlinable
    public func users(_ users: String...) -> some KvResponseGroup {
        self.users(users)
    }


    /// Adds given values into list of hosts.
    ///
    /// The result is the same as ``KvResponseGroup/hosts(_:)-1pv6b``. See it's documentation for details.
    @inlinable
    public func hosts<Hosts>(_ hosts: Hosts) -> some KvResponseGroup
    where Hosts : Sequence, Hosts.Element == String
    {
        modified {
            $0.dispatching.hosts.formUnion(hosts)
        }
    }


    /// Adds given values into list of hosts.
    ///
    /// Host lists of nested response groups are united. Nested lists of hosts are resolved for each response and used to filter requests.
    /// If the resolved list is empty then the response available for any or no host.
    ///
    /// Usually host is provided as a component of an URL.
    ///
    /// Below is a simple example:
    ///
    /// ```swift
    /// SomeResponseGroup()
    ///     .hosts("example.com", "example.org")
    /// ```
    ///
    /// See: ``KvGroup(hosts:content:)-872vb``, ``KvResponseGroup/subdomains(optional:)-9g9xv``.
    @inlinable
    public func hosts(_ hosts: String...) -> some KvResponseGroup {
        self.hosts(hosts)
    }


    /// Adds given values into list of optional subdomains.
    ///
    /// The result is the same as ``KvResponseGroup/subdomains(optional:)-9g9xv``. See it's documentation for details.
    @inlinable
    public func subdomains<Subdomains>(optional subdomains: Subdomains) -> some KvResponseGroup
    where Subdomains : Sequence, Subdomains.Element == String
    {
        modified {
            $0.dispatching.optionalSubdomains.formUnion(subdomains)
        }
    }


    /// Adds given values into list of optional subdomains.
    ///
    /// Optional subdomain lists of nested response groups are united. Nested lists of optional subdomains are resolved for each response and used to filter requests.
    ///
    /// Below is an example where `SomeResponseGroup` is available on "example.com", "example.org", "www.example.com", "www.example.org":
    ///
    /// ```swift
    /// SomeResponseGroup()
    ///     .hosts("example.com", "example.org")
    ///     .subdomains(optional: "www")
    /// ```
    ///
    /// See: ``KvResponseGroup/hosts(_:)-1pv6b``.
    @inlinable
    public func subdomains(optional subdomains: String...) -> some KvResponseGroup {
        self.subdomains(optional: subdomains)
    }


    /// Appends the group's relative path to it's contents.
    ///
    /// Paths of nested groups are correctly joined, duplicated path separators are removed. Special directories "." and ".." are not resolved.
    /// E.g. "///b/./c/..//b///e///./f/../" path is equivalent to "/b/./c/../b/e/./f/..".
    ///
    /// Nested paths are resolved for each response and used to filter requests.
    /// If the resolved path is empty then the response available at root path.
    ///
    /// Below is an example where `response1` is available at both root and "/a" paths, `response2` is available at "/a" path,
    /// `response3` is available at "/b" path, `response4` is available at "/b/c/d" path, `response5` is available at "/b/c/e" path:
    ///
    /// ```swift
    /// KvGroup(hosts: "example.com") {
    ///     response1               // /
    ///     KvGroup {
    ///         response1           // /a
    ///         response2           // /a
    ///     }
    ///     .path("a")
    ///     KvGroup {
    ///         response3           // /b
    ///         KvGroup {
    ///             response4       // /b/c/d
    ///         }
    ///         .path("c/d")
    ///     }
    ///     .path("b")
    ///     KvGroup {
    ///         response5           // /b/c/e
    ///     }
    ///     .path("b/c/e")
    /// }
    /// ```
    ///
    /// See: ``KvGroup(_:content:)``.
    @inlinable
    public func path(_ pathComponent: String) -> some KvResponseGroup {
        modified {
            $0.dispatching.appendPathComponent(pathComponent)
        }
    }


    /// Declares default body length limit in bytes for HTTP requests in the receiver and it's descendant groups.
    ///
    /// Previously declared value is replaced.
    ///
    /// See: ``KvHttpRequestRequiredBody/bodyLengthLimit(_:)``.
    @inlinable
    public func httpBodyLengthLimit(_ value: UInt) -> some KvResponseGroup {
        modified {
            $0.httpRequestBody.bodyLengthLimit = value
        }
    }

}



// MARK: - KvResponseGroupConfiguration

@usableFromInline
struct KvResponseGroupConfiguration {

    @usableFromInline
    static let empty: Self = .init()


    @usableFromInline
    var network: Network

    @usableFromInline
    var dispatching: Dispatching

    @usableFromInline
    var httpRequestBody: HttpRequestBody


    @usableFromInline
    init(network: Network = .empty, dispatching: Dispatching = .empty, httpRequestBody: HttpRequestBody = .empty) {
        self.network = network
        self.dispatching = dispatching
        self.httpRequestBody = httpRequestBody
    }


    @usableFromInline
    init(lhs: Self, rhs: Self) {
        self.init(network: .init(lhs: lhs.network, rhs: rhs.network),
                  dispatching: .init(lhs: lhs.dispatching, rhs: rhs.dispatching),
                  httpRequestBody: .init(lhs: lhs.httpRequestBody, rhs: rhs.httpRequestBody))
    }


    // MARK: .Network

    @usableFromInline
    struct Network {

        @usableFromInline
        typealias Address = String

        @usableFromInline
        typealias Port = UInt16


        @usableFromInline
        static let empty: Self = .init()


        /// Protocol IDs for endpoints.
        @usableFromInline
        private(set) var protocolIDs: [KvNetworkEndpoint : ProtocolID]

        /// Prepared data to configure HTTP channels.
        @usableFromInline
        private(set) var httpEndpoints: HttpEndpoints


        private init() {
            protocolIDs = [:]
            httpEndpoints = .empty
        }


        @usableFromInline
        init(httpEndpoints: HttpEndpoints) {
            self.protocolIDs = .init(uniqueKeysWithValues: httpEndpoints.elements.lazy.map { ($0, .http) })
            self.httpEndpoints = httpEndpoints
        }


        @usableFromInline
        init(lhs: Self, rhs: Self) {
            // If `lhs` is non-emmpty then it's copied. Otherwise `rhs` is copied.
            self = !lhs.isEmpty ? lhs : rhs
        }


        // MARK: .ProtocolID

        @usableFromInline
        enum ProtocolID : Equatable {
            case http
        }


        // MARK: .HttpEndpoints

        @usableFromInline
        struct HttpEndpoints : ExpressibleByDictionaryLiteral, Equatable {

            @usableFromInline
            typealias Configurations = [KvNetworkEndpoint : Configuration]


            static let empty: Self = .init()


            /// All endpoints from ``configurations``.
            private(set) var elements: Set<KvNetworkEndpoint> = [ ]
            /// Protocol configurations for endpoints.
            private(set) var configurations: Configurations = [:]


            private init() { }


            private init(elements: Set<KvNetworkEndpoint>, configurations: Configurations) {
                self.elements = elements
                self.configurations = configurations
            }


            @usableFromInline
            init<E>(uniqueKeysWithValues elements: E) where E : Sequence, E.Element == (KvNetworkEndpoint, Configuration) {
                configurations = .init(uniqueKeysWithValues: elements)
                self.elements = .init(configurations.keys)
            }


            // MARK: : ExpressibleByDictionaryLiteral

            @usableFromInline
            init(dictionaryLiteral elements: (KvNetworkEndpoint, Configuration)...) {
                self.init(uniqueKeysWithValues: elements)
            }


            // MARK: Equatable

            @usableFromInline
            static func ==(lhs: Self, rhs: Self) -> Bool { lhs.configurations == rhs.configurations }


            // MARK: .Configuration

            @usableFromInline
            typealias Configuration = KvHttpConfiguration


            // MARK: Operations

            var isEmpty: Bool { configurations.isEmpty }


            mutating func insert(_ configuration: Configuration, for endpoint: KvNetworkEndpoint) {
                elements.insert(endpoint)
                configurations[endpoint] = configuration
            }


            mutating func remove(_ endpoint: KvNetworkEndpoint) {
                elements.remove(endpoint)
                configurations.removeValue(forKey: endpoint)
            }


            func intersection(_ endpoints: Set<KvNetworkEndpoint>) -> Self {
                .init(elements: elements.subtracting(endpoints),
                      configurations: configurations.filter({ endpoints.contains($0.key) }))
            }

        }


        // MARK: Operations

        @usableFromInline
        var isEmpty: Bool { protocolIDs.isEmpty }


        @usableFromInline
        mutating func insert<H>(_ httpEndpoints: H) where H : Sequence, H.Element == (KvNetworkEndpoint, HttpEndpoints.Configuration) {
            httpEndpoints.forEach { (endpoint, httpConfiguration) in
                insert(protocolID: .http, for: endpoint)
                self.httpEndpoints.insert(httpConfiguration, for: endpoint)
            }
        }


        /// Inserts *protocolID* for *endpoint* key. If some other ID has already been inserted then it's correctly deleted.
        @inline(__always)
        private mutating func insert(protocolID: ProtocolID, for endpoint: KvNetworkEndpoint) {
            let oldProtocolID = protocolIDs.updateValue(protocolID, forKey: endpoint)

            guard let oldProtocolID = oldProtocolID,
                  oldProtocolID != protocolID
            else { return /* Nothing to do */ }

            switch oldProtocolID {
            case .http:
                httpEndpoints.remove(endpoint)
            }
        }

    }


    // MARK: .Dispatching

    @usableFromInline
    struct Dispatching {

        @usableFromInline
        static let empty: Self = .init()


        /// - Note: Empty set means any method.
        @usableFromInline
        var httpMethods: Set<String>

        /// - Note: Empty set means any user.
        @usableFromInline
        var users: Set<String>

        /// - Note: Empty set means any host.
        @usableFromInline
        var hosts: Set<String>

        @usableFromInline
        var optionalSubdomains: Set<String>

        /// See: ``appendPathComponent(_:)``.
        @usableFromInline
        private(set) var path: String


        @usableFromInline
        init(httpMethods: Set<String> = [ ],
             users: Set<String> = [ ],
             hosts: Set<String> = [ ],
             optionalSubdomains: Set<String> = [ ],
             path: String = ""
        ) {
            self.httpMethods = httpMethods
            self.users = users
            self.hosts = hosts
            self.optionalSubdomains = optionalSubdomains
            self.path = Self.normalizedPath(path)
        }


        @usableFromInline
        init(lhs: Self, rhs: Self) {
            self.init(httpMethods: lhs.httpMethods.union(rhs.httpMethods),
                      users: lhs.users.union(rhs.users),
                      hosts: lhs.hosts.union(rhs.hosts),
                      optionalSubdomains: lhs.optionalSubdomains.union(rhs.optionalSubdomains),
                      path: lhs.path + rhs.path)    // Assuming paths are safe and always have leading path separators
        }


        // MARK: Operations

        @inline(__always)
        @usableFromInline
        static func merge<T>(lhs: T?, rhs: T?, transform: (T, T) -> T) -> T? {
            guard let lhs = lhs else { return rhs }
            guard let rhs = rhs else { return lhs }

            return transform(lhs, rhs)
        }


        /// - Returns: Non-empty value where missing leading URL path separator is added or empty string.
        @inline(__always)
        @usableFromInline
        static func normalizedPath(_ value: String) -> String {
            switch value.first {
            case "/", .none:
                return value
            default:
                return "/" + value
            }
        }


        @inline(__always)
        @usableFromInline
        static func join<T>(_ lhs: [T], _ rhs: [T]) -> [T] {
            var result = lhs
            result.append(contentsOf: rhs)
            return result
        }


        @inline(__always)
        @usableFromInline
        mutating func appendPathComponent(_ pathComponent: String) {
            path += Self.normalizedPath(pathComponent)
        }

    }


    // MARK: .HttpRequestBody

    @usableFromInline
    typealias HttpRequestBody = KvHttpRequestBodyConfiguration

}



// MARK: - KvResponseGroupInternalProtocol

protocol KvResponseGroupInternalProtocol : KvResponseGroup {

    func insertResponses<A : KvResponseAccumulator>(to accumulator: A)

}



// MARK: - KvModifiedResponseGroup

@usableFromInline
struct KvModifiedResponseGroup : KvResponseGroupInternalProtocol {

    @usableFromInline
    typealias SourceProvider = () -> any KvResponseGroup

    @usableFromInline
    typealias Configuration = KvResponseGroupConfiguration


    @usableFromInline
    var configuration: Configuration?

    @usableFromInline
    let sourceProvider: SourceProvider


    @usableFromInline
    init(configuration: Configuration? = nil, source: @escaping SourceProvider) {
        self.configuration = configuration
        self.sourceProvider = source
    }


    // MARK: : KvResponseGroup

    @usableFromInline
    typealias Body = KvNeverResponseGroup


    // MARK: : KvResponseGroupInternalProtocol

    func insertResponses<A : KvResponseAccumulator>(to accumulator: A) {
        switch configuration {
        case .none:
            sourceProvider().insertResponses(to: accumulator)

        case .some(let configuration):
            accumulator.with(configuration) { accumulator in
                sourceProvider().insertResponses(to: accumulator)
            }
        }
    }


    // MARK: : KvModifiedResponseGroupProtocol

    @usableFromInline
    func modified(_ transform: (inout Configuration) -> Void) -> Self {
        var newConfiguration = configuration ?? .empty

        transform(&newConfiguration)

        var copy = self
        copy.configuration = newConfiguration
        return copy
    }

}



// MARK: - KvNeverResponseGroupProtocol

public protocol KvNeverResponseGroupProtocol : KvResponseGroup {

    init()

}


// This approach helps to prevent substituion of `KvNeverResponseGroup` as `Body` in the Xcode's code completion for `body` properties
// when declaring structures conforming to `KvResponseGroup`.
// If body constaint were `Body == KvNeverResponseGroup` then the code completion would always produce `var body: KvNeverResponseGroup`.
extension KvResponseGroup where Body : KvNeverResponseGroupProtocol {

    public var body: Body { Body() }

}



// MARK: - KvNeverResponseGroup

/// Special type for implementations of ``KvResponseGroup`` providing no body.
///
/// - Note: It calls *fatalError()* when instantiated.
public struct KvNeverResponseGroup : KvNeverResponseGroupProtocol {

    public typealias Body = KvNeverResponseGroup


    public init() { fatalError("KvNeverResponseGroup must never be instantiated") }

}
