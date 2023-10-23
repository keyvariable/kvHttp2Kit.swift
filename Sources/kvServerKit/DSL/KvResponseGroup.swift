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
/// Customizations are declared via modifiers of response groups.
/// Also there are various overloads of `KvGroup`() method providing the same functionality in convenient way.
///
/// Below is an example where `response1` is available at "a" path, `response2` is available at "a/b" path and both responses are available for GET method only.
///
/// ```swift
/// KvGroup(httpMethods: .GET) {
///     KvGroup("a") {
///         response1
///         KvGroup("b") {
///             response2
///         }
///     }
/// }
/// ```
///
/// Below is a more complicated example where response group is used to incapsulate some part of response hierarchy with options.
///
/// ```swift
/// struct TestableServer : KvServer {
///     var body: some KvResponseRootGroup {
///         ResponseGroup(options: [ ])
///         ResponseGroup(options: .testMode)
///     }
///
///     private struct ResponseGroup : KvResponseGroup {
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
///
/// - SeeAlso: ``KvResponseRootGroup``.
public protocol KvResponseGroup {

    /// It's inferred from your implementation of the required property ``KvResponseGroup/body-swift.property``.
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



    internal var resolvedGroup: any KvResponseGroupInternalProtocol {
        (self as? any KvResponseGroupInternalProtocol) ?? body.resolvedGroup
    }



    // MARK: Modifiers

    @usableFromInline
    typealias Configuration = KvModifiedResponseGroup.Configuration


    @inline(__always)
    @usableFromInline
    func modified(_ transform: (inout Configuration) -> Void) -> some KvResponseGroup {
        ((self as? KvModifiedResponseGroup) ?? KvModifiedResponseGroup(source: { self })).modified(transform)
    }


    /// Adds given values into HTTP method filter.
    ///
    /// The result is the same as ``KvResponseGroup/httpMethods(_:)-6fbma``. See it's documentation for details.
    @inlinable
    public func httpMethods<Methods>(_ httpMethods: Methods) -> some KvResponseGroup
    where Methods : Sequence, Methods.Element == KvHttpMethod
    {
        modified {
            $0.dispatching?.insert(httpMethods: httpMethods)
            ?? ($0.dispatching = .init(httpMethods: .init(httpMethods)))
        }
    }


    /// This modifier adds given values into HTTP method filter.
    ///
    /// By default HTTP method filter accepts any value. Once this modifier is called, the filter is cleared and provided values are inserted.
    ///
    /// HTTP method filters of nested response groups are intersected. Nested filters by HTTP methods are resolved for each HTTP response and used to filter HTTP requests.
    /// If the resolved filter is empty then the response is ignored.
    ///
    /// Below is a simple example:
    ///
    /// ```swift
    /// SomeResponseGroup()
    ///     .httpMethods(.GET, .PUT, .DELETE)
    /// ```
    ///
    /// - SeeAlso: ``KvGroup(httpMethods:content:)-29gzp``.
    @inlinable
    public func httpMethods(_ httpMethods: KvHttpMethod...) -> some KvResponseGroup {
        self.httpMethods(httpMethods)
    }


    /// This modifier adds given values into URL filter by user.
    ///
    /// The result is the same as ``KvResponseGroup/users(_:)-48ll0``. See it's documentation for details.
    @inlinable
    public func users<Users>(_ users: Users) -> some KvResponseGroup
    where Users : Sequence, Users.Element == String
    {
        modified {
            $0.dispatching?.insert(users: users)
            ?? ($0.dispatching = .init(users: .init(users)))
        }
    }


    /// This modifier adds given values into URL filter by user.
    ///
    /// By default user filter accepts any value. Once this modifier is called, the filter is cleared and provided values are inserted.
    ///
    /// User filters of nested response groups are intersected. Nested filters by users are resolved for each response and used to filter requests.
    /// If the resolved filter is empty then the response is ignored.
    ///
    /// Usually user is provided as a component of an URL and separated from domain component by "@" character.
    ///
    /// - Important: HTTP responses are unavailable when user filter is declared.
    ///
    /// Below is a simple example:
    ///
    /// ```swift
    /// SomeResponseGroup()
    ///     .users("user1", "user2")
    /// ```
    ///
    /// - SeeAlso: ``KvGroup(users:content:)-3140o``.
    @inlinable
    public func users(_ users: String...) -> some KvResponseGroup {
        self.users(users)
    }


