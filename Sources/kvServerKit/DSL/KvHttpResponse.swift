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
//  KvHttpResponse.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 11.06.2023.
//

import Foundation

import kvHttpKit

import NIOHTTP1



// MARK: - KvHttpResponse

/// A type representing HTTP responses.
///
/// Simple responses are just instantiated:
///
/// ```swift
/// KvHttpResponse { .string { ISO8601DateFormatter().string(from: Date()) } }
/// ```
///
/// Simple responses can return dynamic content like current date in example above.
/// But they don't depend on URL query, request headers and body.
/// These request arguments can be handled with parameterized responses.
/// Parameterized responses are declared with ``with`` static property and modifiers:
///
/// ```swift
/// KvHttpResponse.with
///     .requestBody(.json(of: DateComponents.self))
///     .content {
///         guard let date = $0.requestBody.date else { return .badRequest }
///         return .string { ISO8601DateFormatter().string(from: date) }
///     }
/// ```
///
/// Declaration in example above decodes `DateComponents` from JSON representation in request body and responds with date string in ISO8601 format.
///
/// Parameterized responses provide custom and structured handling of URL queries.
/// Structured handling of URL queries is a powerful way to produce short and well readable declarations with input validation.
///
/// *kvServerKit* is able to dispatch requests to multiple HTTP responses with the same HTTP method, user, host, and path but different URL queries.
/// In this case *kvServerKit* provides fast single-pass dispatching for HTTP responses with structured handling of URL queries.
/// If there are HTTP responses with custom handling of URL query then the entire query is passed to all the responses.
///
/// The dispatch process is aborted if second matching response is encountered.
/// Status codes 404 (Not Found) and 400 (Bad Request) are returned to the client when there is no matching response or there are several matching responses for an HTTP request.
///
/// Below is an example of three unambiguous HTTP responses for requests having all the same dispatch parameters but URL query component:
///
/// ```swift
/// KvHttpResponse.with
///     .query(.required("from", of: Float.self))
///     .query(.optional("to", of: Float.self))
///     .content {
///         switch $0.query {
///         case (let from, .none):
///             return .string { "\(from) ..." }
///         case (let from, .some(let to)):
///             return .string { "\(from) ..< \(to)" }
///         }
///     }
/// KvHttpResponse.with
///     .query(.required("to", of: Float.self))
///     .content { input in
///         .string { "..< \(input.query)" }
///     }
/// KvHttpResponse.with
///     .query(.optional("from", of: Float.self))
///     .query(.required("through", of: Float.self))
///     .content {
///         switch $0.query {
///         case (.none, let through):
///             return .string { "... \(through)" }
///         case (.some(let from), let through):
///             return .string { "\(from) ... \(through)" }
///         }
///     }
/// ```
public struct KvHttpResponse : KvResponse {

    /// Type of raw URL query passed to the custom handlers.
    public typealias RawUrlQuery = [URLQueryItem]


    typealias Implementation = KvHttpResponseImplementationProtocol

    fileprivate typealias ImplementationBlock = (ImplementationConfiguration) -> Implementation



    @usableFromInline
    var configuration: Configuration = .empty



    fileprivate init(implementationBlock: @escaping ImplementationBlock) {
        self.implementationBlock = implementationBlock
    }



    private let implementationBlock: ImplementationBlock



    // MARK: Simple Response

    private init(callback: @escaping (KvHttpResponseProvider) -> Void) {
        self.init(implementationBlock: { implementationConfiguration in
            KvHttpResponseImplementation(
                clientCallbacks: implementationConfiguration.clientCallbacks,
                responseProvider: callback
            )
        })
    }


    /// Initializes simple HTTP response those content is provided by *content* callback.
    ///
    /// Content of simple HTTP responses doesn't depend on a request.
    ///
    /// Below is an example of a simple HTTP response with standard text representation of a generated UUID:
    ///
    /// ```swift
    /// KvHttpResponse { .string { UUID().uuidString } }
    /// ```
    ///
    /// There are overloads of this initializer with `async`, `throws` and `async throws` content blocks.
    ///
    /// - SeeAlso: ``with``.
    public init(content: @escaping () -> KvHttpResponseContent?) {
        self.init(callback: { $0.invoke(with: content) })
    }


    /// An overload of ``init(content:)`` with throwing callback argument.
    public init(content: @escaping () throws -> KvHttpResponseContent?) {
        self.init(callback: { $0.invoke(with: content) })
    }


    /// An overload of ``init(content:)`` with asynchronous callback argument.
    public init(content: @escaping () async -> KvHttpResponseContent?) {
        self.init(callback: { $0.invoke(with: content) })
    }


