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
//  KvGroup.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 26.06.2023.
//

import kvHttpKit

import kvKit



/// It's designated to wrap responses and response groups in a root group and then handle it as a single entity.
/// For example modifiers can be applied to whole group.
@inlinable
public func KvRootGroup<Content : KvResponseRootGroup>(
    @KvResponseRootGroupBuilder content: @escaping () -> Content
) -> some KvResponseRootGroup {
    content()
}


/// It's designated to wrap responses and response groups in a group and then handle it as a single entity.
/// For example modifiers can be applied to whole group.
@inlinable
public func KvGroup<Content : KvResponseGroup>(
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup {
    content()
}


// MARK: Network

/// - Returns: A root response group with parameters of HTTP connections for HTTP responses in the group contents.
///
/// - Parameter httpEndpoints: Sequence of network addresses (IP addresses or host names), ports and HTTP protocol configurations.
///
/// Below is an example where the contents are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
///
/// ```swift
/// KvGroup(httpEndpoints: KvNetworkEndpoint.systemEndpoints(on: 8080).lazy.map { ($0, .v2(ssl: ssl)) }) {
///     Contents()
/// }
/// ```
///
/// - Note: By default HTTP responses are available at IPv6 local machine address `::1`, on port 80, via insecure HTTP/1.1.
///
/// - SeeAlso: ``KvGroup(http:at:content:)``, ``KvGroup(http:at:on:content:)``, ``KvResponseRootGroup/http(_:)``.
@inlinable
public func KvGroup<HttpEndpoints, Content : KvResponseRootGroup>(
    httpEndpoints: HttpEndpoints,
    @KvResponseRootGroupBuilder content: @escaping () -> Content
) -> some KvResponseRootGroup
where HttpEndpoints : Sequence, HttpEndpoints.Element == (KvNetworkEndpoint, KvResponseRootGroup.HTTP)
{
    let network: KvResponseRootGroup.Configuration.Network = .init(
        httpEndpoints: .init(uniqueKeysWithValues: httpEndpoints)
    )

    return KvModifiedResponseRootGroup(configuration: .init(network: network), source: content)
}


/// A shorthand for ``KvGroup(httpEndpoints:content:)`` providing the same HTTP configuration on given *endpoints*. See it's documentation for details.
///
/// Below is an example where the contents are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
///
/// ```swift
/// KvGroup(http: .v2(ssl: ssl), at: KvNetworkEndpoint.systemEndpoints(on: 8080)) {
///     Contents()
/// }
/// ```
///
/// - SeeAlso: ``KvResponseRootGroup/http(_:at:)``.
@inlinable
public func KvGroup<Endpoints, Content : KvResponseRootGroup>(
    http: KvResponseRootGroup.HTTP,
    at endpoints: Endpoints,
    @KvResponseRootGroupBuilder content: @escaping () -> Content
) -> some KvResponseRootGroup
where Endpoints : Sequence, Endpoints.Element == KvNetworkEndpoint
{
    KvGroup(httpEndpoints: endpoints.lazy.map { ($0, http) }, content: content)
}


/// A shorthand for ``KvGroup(httpEndpoints:content:)`` providing the same HTTP configuration on all combinations of *addresses* and *ports*. See it's documentation for details.
///
/// Below is an example where the contents are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
///
/// ```swift
/// KvGroup(http: .v2(ssl: ssl), at: KvNetworkEndpoint.systemAddresses, on: [ 8080 ]) {
///     Contents()
/// }
/// ```
///
/// - SeeAlso: ``KvResponseRootGroup/http(_:at:on:)``.
@inlinable
public func KvGroup<Addresses, Ports, Content : KvResponseRootGroup>(
    http: KvResponseRootGroup.HTTP,
    at addresses: Addresses,
    on ports: Ports,
    @KvResponseRootGroupBuilder content: @escaping () -> Content
) -> some KvResponseRootGroup
where Addresses : Sequence, Addresses.Element == KvNetworkEndpoint.Address, Ports : Sequence, Ports.Element == KvNetworkEndpoint.Port
{
    KvGroup(httpEndpoints: KvCartesianProductSequence(addresses, ports).lazy.map { (KvNetworkEndpoint($0, on: $1), http) }, content: content)
}


// MARK: Response Dispatching

/// - Returns: A response group with HTTP method filter containing given elements.
///
/// See ``KvResponseGroup/httpMethods(_:)-7bfx0`` for details.
@inlinable
public func KvGroup<Methods, Content : KvResponseGroup>(
    httpMethods: Methods,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup
where Methods : Sequence, Methods.Element == KvHttpMethod
{
    KvModifiedResponseGroup(configuration: .init(dispatching: .init(httpMethods: .init(httpMethods))), source: content)
}


/// - Returns: A response group with HTTP method filter containing given elements.
///
/// See ``KvResponseGroup/httpMethods(_:)-7bfx0`` for details.
@inlinable
public func KvGroup<Content : KvResponseGroup>(
    httpMethods: KvHttpMethod...,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup {
    KvGroup(httpMethods: httpMethods, content: content)
}


/// - Returns: A response group with user filter containing given elements.
///
/// - Important: HTTP responses are unavailable when user filter is declared.
///
/// See ``KvResponseGroup/users(_:)-48ll0`` for details.
@inlinable
public func KvGroup<Users, Content : KvResponseGroup>(
    users: Users,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup
where Users : Sequence, Users.Element == String
{
    KvModifiedResponseGroup(configuration: .init(dispatching: .init(users: .init(users))), source: content)
}


/// - Returns: A response group with user filter containing given elements.
///
/// - Important: HTTP responses are unavailable when user filter is declared.
///
/// See ``KvResponseGroup/users(_:)-48ll0`` for details.
@inlinable
public func KvGroup<Content : KvResponseGroup>(
    users: String...,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup {
    KvGroup(users: users, content: content)
}


/// A shorthand for ``KvGroup(hosts:hostAliases:optionalSubdomains:content:)-6clfy``.
@inlinable
public func KvGroup<Hosts, HostAliases, OptionalSubdomains, Content : KvResponseRootGroup>(
    hosts: Hosts,
    hostAliases: HostAliases = EmptyCollection<String>(),
    optionalSubdomains: OptionalSubdomains = EmptyCollection<String>(),
    @KvResponseRootGroupBuilder content: @escaping () -> Content
) -> some KvResponseRootGroup
where Hosts : Sequence, Hosts.Element == String,
      HostAliases : Sequence, HostAliases.Element == String,
      OptionalSubdomains : Sequence, OptionalSubdomains.Element == String
{
    KvModifiedResponseRootGroup(
        configuration: .init(dispatching: .init(hosts: .init(hosts),
                                                hostAliases: .init(hostAliases),
                                                optionalSubdomains: .init(optionalSubdomains))),
        source: content
    )
}


/// - Returns: A root response group with given host parameters.
///
/// Host lists of nested response groups are united. Nested lists of hosts are resolved for each response and used to filter requests.
/// If the resolved list is unset then the response available for any or no host.
/// If the resolved list is empty then the responses are ignored.
///
/// Below is an example of typical usage:
///
/// ```swift
/// KvGroup(hosts: "example.com", hostAliases: "example.org", "example.net", optionalSubdomains: "www", "an") {
///     responses
/// }
/// ```
///
/// - SeeAlso: ``KvResponseRootGroup/hosts(_:)-9jenr``, ``KvResponseRootGroup/hosts(aliases:)-6nalk``, ``KvResponseRootGroup/subdomains(optional:)-7x9it``.
@inlinable
public func KvGroup<Content : KvResponseRootGroup>(
    hosts: String...,
    hostAliases: String...,
    optionalSubdomains: String...,
    @KvResponseRootGroupBuilder content: @escaping () -> Content
) -> some KvResponseRootGroup {
    KvGroup(hosts: hosts, hostAliases: hostAliases, optionalSubdomains: optionalSubdomains, content: content)
}


/// Declares relative path to the contents.
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
///     KvGroup("a") {
///         response1           // /a
///     }
///     KvGroup("a") {
///         response2           // /a
///     }
///     KvGroup("b") {
///         response3           // /b
///         KvGroup("c/d") {
///             response4       // /b/c/d
///         }
///     }
///     KvGroup("b/c/e") {
///         response5           // /b/c/e
///     }
/// }
/// ```
///
/// - SeeAlso: ``KvResponseGroup/path(_:)``.
@inlinable
public func KvGroup<Content : KvResponseGroup>(
    _ path: String,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup {
    KvModifiedResponseGroup(configuration: .init(dispatching: .init(path: KvUrlPath(path: path))), source: content)
}