    /// This modifier appends the group's relative path to it's contents.
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
    /// - SeeAlso: ``KvGroup(_:content:)``.
    @inlinable
    public func path(_ pathComponent: String) -> some KvResponseGroup {
        modified {
            $0.dispatching?.appendPathComponent(pathComponent)
            ?? ($0.dispatching = .init(path: pathComponent))
        }
    }


    /// This modifier declares default body length limit in bytes for HTTP requests in the receiver and it's descendant groups.
    ///
    /// Previously declared value is replaced.
    ///
    /// - SeeAlso: ``KvHttpRequestRequiredBody/bodyLengthLimit(_:)``.
    @inlinable
    public func httpBodyLengthLimit(_ value: UInt) -> some KvResponseGroup {
        modified {
            _ = {
                switch $0 {
                case .none:
                    $0 = .init(bodyLengthLimit: value)
                case .some:
                    $0!.bodyLengthLimit = value
                }
            }(&$0.httpRequestBody)
        }
    }


    /// This modifier declares handler of incidents in the receiver's context. It's a place to customize default response content.
    ///
    /// - Parameter block:  A block returning custom response or `nil` for given *incident*.
    ///                     If `nil` is returned then ``KvHttpIncident/defaultStatus`` is submitted to client.
    ///
    /// Previously declared value is replaced.
    ///
    /// Below is an example where custom 404 (Not Found) response is provided for any subpath of */a* path:
    ///
    /// ```swift
    /// KvGroup("a") {
    ///     responses
    /// }
    /// .onHttpIncident { incident in
    ///     guard incident.defaultStatus == .notFound else { return nil }
    ///     return try .notFound
    ///         .file(at: htmlFileURL)
    ///         .contentType(.text(.html))
    /// }
    /// ```
    ///
    /// Incident handlers can be provided for particular responses with ``KvHttpResponse/onIncident(_:)``.
    ///
    /// - SeeAlso: ``onError(_:)``.
    @inlinable
    public func onHttpIncident(_ block: @escaping (KvHttpIncident, KvHttpRequestContext) throws -> KvHttpResponseProvider?) -> some KvResponseGroup {
        modified {
            $0.clientCallbacks = .accumulate(.init(onHttpIncident: { try? block($0, $1) }), into: $0.clientCallbacks)
        }
    }


    /// This modifier declares callback for errors in the receiver's context.
    ///
    /// Previously declared value is replaced.
    ///
    /// Error callbacks can be provided for particular responses with ``KvHttpResponse/onError(_:)``.
    ///
    /// - SeeAlso: ``onHttpIncident(_:)``.
    @inlinable
    public func onError(_ block: @escaping (Error, KvHttpRequestContext) -> Void) -> some KvResponseGroup {
        modified {
            $0.clientCallbacks = .accumulate(.init(onError: block), into: $0.clientCallbacks)
        }
    }

}



// MARK: - KvResponseGroupConfiguration

@usableFromInline
struct KvResponseGroupConfiguration : KvDefaultOverlayCascadable, KvDefaultAccumulationCascadable {

    @usableFromInline
    static let empty: Self = .init()


    @usableFromInline
    var dispatching: Dispatching?

    @usableFromInline
    var httpRequestBody: HttpRequestBody?

    @usableFromInline
    var clientCallbacks: KvClientCallbacks?


    @usableFromInline
    init(dispatching: Dispatching? = nil,
         httpRequestBody: HttpRequestBody? = nil,
         clientCallbacks: KvClientCallbacks? = nil
    ) {
        self.dispatching = dispatching
        self.httpRequestBody = httpRequestBody
        self.clientCallbacks = clientCallbacks
    }


    // MARK: : KvCascadable

    @usableFromInline
    static func overlay(_ addition: Self, over base: Self) -> Self {
        .init(dispatching: .overlay(addition.dispatching, over: base.dispatching),
              httpRequestBody: .overlay(addition.httpRequestBody, over: base.httpRequestBody),
              clientCallbacks: .overlay(addition.clientCallbacks, over: base.clientCallbacks)
        )
    }


    @usableFromInline
    static func accumulate(_ addition: Self, into base: Self) -> Self {
        .init(dispatching: .accumulate(addition.dispatching, into: base.dispatching),
              httpRequestBody: .accumulate(addition.httpRequestBody, into: base.httpRequestBody),
              clientCallbacks: .accumulate(addition.clientCallbacks, into: base.clientCallbacks)
        )
    }