    /// An overload of ``init(content:)`` with asynchronous throwing callback argument.
    public init(content: @escaping () async throws -> KvHttpResponseContent?) {
        self.init(callback: { $0.invoke(with: content) })
    }



    // MARK: Parameterized Responses

    /// - Returns: A builder of parameterized HTTP response.
    ///
    /// Builders of parameterized HTTP responses are used to configure handling of URL query, request headers and body.
    /// When builder is configured, call `.content`() method to get instance of ``KvHttpResponse``.
    ///
    /// The callback provided to `.content`() method is passed with a request input, e.g. containing processed URL query, request headers, body.
    ///
    /// Below is an example of a parameterized HTTP response with generated UUID.
    /// Format of returned UUID depends on *string* flag in URL query.
    ///
    /// ```swift
    /// KvHttpResponse.with
    ///     .query(.bool("string"))
    ///     .content { input in
    ///         let uuid = UUID()
    ///
    ///         switch input.query {
    ///         case true:
    ///             return .string { uuid.uuidString }
    ///         case false:
    ///             return withUnsafeBytes(of: uuid, { buffer in
    ///                 return .binary { buffer }
    ///             })
    ///         }
    ///     }
    /// ```
    ///
    /// Below is an example of an echo response returning a request body:
    /// ```swift
    /// KvHttpResponse.with
    ///     .requestBody(.data)
    ///     .content { input in .binary { input.requestBody ?? Data() } }
    /// ```
    ///
    /// Initially response matches empty URL query and empty or missing HTTP request body.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// Below is an example of a random integer response. Note how `.queryFlatMap`() is used to validate and wrap the values into a standard *ClosedRange* structure.
    /// Also note that `.queryFlatMap`() produces single query value so it can be appended with up to 9 query items.
    /// ```swift
    /// KvHttpResponse.with
    ///     .query(.optional("from", of: Int.self))
    ///     .query(.optional("through", of: Int.self))
    ///     .queryFlatMap { from, through -> QueryResult<ClosedRange<Int>> in
    ///         let lowerBound = from ?? .min, upperBound = through ?? .max
    ///         return lowerBound <= upperBound ? .success(lowerBound ... upperBound) : .failure
    ///     }
    ///     .content { input in .string { "\(Int.random(in: input.query))" } }
    /// ```
    ///
    /// A response can be declared for a hierarchy of URL paths.
    /// Below is an example of a response group providing access to profiles at "profiles/%u" paths and top-rated profiles at "profiles/top" path.
    /// ```swift
    /// KvGroup("profiles") {
    ///     KvGroup("top") {
    ///         KvHttpResponse { .string { "Top profiles" } }
    ///     }
    ///     KvHttpResponse.with
    ///         .subpathFilter { $0.components.count == 1 }
    ///         .subpathFlatMap { .unwrapping(UInt($0.components.first!)) }
    ///         .content { input in .string { "Profile \(input.subpath)" } }
    /// }
    /// ```
    ///
    /// - SeeAlso: ``init(content:)-5zj38``.
    @inlinable
    public static var with: InitialParameterizedResponse { .init() }



    // MARK: : KvResponse

    public var body: KvNeverResponse { Body() }



    // MARK: .Incident

    /// *KvHttpResponse* specific incidents.
    public enum Incident : KvHttpIncident {

        /// There are two or more declared responses for an HTTP request. Default status: 400 (Bad Request).
        case ambiguousRequest
        /// Processing of HTTP request headers has failed with associated error. Default status: 400 (Bad Request).
        case invalidHeaders(Error)
        /// Request processing has failed with associated error. Default status: 500 (Internal Server Error).
        case processingFailed(Error)
        /// There are no declared responses for an HTTP request. Default status: 404 (Not Found).
        case responseNotFound


        // MARK: : KvHttpIncident

        @inlinable
        public var defaultStatus: KvHttpStatus {
            switch self {
            case .ambiguousRequest:
                return .badRequest
            case .invalidHeaders(_):
                return .badRequest
            case .processingFailed(_):
                return .internalServerError
            case .responseNotFound:
                return .notFound
            }
        }

    }



    // MARK: .Configuration

    @usableFromInline
    struct Configuration {

        @usableFromInline
        static let empty: Self = .init()


        @usableFromInline
        var clientCallbacks: KvClientCallbacks?

    }



    // MARK: Modifiers

    @inline(__always)
    @usableFromInline
    func modified(_ block: (inout Configuration) -> Void) -> KvHttpResponse {
        var copy = self
        block(&copy.configuration)
        return copy
    }



