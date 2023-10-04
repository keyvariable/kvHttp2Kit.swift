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

import kvKit
import NIOHTTP1



/// It's designated to wrap responses and response groups in a group and then handle it as a signle entity.
/// For example modifiers can be applied to whole group.
@inlinable
public func KvGroup<Content : KvResponseGroup>(
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup {
    content()
}


// MARK: Network

/// Declares parameters of HTTP connections for HTTP responses in the group contents. Existing values of the contents are replaced with provided values.
///
/// - Parameter httpEndpoints: Sequence of network addresses (IP addresses or host names), ports and HTTP protocol configurations.
///
/// Below is an example where the contents are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
///
/// ```swift
/// KvGroup(httpEndpoints: Host.current().addresses.lazy.map { (.init($0, on: 8080), .v2(ssl: ssl)) }) {
///     Contents()
/// }
/// ```
///
/// See: ``KvGroup(http:at:content:)``, ``KvGroup(http:at:on:content:)``, ``KvResponseGroup/http(_:)``.
///
/// - Note: By default HTTP responses are available at IPv6 local machine address `::1`, on port 80, via insecure HTTP/1.1.
@inlinable
public func KvGroup<HttpEndpoints, Content : KvResponseGroup>(
    httpEndpoints: HttpEndpoints,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup
where HttpEndpoints : Sequence, HttpEndpoints.Element == (KvNetworkEndpoint, KvResponseGroup.HTTP)
{
    let network: KvResponseGroup.Configuration.Network = .init(
        httpEndpoints: .init(uniqueKeysWithValues: httpEndpoints)
    )

    return KvModifiedResponseGroup(configuration: .init(network: network), source: content)
}


/// A shorthand for ``KvGroup(httpEndpoints:content:)`` providing the same HTTP configuration on given *endpoints*. See it's documentation for details.
///
/// Below is an example where the contents are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
///
/// ```swift
/// KvGroup(http: .v2(ssl: ssl), at: Host.current().addresses.lazy.map { .init($0, on: 8080) }) {
///     Contents()
/// }
/// ```
///
/// See: ``KvResponseGroup/http(_:at:)``.
@inlinable
public func KvGroup<Endpoints, Content : KvResponseGroup>(
    http: KvResponseGroup.HTTP,
    at endpoints: Endpoints,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup
where Endpoints : Sequence, Endpoints.Element == KvNetworkEndpoint
{
    KvGroup(httpEndpoints: endpoints.lazy.map { ($0, http) }, content: content)
}


/// A shorthand for ``KvGroup(httpEndpoints:content:)`` providing the same HTTP configuration on all combinations of *addresses* and *ports*. See it's documentation for details.
///
/// Below is an example where the contents are available at all the current machine's IP addresses on port 8080 via secure HTTP/2.0:
///
/// ```swift
/// KvGroup(http: .v2(ssl: ssl), at: Host.current().addresses, on: [ 8080 ]) {
///     Contents()
/// }
/// ```
///
/// See: ``KvResponseGroup/http(_:at:on:)``.
@inlinable
public func KvGroup<Addresses, Ports, Content : KvResponseGroup>(
    http: KvResponseGroup.HTTP,
    at addresses: Addresses,
    on ports: Ports,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup
where Addresses : Sequence, Addresses.Element == KvNetworkEndpoint.Address, Ports : Sequence, Ports.Element == KvNetworkEndpoint.Port
{
    KvGroup(httpEndpoints: KvCartesianProductSequence(addresses, ports).lazy.map { (KvNetworkEndpoint($0, on: $1), http) }, content: content)
}


// MARK: Response Dispatching

/// Adds given values into list of HTTP methods.
///
/// The result is the same as ``KvGroup(httpMethods:content:)-29gzp``. See it's documentation for details.
@inlinable
public func KvGroup<Methods, Content : KvResponseGroup>(
    httpMethods: Methods,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup
where Methods : Sequence, Methods.Element == KvHttpMethod
{
    KvModifiedResponseGroup(configuration: .init(dispatching: .init(httpMethods: Set(httpMethods))), source: content)
}


/// Adds given values into list of HTTP methods.
///
/// HTTP method lists of nested response groups are united. Nested lists of HTTP methods are resolved for each HTTP response and used to filter HTTP requests.
/// If the resolved list is empty then the response available for any HTTP method.
///
/// Below is an example of typical usage:
///
/// ```swift
/// KvGroup(httpMethods: .GET, .PUT, .DELETE) {
///     HttpResponses()
/// }
/// ```
///
/// Below is an example where `Response1` is available for `.GET`, `.PUT` and `.DELETE` HTTP methods but `Response2` is available only for `.GET` and `.PUT` HTTP methods.
///
/// ```swift
/// KvGroup(httpMethods: .GET, .PUT) {
///     KvGroup(httpMethods: .DELETE) {
///         Response1()
///     }
///     Response2()
/// }
/// ```
///
/// See: ``KvResponseGroup/httpMethods(_:)-6fbma``.
@inlinable
public func KvGroup<Content : KvResponseGroup>(
    httpMethods: KvHttpMethod...,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup {
    KvGroup(httpMethods: httpMethods, content: content)
}


/// Adds given values into list of users.
///
/// The result is the same as ``KvGroup(users:content:)-3140o``. See it's documentation for details.
@inlinable
public func KvGroup<Users, Content : KvResponseGroup>(
    users: Users,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup
where Users : Sequence, Users.Element == String
{
    KvModifiedResponseGroup(configuration: .init(dispatching: .init(users: .init(users))), source: content)
}


/// Adds given values into list of users.
///
/// User lists of nested response groups are united. Nested lists of users are resolved for each response and used to filter requests.
/// If the resolved list is empty then the response available for any or no user.
///
/// Usually user is provided as a component of an URL and separated from domain component by "@" character.
///
/// Below is an example of typical usage:
///
/// ```swift
/// KvGroup(users: "user1", "user2") {
///     Responses()
/// }
/// ```
///
/// Below is an example where `Response1` is available for "user1", "user2" and "admin" users but `Response2` is available only for "user1" and "user2" users.
///
/// ```swift
/// KvGroup(users: "user1", "user2") {
///     KvGroup(users: "admin") {
///         Response1()
///     }
///     Response2()
/// }
/// ```
///
/// See: ``KvResponseGroup/users(_:)-48ll0``.
@inlinable
public func KvGroup<Content : KvResponseGroup>(
    users: String...,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup {
    KvGroup(users: users, content: content)
}


/// Adds given values into list of hosts.
///
/// Host lists of nested response groups are united. Nested lists of hosts are resolved for each response and used to filter requests.
/// If the resolved list is empty then the response available for any or no host.
///
/// Usually host is provided as a component of an URL.
///
/// See ``KvGroup(hosts:content:)-872vb`` for examples.
///
/// See: ``KvResponseGroup/hosts(_:)-3ilz3``.
@inlinable
public func KvGroup<Hosts, Content : KvResponseGroup>(
    hosts: Hosts,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup
where Hosts : Sequence, Hosts.Element == String
{
    KvModifiedResponseGroup(configuration: .init(dispatching: .init(hosts: .init(hosts))), source: content)
}


/// Adds given values into list of hosts.
///
/// Host lists of nested response groups are united. Nested lists of hosts are resolved for each response and used to filter requests.
/// If the resolved list is empty then the response available for any or no host.
///
/// Usually host is provided as a component of an URL.
///
/// Below is an example of typical usage:
///
/// ```swift
/// KvGroup(hosts: "example.com", "example.org") {
///     Responses()
/// }
/// ```
///
/// Below is an example where `Response1` is available for "user1", "user2" and "admin" users but `Response2` is available only for "user1" and "user2" users.
///
/// ```swift
/// KvGroup(users: "user1", "user2") {
///     KvGroup(users: "admin") {
///         Response1()
///     }
///     Response2()
/// }
/// ```
///
/// See: ``KvResponseGroup/hosts(_:)-1pv6b``.
@inlinable
public func KvGroup<Content : KvResponseGroup>(
    hosts: String...,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup {
    KvGroup(hosts: hosts, content: content)
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
/// See: ``KvResponseGroup/path(_:)``.
@inlinable
public func KvGroup<Content : KvResponseGroup>(
    _ path: String,
    @KvResponseGroupBuilder content: @escaping () -> Content
) -> some KvResponseGroup {
    KvModifiedResponseGroup(configuration: .init(dispatching: .init(path: path)), source: content)
}
