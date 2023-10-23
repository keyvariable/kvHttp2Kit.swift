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
//  KvResponseRootGroup.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 22.10.2023.
//

import kvKit



// MARK: - KvResponseRootGroup

/// A type that represents top level of hierarchical structure of responses.
///
/// Groups are used to manage their contents as a single entity and to customize handling of responses in the group.
/// Customizations are declared via modifiers of response groups.
/// Also there are various overloads of `KvGroup`() method providing the same functionality in convenient way.
///
/// Some dispatch parameters can be declared only on the top level of response hierarchy.
/// E.g. network endpoints and protocols, host names and aliases.
///
/// Below is an example where `responses1` are available on "example.com" host and "example.org" alias, `responses2` are available on "example.org" only.
///
/// ```swift
/// struct Server : KvServer {
///     var body: some KvResponseRootGroup {
///         KvGroup(hosts: "example.com", hostAliases: "example.org") {
///             responses1
///         }
///         KvGroup(hosts: "example.org") {
///             responses2
///         }
///     }
/// }
/// ```
///
/// - Note: When `responses1` are requested on "example.org" host in the example above, client is redirected to "example.com" host.
///         But no redirection occurs when `responses2` are requested on "example.org" host.
///
/// - SeeAlso: ``KvResponseGroup``.
public protocol KvResponseRootGroup {

    /// It's inferred from your implementation of the required property ``KvResponseRootGroup/body-swift.property``.
    associatedtype Body : KvResponseRootGroup


    /// Incapsulated responses and response groups.
    ///
    /// It's a place to define group's contents.
    @KvResponseRootGroupBuilder
    var body: Body { get }

}


extension KvResponseRootGroup {

    internal var resolvedGroup: any KvResponseRootGroupInternalProtocol {
        (self as? any KvResponseRootGroupInternalProtocol) ?? body.resolvedGroup
    }



    // MARK: Modifiers

    public typealias HTTP = KvHttpConfiguration


    @usableFromInline
    typealias Configuration = KvModifiedResponseRootGroup.Configuration


    @inline(__always)
    @usableFromInline
    func modified(_ transform: (inout Configuration) -> Void) -> some KvResponseRootGroup {
        ((self as? KvModifiedResponseRootGroup) ?? KvModifiedResponseRootGroup(source: { self })).modified(transform)
    }


    /// This modifier declares parameters of HTTP connections for HTTP responses in the group contents.
    ///
    /// - Parameter httpEndpoints: Sequence of network addresses (IP addresses or host names), ports and HTTP protocol configurations.
    ///
    /// Existing values of the contents are replaced with provided values.
    /// Arguments of cascade invocations of the modifier are merged. Existing configurations are replaced with new values on the same endpoints.
    ///
    /// Below is an example where the contents of `responseGroup` are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
    ///
    /// ```swift
    /// responseGroup
    ///     .http(Host.current().addresses.lazy.map { (.init($0, on: 8080), .v2(ssl: ssl)) })
    /// ```
    ///
    /// - Note: By default HTTP responses are available at IPv6 local machine address `::1`, on port 80, via insecure HTTP/1.1.
    ///
    /// - SeeAlso: ``KvHttpConfiguration``, ``KvGroup(httpEndpoints:content:)``, ``http(_:at:)``, ``http(_:at:on:)``.
    @inlinable
    public func http<HttpEndpoints>(_ httpEndpoints: HttpEndpoints) -> some KvResponseRootGroup
    where HttpEndpoints : Sequence, HttpEndpoints.Element == (KvNetworkEndpoint, HTTP)
    {
        modified { configuration in
            configuration.network?.insert(httpEndpoints)
            ?? (configuration.network = .init(httpEndpoints: .init(uniqueKeysWithValues: httpEndpoints)))
        }
    }


    /// A shorthand for ``http(_:)`` modifier providing the same HTTP configuration on given *endpoints*. See it's documentation for details.
    ///
    /// Below is an example where the contents of `responseGroup` are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
    ///
    /// ```swift
    /// responseGroup
    ///     .http(.v2(ssl: ssl), at: Host.current().addresses.lazy.map { .init($0, on: 8080) })
    /// ```
    ///
    /// - SeeAlso: ``KvHttpConfiguration``, ``KvGroup(http:at:content:)``.
    @inlinable
    public func http<Endpoints>(_ http: HTTP = .init(), at endpoints: Endpoints) -> some KvResponseRootGroup
    where Endpoints : Sequence, Endpoints.Element == KvNetworkEndpoint
    {
        self.http(endpoints.lazy.map { ($0, http) })
    }