    /// Declares handler of incidents while processing requests to the response. It's a place to customize default response content.
    ///
    /// - Parameter block:  A block returning custom response content or `nil` for given *incident*.
    ///                     If `nil` is returned then ``KvHttpIncident/defaultStatus`` is submitted to client.
    ///
    /// Previously declared value is replaced.
    ///
    /// Below is an example where custom 413 (Content Too Large) response is provided when request body exceeds limit:
    ///
    /// ```swift
    /// KvHttpResponse.with
    ///    .requestBody(.data.bodyLengthLimit(1024))
    ///    .content { input in .binary { input.requestBody ?? .init() } }
    ///    .onIncident { incident in
    ///        guard incident.defaultStatus == .contentTooLarge else { return nil }
    ///        return .contentTooLarge.string("Content is too large. Limit is 1024 bytes.")
    ///    }
    /// ```
    ///
    /// Incident handlers can be provided for responses in groups with ``KvResponseGroup/onHttpIncident(_:)``.
    ///
    /// - SeeAlso: ``onError(_:)``.
    @inlinable
    public func onIncident(_ block: @escaping (KvHttpIncident, KvHttpRequestContext) throws -> KvHttpResponseContent?) -> KvHttpResponse {
        modified {
            $0.clientCallbacks = .accumulate(.init(onHttpIncident: { try? block($0, $1) }), into: $0.clientCallbacks)
        }
    }


    /// Declares callback for errors of processing requests to the response.
    ///
    /// Previously declared value is replaced.
    ///
    /// Error callbacks can be provided for responses in groups with ``KvResponseGroup/onError(_:)``.
    ///
    /// - SeeAlso: ``onIncident(_:)``.
    @inlinable
    public func onError(_ block: @escaping (Error, KvHttpRequestContext) -> Void) -> KvHttpResponse {
        modified {
            $0.clientCallbacks = .accumulate(.init(onError: block), into: $0.clientCallbacks)
        }
    }

}



// MARK: : KvResponseInternalProtocol

extension KvHttpResponse : KvResponseInternalProtocol {

    func insert<A : KvHttpResponseAccumulator>(to accumulator: A) {
        let configuration = ImplementationConfiguration(accumulator.responseGroupConfiguration, configuration)

        accumulator.insert(implementationBlock(configuration))
    }



    // MARK: .ImplementationConfiguration

    fileprivate struct ImplementationConfiguration {

        let httpRequestBody: KvResponseGroupConfiguration.HttpRequestBody?
        let clientCallbacks: KvClientCallbacks?


        init(_ responseGroupConfiguration: KvResponseGroupConfiguration?, _ responseConfiguration: Configuration?) {
            self.httpRequestBody = responseGroupConfiguration?.httpRequestBody
            self.clientCallbacks = .accumulate(responseConfiguration?.clientCallbacks, into: responseGroupConfiguration?.clientCallbacks)
        }

    }

}


// MARK: .ParameterizedResponse

extension KvHttpResponse {

    /// Type of parameterized HTTP response builder.
    ///
    /// See ``KvHttpResponse/with-swift.type.property`` for details.
    public struct ParameterizedResponse<QueryItemGroup, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>
    where QueryItemGroup : KvUrlQueryItemGroup,
          Subpath : KvUrlSubpathProtocol
    {

        /// Type representing processed content of the HTTP request. It's passed to the response's content callback.
        public typealias Input = KvHttpResponseInput<QueryItemGroup.Value, RequestHeaders, RequestBodyValue, SubpathValue>


        @usableFromInline
        var configuration: Configuration


        @usableFromInline
        init(with configuration: Configuration) {
            self.configuration = configuration
        }


        // MARK: .Configuration

        @usableFromInline
        struct Configuration {

            @usableFromInline
            typealias SubpathFilterCallback = (Subpath) -> KvFilterResult<SubpathValue>

            @usableFromInline
            typealias RequestHeadCallback = (KvHttpServer.RequestHeaders) -> Result<RequestHeaders, Error>


            @usableFromInline
            let subpathFilter: SubpathFilterCallback

            @usableFromInline
            let queryItemGroup: QueryItemGroup

            @usableFromInline
            let requestHeadCallback: RequestHeadCallback

            @usableFromInline
            let requestBody: any KvHttpRequestBodyInternal


            @usableFromInline
            init(subpathFilter: @escaping SubpathFilterCallback,
                 queryItemGroup: QueryItemGroup,
                 requestHeadCallback: @escaping RequestHeadCallback,
                 requestBody: any KvHttpRequestBodyInternal
            ) {
                self.subpathFilter = subpathFilter
                self.queryItemGroup = queryItemGroup
                self.requestHeadCallback = requestHeadCallback
                self.requestBody = requestBody
            }

        }


        // MARK: Completion

        /// A template method for the public overloads.
        private func content<QueryParser>(
            _ queryParser: QueryParser,
            _ callback: @escaping (Input, KvHttpResponseProvider) -> Void
        ) -> KvHttpResponse
        where QueryParser : KvUrlQueryParserProtocol & KvUrlQueryParseResultProvider, QueryParser.Value == QueryItemGroup.Value
        {
            return .init { implementationConfiguration in
                var body = configuration.requestBody

                if let baseBodyConfiguration = implementationConfiguration.httpRequestBody {
                    body = body.with(baseConfiguration: baseBodyConfiguration)
                }

                return KvHttpResponseImplementation(
                    subpathFilter: configuration.subpathFilter,
                    urlQueryParser: queryParser,
                    headCallback: configuration.requestHeadCallback,
                    body: body,
                    clientCallbacks: implementationConfiguration.clientCallbacks,
                    responseProvider: callback
                )
            }
        }

    }

}