    // MARK: .Dispatching

    @usableFromInline
    struct Dispatching : KvDefaultOverlayCascadable, KvDefaultAccumulationCascadable {

        /// - Note: `nil` means any method.
        @usableFromInline
        var httpMethods: CascadableSet<KvHttpMethod>?

        /// - Note: `nil` means any user.
        @usableFromInline
        var users: CascadableSet<String>?

        /// - SeeAlso: ``appendPathComponent(_:)``.
        @usableFromInline
        private(set) var path: String


        @usableFromInline
        init(httpMethods: CascadableSet<KvHttpMethod>? = nil,
             users: CascadableSet<String>? = nil,
             path: String = ""
        ) {
            self.httpMethods = httpMethods
            self.users = users
            self.path = Self.normalizedPath(path)
        }


        // MARK: : KvCascadable

        @usableFromInline
        static func overlay(_ addition: Self, over base: Self) -> Self {
            .init(httpMethods: .overlay(addition.httpMethods, over: base.httpMethods),
                  users: .overlay(addition.users, over: base.users),
                  path: base.path + addition.path)    // Assuming paths are safe and always have leading path separators
        }


        @usableFromInline
        static func accumulate(_ addition: Self, into base: Self) -> Self {
            .init(httpMethods: .accumulate(addition.httpMethods, into: base.httpMethods),
                  users: .accumulate(addition.users, into: base.users),
                  path: base.path + addition.path)    // Assuming paths are safe and always have leading path separators
        }


        // MARK: .CascadableSet

        @usableFromInline
        struct CascadableSet<T : Hashable> : KvDefaultOverlayCascadable, KvDefaultAccumulationCascadable {

            private(set) var elements: Set<T>


            @usableFromInline
            init<Elements>(_ elements: Elements) where Elements : Sequence, Elements.Element == T {
                self.elements = .init(elements)
            }

            @usableFromInline
            init(_ elements: Set<T>) {
                self.elements = elements
            }


            // MARK: : KvCascadable

            @usableFromInline
            static func overlay(_ addition: Self, over base: Self) -> Self {
                .init(base.elements.intersection(addition.elements))
            }


            @usableFromInline
            static func accumulate(_ addition: Self, into base: Self) -> Self {
                .init(base.elements.union(addition.elements))
            }


            // MARK: Operations

            @usableFromInline
            mutating func insert<Elements>(_ elements: Elements) where Elements : Sequence, Elements.Element == T {
                self.elements.formUnion(elements)
            }

        }


        // MARK: Operations

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
        mutating func insert<HttpMethods>(httpMethods: HttpMethods)
        where HttpMethods : Sequence, HttpMethods.Element == KvHttpMethod
        {
            self.httpMethods?.insert(httpMethods)
            ?? (self.httpMethods = .init(httpMethods))
        }


        @inline(__always)
        @usableFromInline
        mutating func insert<Users>(users: Users)
        where Users : Sequence, Users.Element == String
        {
            self.users?.insert(users)
            ?? (self.users = .init(users))
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

    func insertResponses<A : KvHttpResponseAccumulator>(to accumulator: A)

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
    var body: KvNeverResponseGroup { KvNeverResponseGroup() }


    // MARK: : KvResponseGroupInternalProtocol

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



// MARK: - KvNeverResponseGroup

/// Special type for implementations of ``KvResponseGroup`` providing no body.
///
/// - Note: It calls *fatalError()* when instantiated.
public struct KvNeverResponseGroup : KvResponseGroup {

    public typealias Body = KvNeverResponseGroup


    init() { fatalError("KvNeverResponseGroup must never be instantiated") }


    public var body: Body { Body() }

}



// MARK: - KvEmptyResponseGroup

/// It's designated to explicitly declare empty response groups.
public struct KvEmptyResponseGroup : KvResponseGroup {

    public typealias Body = KvNeverResponseGroup


    @inlinable
    public init() { }


    public var body: Body { Body() }

}


// MARK: : KvResponseGroupInternalProtocol

extension KvEmptyResponseGroup : KvResponseGroupInternalProtocol {

    func insertResponses<A : KvHttpResponseAccumulator>(to accumulator: A) {
        // Nothing to do
    }

}