    /// A shorthand for ``http(_:)`` modifier providing the same HTTP configuration on all combinations of *addresses* and *ports*. See it's documentation for details.
    ///
    /// Below is an example where the contents of `responseGroup` are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
    ///
    /// ```swift
    /// responseGroup
    ///     .http(.v2(ssl: ssl), at: Host.current().addresses, on: [ 8080 ])
    /// ```
    ///
    /// - SeeAlso: ``KvHttpConfiguration``, ``KvGroup(http:at:on:content:)``.
    @inlinable
    public func http<Addresses, Ports>(
        _ http: HTTP = .init(),
        at addresses: Addresses,
        on ports: Ports
    ) -> some KvResponseRootGroup
    where Addresses : Sequence, Addresses.Element == String,
          Ports : Sequence, Ports.Element == UInt16
    {
        self.http(http, at: KvCartesianProductSequence(addresses, ports).lazy.map { KvNetworkEndpoint($0.0, on: $0.1) })
    }


    /// This modifier adds given values into list of hosts.
    ///
    /// This is an overload of ``KvResponseRootGroup/hosts(_:)-9jenr``.
    /// See it's documentation for details.
    @inlinable
    public func hosts<Hosts>(_ hosts: Hosts) -> some KvResponseRootGroup
    where Hosts : Sequence, Hosts.Element == String
    {
        modified {
            $0.dispatching?.hosts.formUnion(hosts)
            ?? ($0.dispatching = .init(hosts: .init(hosts)))
        }
    }


    /// This modifier adds given values into list of hosts.
    ///
    /// This is an overload of ``KvResponseRootGroup/hosts(_:)-9jenr``.
    /// See it's documentation for details.
    @inlinable
    public func hosts(_ hosts: Set<String>) -> some KvResponseRootGroup {
        modified {
            $0.dispatching?.hosts.formUnion(hosts)
            ?? ($0.dispatching = .init(hosts: hosts))
        }
    }


    /// This modifier adds given values into list of hosts the group content is available on.
    ///
    /// By default list of hosts is unset.
    /// Host lists of nested response groups are united.
    /// If the resolved list is empty then the group contents are ignored.
    /// If the resolved list is unset then the group contents are available for any host.
    ///
    /// Below is an example where `responseRootGroup` is available at "example.com" host
    /// and requests are redirected from "example.org", "example.net" hosts and all the hosts prefixed with "www." and "an.".
    ///
    /// ```swift
    /// responseRootGroup
    ///     .hosts("example.com")
    ///     .hosts(aliases: "example.org", "example.net")
    ///     .subdomains(optional: "www", "an")
    /// ```
    ///
    /// - SeeAlso: ``KvGroup(hosts:hostAliases:optionalSubdomains:content:)-6clfy``, ``KvResponseRootGroup/hosts(aliases:)-6nalk``,
    ///            ``KvResponseRootGroup/subdomains(optional:)-7x9it``.
    @inlinable
    public func hosts(_ hosts: String...) -> some KvResponseRootGroup {
        self.hosts(hosts)
    }


    /// This modifier adds given values into list of host aliases.
    ///
    /// This is an overload of ``KvResponseRootGroup/hosts(aliases:)-6nalk``.
    /// See it's documentation for details.
    @inlinable
    public func hosts<Hosts>(aliases hostAliases: Hosts) -> some KvResponseRootGroup
    where Hosts : Sequence, Hosts.Element == String
    {
        modified {
            $0.dispatching?.hostAliases.formUnion(hostAliases)
            ?? ($0.dispatching = .init(hostAliases: .init(hostAliases)))
        }
    }


    /// This modifier adds given values into list of host aliases.
    ///
    /// This is an overload of ``KvResponseRootGroup/hosts(aliases:)-6nalk``.
    /// See it's documentation for details.
    @inlinable
    public func hosts(aliases hostAliases: Set<String>) -> some KvResponseRootGroup {
        modified {
            $0.dispatching?.hostAliases.formUnion(hostAliases)
            ?? ($0.dispatching = .init(hostAliases: .init(hostAliases)))
        }
    }