// MARK: Completion for Empty Query

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup == KvEmptyUrlQueryItemGroup {

    private func content(_ callback: @escaping (Input, KvHttpResponseProvider) -> Void) -> KvHttpResponse {
        content(KvEmptyUrlQueryParser(), callback)
    }


    /// Call this method to finalize configuration of an HTTP response.
    ///
    /// - Parameter callback: Function to be called for each request with a request input.
    ///
    /// - Returns: Configured instance of ``KvHttpResponse``.
    ///
    /// There are overloads of this method with `async`, `throws` and `async throws` callback blocks.
    ///
    /// See ``KvHttpResponse`` for examples.
    public func content(_ callback: @escaping (Input) -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { callback(input) })
        }
    }


    /// An overload of ``content(_:)`` with throwing callback argument.
    public func content(_ callback: @escaping (Input) throws -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { try callback(input) })
        }
    }


    /// An overload of ``content(_:)`` with throwing callback argument.
    public func content(_ callback: @escaping (Input) async -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { await callback(input) })
        }
    }


    /// An overload of ``content(_:)`` with throwing callback argument.
    public func content(_ callback: @escaping (Input) async throws -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { try await callback(input) })
        }
    }

}


// MARK: Completion for Raw Queries

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvRawUrlQueryItemGroupProtocol {

    private func content(_ callback: @escaping (Input, KvHttpResponseProvider) -> Void) -> KvHttpResponse {
        content(KvRawUrlQueryParser(for: configuration.queryItemGroup), callback)
    }


    /// Call this method to finalize configuration of an HTTP response.
    ///
    /// - Parameter callback: Function to be called for each request with a request input.
    ///
    /// - Returns: Configured instance of ``KvHttpResponse``.
    ///
    /// There are overloads of this method with `async`, `throws` and `async throws` callback blocks.
    ///
    /// See ``KvHttpResponse`` for examples.
    public func content(_ callback: @escaping (Input) -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { callback(input) })
        }
    }


    /// An overload of ``content(_:)`` with throwing callback argument.
    public func content(_ callback: @escaping (Input) throws -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { try callback(input) })
        }
    }


    /// An overload of ``content(_:)`` with throwing callback argument.
    public func content(_ callback: @escaping (Input) async -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { await callback(input) })
        }
    }


    /// An overload of ``content(_:)`` with throwing callback argument.
    public func content(_ callback: @escaping (Input) async throws -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { try await callback(input) })
        }
    }

}


// MARK: Completion for Structured Queries

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvUrlQueryItemImplementationProvider {

    private func content(_ callback: @escaping (Input, KvHttpResponseProvider) -> Void) -> KvHttpResponse {
        content(KvUrlQueryParser(for: configuration.queryItemGroup), callback)
    }


    /// Call this method to finalize configuration of an HTTP response.
    ///
    /// - Parameter callback: Function to be called for each request with a request input.
    ///
    /// - Returns: Configured instance of ``KvHttpResponse``.
    ///
    /// There are overloads of this method with `async`, `throws` and `async throws` callback blocks.
    ///
    /// See ``KvHttpResponse`` for examples.
    public func content(_ callback: @escaping (Input) -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { callback(input) })
        }
    }


    /// An overload of ``content(_:)`` with throwing callback argument.
    public func content(_ callback: @escaping (Input) throws -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { try callback(input) })
        }
    }


    /// An overload of ``content(_:)`` with throwing callback argument.
    public func content(_ callback: @escaping (Input) async -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { await callback(input) })
        }
    }


    /// An overload of ``content(_:)`` with throwing callback argument.
    public func content(_ callback: @escaping (Input) async throws -> KvHttpResponseContent?) -> KvHttpResponse {
        content { input, completion in
            completion.invoke(with: { try await callback(input) })
        }
    }

}


// MARK: Initialization

public typealias InitialParameterizedResponse = KvHttpResponse.ParameterizedResponse<KvEmptyUrlQueryItemGroup, KvHttpRequestIgnoredHeaders, KvHttpRequestVoidBodyValue, KvUnavailableUrlSubpath, Void>


extension InitialParameterizedResponse {

    @usableFromInline
    init() {
        self.init(with: .init(subpathFilter: { _ in .accepted(()) },
                              queryItemGroup: .init(),
                              requestHeadCallback: { _ in .success(.init()) },
                              requestBody: KvHttpRequestProhibitedBody()))
    }

}


// MARK: Configuring Auxiliaries

extension KvHttpResponse.ParameterizedResponse {

    @usableFromInline
    @inline(__always)
    func map<Q, H, B, S, SFV>(_ transform: (Configuration) -> KvHttpResponse.ParameterizedResponse<Q, H, B, S, SFV>.Configuration) -> KvHttpResponse.ParameterizedResponse<Q, H, B, S, SFV>
    where Q : KvUrlQueryItemGroup
    {
        .init(with: transform(configuration))
    }


    @usableFromInline
    @inline(__always)
    func mapQuery<Q>(_ transform: (QueryItemGroup) -> Q) -> KvHttpResponse.ParameterizedResponse<Q, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>
    where Q : KvUrlQueryItemGroup
    {
        map { .init(subpathFilter: $0.subpathFilter,
                    queryItemGroup: transform($0.queryItemGroup),
                    requestHeadCallback: $0.requestHeadCallback,
                    requestBody: $0.requestBody)
        }
    }

}


// MARK: Empty Query

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup == KvEmptyUrlQueryItemGroup {

    public typealias MappingRaw<T> = KvHttpResponse.ParameterizedResponse<KvRawUrlQueryItemGroup<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/with-swift.type.property`` for examples.
    ///
    /// - Note: Initially response matches empty URL query.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> KvHttpResponse.ParameterizedResponse<KvUrlQueryItemGroupOfOne<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue> {
        mapQuery { _ in .init(item) }
    }


    /// Provides custom processing of URL query.
    ///
    /// Transformation result is available in the input passed to the response callback.
    ///
    /// Transformation block always return the result. So response will always match any URL query.
    /// Avoid use of such responses in overloading by URL query. To be able to reject URL queries use ``KvHttpResponse/ParameterizedResponse/queryFlatMap(_:)-190ql`` modifier.
    ///
    /// Custom processing of URL queries can't be combined with the structured processing.
    ///
    /// - Note: Initially response matches empty URL query.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (KvHttpResponse.RawUrlQuery?) -> T) -> MappingRaw<T> {
        mapQuery { _ in .init(transform) }
    }


    /// Provides custom processing of URL query.
    ///
    /// Transformation result is available in the input passed to the response callback.
    ///
    /// Transformation block returns instance of ``KvUrlQueryParseResult``. So an URL query can be rejected.
    /// If processing of URL query always succeeds then ``KvHttpResponse/ParameterizedResponse/queryMap(_:)-80vtg`` modifier should be used instead.
    ///
    /// Custom processing of URL queries can't be combined with the structured processing.
    ///
    /// - Note: Initially response matches empty URL query.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (KvHttpResponse.RawUrlQuery?) -> KvResponse.QueryResult<T>) -> MappingRaw<T> {
        mapQuery { _ in .init(transform) }
    }

}