    /// This modifier adds given values into list of host aliases.
    ///
    /// By default list of host aliases is empty.
    /// Host alias lists of nested response groups are united.
    /// If the resolved list of host aliases is non-empty then server redirects clients to first element of the host list.
    ///
    /// Below is an example where `responseRootGroup` is available at "example.com" host
    /// and requests are redirected from "example.org", "example.net" hosts and all the hosts prefixed with "www." and "an.".
    ///
    /// ```swift
    /// responseRootGroup
    ///     .hosts("example.com")
    ///     .hosts(aliases: "example.org", "example.net")
    ///     .subdomains(optional: "www", "an")
    /// ```
    ///
    /// - SeeAlso: ``KvGroup(hosts:hostAliases:optionalSubdomains:content:)-6clfy``, ``KvResponseRootGroup/hosts(_:)-9jenr``,
    ///            ``KvResponseRootGroup/subdomains(optional:)-7x9it``.
    @inlinable
    public func hosts(aliases hostAliases: String...) -> some KvResponseRootGroup {
        self.hosts(aliases: hostAliases)
    }


    /// This modifier adds given values into list of optional subdomains.
    ///
    /// This is an overload of  ``KvResponseRootGroup/subdomains(optional:)-7x9it``.
    /// See it's documentation for details.
    @inlinable
    public func subdomains<Subdomains>(optional subdomains: Subdomains) -> some KvResponseRootGroup
    where Subdomains : Sequence, Subdomains.Element == String
    {
        modified {
            $0.dispatching?.optionalSubdomains.formUnion(subdomains)
            ?? ($0.dispatching = .init(optionalSubdomains: .init(subdomains)))
        }
    }


    /// This modifier adds given values into list of optional subdomains.
    ///
    /// This is an overload of  ``KvResponseRootGroup/subdomains(optional:)-7x9it``.
    /// See it's documentation for details.
    @inlinable
    public func subdomains(optional subdomains: Set<String>) -> some KvResponseRootGroup {
        modified {
            $0.dispatching?.optionalSubdomains.formUnion(subdomains)
            ?? ($0.dispatching = .init(optionalSubdomains: subdomains))
        }
    }


    /// This modifier adds given values into list of optional subdomains.
    ///
    /// By default list of optional subdomains is empty.
    /// Optional subdomain lists of nested response groups are united.
    /// If the resolved list of optional subdomains is non-empty
    /// then server redirects clients to first element of the host list from all elements of both host and host alias lists prefixed with each optional subdomain.
    ///
    ///
    /// Below is an example where `responseRootGroup` is available at "example.com" host
    /// and requests are redirected from "example.org", "example.net" hosts and all the hosts prefixed with "www." and "an.".
    ///
    /// ```swift
    /// responseRootGroup
    ///     .hosts("example.com")
    ///     .hosts(aliases: "example.org", "example.net")
    ///     .subdomains(optional: "www", "an")
    /// ```
    ///
    /// - SeeAlso: ``KvGroup(hosts:hostAliases:optionalSubdomains:content:)-6clfy``, ``KvResponseRootGroup/hosts(_:)-9jenr``,
    ///            ``KvResponseRootGroup/hosts(aliases:)-6nalk``.
    @inlinable
    public func subdomains(optional subdomains: String...) -> some KvResponseRootGroup {
        self.subdomains(optional: subdomains)
    }

}



// MARK: - KvResponseRootGroupConfiguration

@usableFromInline
struct KvResponseRootGroupConfiguration : KvDefaultOverlayCascadable, KvDefaultAccumulationCascadable {

    @usableFromInline
    static let empty: Self = .init()


    @usableFromInline
    var network: Network?

    @usableFromInline
    var dispatching: Dispatching?


    @usableFromInline
    init(network: Network? = nil,
         dispatching: Dispatching? = nil
    ) {
        self.network = network
        self.dispatching = dispatching
    }


    // MARK: : KvCascadable

    @usableFromInline
    static func overlay(_ addition: Self, over base: Self) -> Self { .init(
        network: .overlay(addition.network, over: base.network),
        dispatching: .overlay(addition.dispatching, over: base.dispatching)
    ) }


    @usableFromInline
    static func accumulate(_ addition: Self, into base: Self) -> Self { .init(
        network: .accumulate(addition.network, into: base.network),
        dispatching: .accumulate(addition.dispatching, into: base.dispatching)
    ) }


    // MARK: .Network

    @usableFromInline
    struct Network : KvDefaultOverlayCascadable, KvDefaultAccumulationCascadable {

        @usableFromInline
        typealias Address = String

        @usableFromInline
        typealias Port = UInt16


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


        // MARK: : KvCascadable