// MARK: Query of Single Element

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvUrlQueryItemGroupOfOneProtocol {

    public typealias AmmendedUpToTwo<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingOne<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/with-swift.type.property`` for examples.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> AmmendedUpToTwo<T> {
        mapQuery { $0.ammended(item) }
    }


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.Value) -> T) -> MappingOne<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.Value) -> KvResponse.QueryResult<T>) -> MappingOne<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: Query of Two Elements

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvUrlQueryItemGroupOfTwoProtocol {

    public typealias AmmendedUpToThree<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingTwo<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/with-swift.type.property`` for examples.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> AmmendedUpToThree<T> {
        mapQuery { $0.ammended(item) }
    }


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value) -> T) -> MappingTwo<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value) -> KvResponse.QueryResult<T>) -> MappingTwo<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: Query of Three Elements

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvUrlQueryItemGroupOfThreeProtocol {

    public typealias AmmendedUpToFour<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingThree<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/with-swift.type.property`` for examples.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> AmmendedUpToFour<T> {
        mapQuery { $0.ammended(item) }
    }


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value) -> T) -> MappingThree<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value) -> KvResponse.QueryResult<T>) -> MappingThree<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: Query of Four Elements

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvUrlQueryItemGroupOfFourProtocol {

    public typealias AmmendedUpToFive<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingFour<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/with-swift.type.property`` for examples.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> AmmendedUpToFive<T> {
        mapQuery { $0.ammended(item) }
    }


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value) -> T) -> MappingFour<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value) -> KvResponse.QueryResult<T>) -> MappingFour<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: Query of Five Elements

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvUrlQueryItemGroupOfFiveProtocol {

    public typealias AmmendedUpToSix<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingFive<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/with-swift.type.property`` for examples.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> AmmendedUpToSix<T> {
        mapQuery { $0.ammended(item) }
    }


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value) -> T) -> MappingFive<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value) -> KvResponse.QueryResult<T>) -> MappingFive<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: Query of Six Elements

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvUrlQueryItemGroupOfSixProtocol {

    public typealias AmmendedUpToSeven<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingSix<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/with-swift.type.property`` for examples.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> AmmendedUpToSeven<T> {
        mapQuery { $0.ammended(item) }
    }


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value, QueryItemGroup.G5.Value) -> T) -> MappingSix<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value, QueryItemGroup.G5.Value) -> KvResponse.QueryResult<T>) -> MappingSix<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: Query of Seven Elements

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvUrlQueryItemGroupOfSevenProtocol {

    public typealias AmmendedUpToEight<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingSeven<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/with-swift.type.property`` for examples.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> AmmendedUpToEight<T> {
        mapQuery { $0.ammended(item) }
    }


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value, QueryItemGroup.G5.Value, QueryItemGroup.G6.Value) -> T) -> MappingSeven<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value, QueryItemGroup.G5.Value, QueryItemGroup.G6.Value) -> KvResponse.QueryResult<T>) -> MappingSeven<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: Query of Eight Elements

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvUrlQueryItemGroupOfEightProtocol {

    public typealias AmmendedUpToNine<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingEight<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/with-swift.type.property`` for examples.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> AmmendedUpToNine<T> {
        mapQuery { $0.ammended(item) }
    }


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value, QueryItemGroup.G5.Value, QueryItemGroup.G6.Value, QueryItemGroup.G7.Value) -> T) -> MappingEight<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value, QueryItemGroup.G5.Value, QueryItemGroup.G6.Value, QueryItemGroup.G7.Value) -> KvResponse.QueryResult<T>) -> MappingEight<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: Query of Nine Elements

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvUrlQueryItemGroupOfNineProtocol {

    public typealias AmmendedUpToTen<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingNine<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/with-swift.type.property`` for examples.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> AmmendedUpToTen<T> {
        mapQuery { $0.ammended(item) }
    }


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value, QueryItemGroup.G5.Value, QueryItemGroup.G6.Value, QueryItemGroup.G7.Value, QueryItemGroup.G8.Value) -> T) -> MappingNine<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value, QueryItemGroup.G5.Value, QueryItemGroup.G6.Value, QueryItemGroup.G7.Value, QueryItemGroup.G8.Value) -> KvResponse.QueryResult<T>) -> MappingNine<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: Query of Ten Elements

extension KvHttpResponse.ParameterizedResponse where QueryItemGroup : KvUrlQueryItemGroupOfTenProtocol {

    public typealias MappingTen<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value, QueryItemGroup.G5.Value, QueryItemGroup.G6.Value, QueryItemGroup.G7.Value, QueryItemGroup.G8.Value, QueryItemGroup.G9.Value) -> T) -> MappingTen<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifiers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value, QueryItemGroup.G3.Value, QueryItemGroup.G4.Value, QueryItemGroup.G5.Value, QueryItemGroup.G6.Value, QueryItemGroup.G7.Value, QueryItemGroup.G8.Value, QueryItemGroup.G9.Value) -> KvResponse.QueryResult<T>) -> MappingTen<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: First Request Header Modifier

extension KvHttpResponse.ParameterizedResponse where RequestHeaders == KvHttpRequestIgnoredHeaders {

    /// Adds raw HTTP headers into the input passed to the response callback.
    ///
    /// See ``requestHeadersMap(_:)-4ceet`` and ``requestHeadersFlatMap(_:)-3mu63`` to perform custom processing of or filtering by raw HTTP headers.
    /// Consider these methods to reduce performance costs and memory usage.
    @inlinable
    public var requestHeaders: HandlingRequestHeaders<KvHttpServer.RequestHeaders> {
        requestHeadersFlatMap { .success($0) }
    }


    /// Adds transformation of HTTP request headers.
    ///
    /// The result of transformation is available in the input passed to the callback. Use this method to collect some data from HTTP request headers and then use it in the callback.
    ///
    /// See ``requestHeadersFlatMap(_:)-3mu63`` to reject HTTP requests by their headers.
    ///
    /// - SeeAlso: ``requestHeaders``.
    @inlinable
    public func requestHeadersMap<H>(_ transform: @escaping (KvHttpServer.RequestHeaders) -> H) -> HandlingRequestHeaders<H> {
        requestHeadersFlatMap { .success(transform($0)) }
    }


    /// Adds transformation and validation of HTTP request headers.
    ///
    /// The result of succeeded transformation is available in the input passed to the callback. Use this method to collect some data from HTTP request headers and then use it in the callback.
    ///
    /// See ``requestHeadersMap(_:)-4ceet`` if there is no need to validate headers of HTTP requests.
    ///
    /// - SeeAlso: ``requestHeaders``.
    @inlinable
    public func requestHeadersFlatMap<H>(_ transform: @escaping (KvHttpServer.RequestHeaders) -> Result<H, Error>) -> HandlingRequestHeaders<H> {
        map { .init(
            subpathFilter: $0.subpathFilter,
            queryItemGroup: $0.queryItemGroup,
            requestHeadCallback: transform,
            requestBody: $0.requestBody
        ) }
    }

}


// MARK: Nested Request Header Modifier

extension KvHttpResponse.ParameterizedResponse {

    public typealias HandlingRequestHeaders<H> = KvHttpResponse.ParameterizedResponse<QueryItemGroup, H, RequestBodyValue, Subpath, SubpathValue>


    /// Adds additional transformation of HTTP request headers.
    @inlinable
    public func requestHeadersMap<H>(_ transform: @escaping (RequestHeaders) -> H) -> HandlingRequestHeaders<H> {
        map { configuration in .init(
            subpathFilter: configuration.subpathFilter,
            queryItemGroup: configuration.queryItemGroup,
            requestHeadCallback: { headers in configuration.requestHeadCallback(headers).map(transform) },
            requestBody: configuration.requestBody
        ) }
    }


    /// Adds additional transformation and validation of HTTP request headers.
    @inlinable
    public func requestHeadersFlatMap<H>(_ transform: @escaping (RequestHeaders) -> Result<H, Error>) -> HandlingRequestHeaders<H> {
        map { configuration in .init(
            subpathFilter: configuration.subpathFilter,
            queryItemGroup: configuration.queryItemGroup,
            requestHeadCallback: { headers in configuration.requestHeadCallback(headers).flatMap(transform) },
            requestBody: configuration.requestBody
        ) }
    }

}


// MARK: Request Body Modifiers

extension KvHttpResponse.ParameterizedResponse where RequestBodyValue == KvHttpRequestVoidBodyValue {

    public typealias HandlingRequestBody<B> = KvHttpResponse.ParameterizedResponse<QueryItemGroup, RequestHeaders, B, Subpath, SubpathValue>


    /// Adds processing of HTTP request body.
    ///
    /// - Parameter requestBody: Declaration of HTTP request body processing as instance of ``KvHttpRequestDataBody``.
    ///
    /// The result of HTTP request body processing is available in the input passed to the callback.
    ///
    /// Initially response matches empty or missing HTTP request body. Requests having non-empty bodies are rejected.
    @inlinable
    public func requestBody(_ requestBody: KvHttpRequestDataBody) -> HandlingRequestBody<KvHttpRequestDataBody.Value> {
        map { .init(
            subpathFilter: $0.subpathFilter,
            queryItemGroup: $0.queryItemGroup,
            requestHeadCallback: $0.requestHeadCallback,
            requestBody: requestBody
        ) }
    }


    /// Adds processing of HTTP request body.
    ///
    /// - Parameter requestBody: Declaration of HTTP request body processing. See ``KvHttpRequestJsonBody`` for available body processing options.
    ///
    /// The result of HTTP request body processing is available in the input passed to the callback.
    ///
    /// Initially response matches empty or missing HTTP request body. Requests having non-empty bodies are rejected.
    @inlinable
    public func requestBody<B>(_ requestBody: KvHttpRequestJsonBody<B>) -> HandlingRequestBody<B>
    where B : Decodable {
        map { .init(
            subpathFilter: $0.subpathFilter,
            queryItemGroup: $0.queryItemGroup,
            requestHeadCallback: $0.requestHeadCallback,
            requestBody: requestBody
        ) }
    }


    /// Adds processing of HTTP request body.
    ///
    /// - Parameter requestBody: Declaration of HTTP request body processing. See ``KvHttpRequestReducingBody`` for available body processing options.
    ///
    /// The result of HTTP request body processing is available in the input passed to the callback.
    ///
    /// Initially response matches empty or missing HTTP request body. Requests having non-empty bodies are rejected.
    @inlinable
    public func requestBody<B>(_ requestBody: KvHttpRequestReducingBody<B>) -> HandlingRequestBody<B> {
        map { .init(
            subpathFilter: $0.subpathFilter,
            queryItemGroup: $0.queryItemGroup,
            requestHeadCallback: $0.requestHeadCallback,
            requestBody: requestBody
        ) }
    }

}