        @usableFromInline
        static func accumulate(_ addition: Self, into base: Self) -> Self {
            var result = base

            result.protocolIDs.merge(addition.protocolIDs, uniquingKeysWith: { base, addition in addition })
            addition.httpEndpoints.configurations.forEach {
                result.httpEndpoints.insert($0.value, for: $0.key)
            }

            return result
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
    struct Dispatching : KvDefaultOverlayCascadable, KvDefaultAccumulationCascadable {

        /// Primary hosts. Responses are available on primary hosts without redirections.
        ///
        /// - Important: Redirections are performed to first primary host.
        ///
        /// - Note: Empty set means any host.
        @usableFromInline
        var hosts: Set<String>

        /// - Note: Empty set means any host.
        @usableFromInline
        var hostAliases: Set<String>

        @usableFromInline
        var optionalSubdomains: Set<String>


        @usableFromInline
        init(hosts: Set<String> = [ ],
             hostAliases: Set<String> = [ ],
             optionalSubdomains: Set<String> = [ ]
        ) {
            self.hosts = hosts
            self.hostAliases = hostAliases
            self.optionalSubdomains = optionalSubdomains
        }


        // MARK: : KvCascadable

        @usableFromInline
        static func accumulate(_ addition: Self, into base: Self) -> Self {
            .init(hosts: base.hosts.union(addition.hosts),
                  hostAliases: base.hostAliases.union(addition.hostAliases),
                  optionalSubdomains: base.optionalSubdomains.union(addition.optionalSubdomains))
        }

    }

}



// MARK: - KvResponseRootGroupInternalProtocol

protocol KvResponseRootGroupInternalProtocol : KvResponseRootGroup {

    func insertResponses<A : KvHttpResponseAccumulator>(to accumulator: A)

}



// MARK: - KvModifiedResponseRootGroup

@usableFromInline
struct KvModifiedResponseRootGroup : KvResponseRootGroupInternalProtocol {

    @usableFromInline
    typealias SourceProvider = () -> any KvResponseRootGroup

    @usableFromInline
    typealias Configuration = KvResponseRootGroupConfiguration


    @usableFromInline
    var configuration: Configuration?

    @usableFromInline
    let sourceProvider: SourceProvider


    @usableFromInline
    init(configuration: Configuration? = nil, source: @escaping SourceProvider) {
        self.configuration = configuration
        self.sourceProvider = source
    }


    // MARK: : KvResponseRootGroup

    @usableFromInline
    var body: KvNeverResponseRootGroup { KvNeverResponseRootGroup() }


    // MARK: : KvResponseRootGroupInternalProtocol

    func insertResponses<A : KvHttpResponseAccumulator>(to accumulator: A) {

        @inline(__always)
        func Insert<Accumulator>(to accumulator: Accumulator) where Accumulator : KvHttpResponseAccumulator {
            sourceProvider().resolvedGroup.insertResponses(to: accumulator)
        }


        switch configuration {
        case .none:
            Insert(to: accumulator)

        case .some(let configuration):
            accumulator.with(configuration, body: Insert(to:))
        }
    }


    // MARK: : KvModifiedResponseRootGroupProtocol

    @usableFromInline
    func modified(_ transform: (inout Configuration) -> Void) -> Self {
        var newConfiguration = configuration ?? .empty

        transform(&newConfiguration)

        var copy = self
        copy.configuration = newConfiguration
        return copy
    }

}



// MARK: - KvNeverResponseRootGroup

/// Special type for implementations of ``KvResponseRootGroup`` providing no body.
///
/// - Note: It calls *fatalError()* when instantiated.
public struct KvNeverResponseRootGroup : KvResponseRootGroup {

    public typealias Body = KvNeverResponseRootGroup


    init() { fatalError("KvNeverResponseRootGroup must never be instantiated") }


    public var body: Body { Body() }

}



// MARK: - KvEmptyResponseRootGroup

/// It's designated to explicitly declare empty response root groups.
public struct KvEmptyResponseRootGroup : KvResponseRootGroup {

    public typealias Body = KvNeverResponseRootGroup


    @inlinable
    public init() { }


    public var body: Body { Body() }

}


// MARK: : KvResponseRootGroupInternalProtocol

extension KvEmptyResponseRootGroup : KvResponseRootGroupInternalProtocol {

    func insertResponses<A : KvHttpResponseAccumulator>(to accumulator: A) {
        // Nothing to do
    }

}