// MARK: Subpath Modifiers

extension KvHttpResponse.ParameterizedResponse where Subpath == KvUnavailableUrlSubpath {

    public typealias HandlingSubpath<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup, RequestHeaders, RequestBodyValue, KvUrlSubpath, T>


    /// Enables processing of URL subpaths.
    ///
    /// For example if response is declared at "/a/b" path then it's returned for "/a/b" path and any subpath.
    /// The subpath is provided as instance of ``KvUrlSubpath`` at ``KvHttpResponse/ParameterizedResponse/Input``.``KvHttpResponseInput/subpath``.
    ///
    /// Below is a simple example returning the subpath:
    /// ```swift
    /// struct Server : KvServer {
    ///     var body: some KvResponseRootGroup {
    ///         KvGroup("a/b") {
    ///             KvHttpResponse.with
    ///                 .subpath
    ///                 .content { input in
    ///                     .string { input.subpath.joined }
    ///                 }
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// Use ``subpathFlatMap(_:)-6xc4y`` or ``subpathFilter(_:)-3tjji`` modifiers to provide additional filtering by subpath.
    @inlinable
    public var subpath: HandlingSubpath<KvUrlSubpath> {
        subpathFlatMap { .accepted($0) }
    }


    /// Analog of ``subpathFlatMap(_:)-6xc4y`` modifier returning a boolean value.
    ///
    /// - SeeAlso: ``subpath``, ``subpathFlatMap(_:)-6xc4y``.
    @inlinable
    public func subpathFilter(_ predicate: @escaping (KvUrlSubpath) -> Bool) -> HandlingSubpath<KvUrlSubpath> {
        subpathFlatMap { predicate($0) ? .accepted($0) : .rejected }
    }


    /// Enables processing of URL subpaths with additional filter callback. See ``subpath`` modifier for details on subpath processing.
    ///
    /// Responses at rejected subpaths are ignored. So it's the way avoid ambiguity when there are regular and subpath responses.
    /// Also this method provides the way to avoid double execution of some code in both filter callback and `.content` callback.
    ///
    /// Below is an example of a response group providing access to profiles at "profiles/$id" paths and top-rated profiles at "profiles/top".
    /// ```swift
    /// KvGroup("profiles") {
    ///     KvGroup("top") {
    ///         KvHttpResponse { .string { "Top profiles" } }
    ///     }
    ///     KvHttpResponse.with
    ///         .subpathFilter { $0.components.count == 1 }
    ///         .subpathFlatMap { .unwrapping(Int($0.components.first!)) }
    ///         .content { input in
    ///             .string { "Profile \(input.subpath)" }
    ///         }
    /// }
    /// ```
    ///
    /// - SeeAlso: ``subpath``, ``subpathFilter(_:)-3tjji``.
    @inlinable
    public func subpathFlatMap<SubpathMapValue>(_ predicate: @escaping (KvUrlSubpath) -> KvFilterResult<SubpathMapValue>) -> HandlingSubpath<SubpathMapValue> {
        map { .init(
            subpathFilter: predicate,
            queryItemGroup: $0.queryItemGroup,
            requestHeadCallback: $0.requestHeadCallback,
            requestBody: $0.requestBody
        ) }
    }

}


extension KvHttpResponse.ParameterizedResponse where Subpath == KvUrlSubpath {

    public typealias MappedSubpath<T> = KvHttpResponse.ParameterizedResponse<QueryItemGroup, RequestHeaders, RequestBodyValue, KvUrlSubpath, T>


    /// Adds additional subpath filter. See ``subpathFilter(_:)-9ey8x`` for details.
    @inlinable
    public func subpathFilter(_ predicate: @escaping (SubpathValue) -> Bool) -> Self {
        subpathFlatMap { predicate($0) ? .accepted($0) : .rejected }
    }


    /// Adds additional subpath filter. See ``subpathFlatMap(_:)-7xend`` for details.
    @inlinable
    public func subpathFlatMap<SubpathMapValue>(_ predicate: @escaping (SubpathValue) -> KvFilterResult<SubpathMapValue>) -> MappedSubpath<SubpathMapValue> {
        map { configuration in .init(
            subpathFilter: {
                subpath in configuration.subpathFilter(subpath).flatMap(predicate)
            },
            queryItemGroup: configuration.queryItemGroup,
            requestHeadCallback: configuration.requestHeadCallback,
            requestBody: configuration.requestBody
        ) }
    }

}
