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

import NIOHTTP1



// MARK: - KvHttpResponse

/// A type representing HTTP responses.
///
/// There are two types of HTTP responses: static and dynamic.
/// Static HTTP responses doesn't depend on request.
/// Dynamic HTTP responses may depend on URL query, request headers and body.
///
/// Below are simple examples of a static and dynamic responses:
///
/// ```swift
/// KvHttpResponse.static { .string { ISO8601DateFormatter().string(from: Date()) } }
///
/// KvHttpResponse.dynamic
///     .requestBody(.json(of: DateComponents.self))
///     .content {
///         guard let date = $0.requestBody.date else { return .badRequest }
///         return .string { ISO8601DateFormatter().string(from: date) }
///     }
/// ```
///
/// Dynamic responses provide custom and structured handling of URL queries.
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
/// KvHttpResponse.dynamic
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
/// KvHttpResponse.dynamic
///     .query(.required("to", of: Float.self))
///     .content { input in
///         .string { "..< \(input.query)" }
///     }
/// KvHttpResponse.dynamic
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
    typealias ClientCallbacks = KvResponseGroupConfiguration.ClientCallbacks



    @usableFromInline
    var configuration: Configuration = .empty



    fileprivate init(implementationBlock: @escaping ImplementationBlock) {
        self.implementationBlock = implementationBlock
    }



    private let implementationBlock: ImplementationBlock



    // MARK: Fabrics

    /// - Returns: A static HTTP response those content is provided by *content* callback.
    ///
    /// Content of static HTTP responses don't depend on a request content.
    ///
    /// Below is an example of a static HTTP response with standard text representation of a generated UUID:
    ///
    /// ```swift
    /// KvHttpResponse.static { .string { UUID().uuidString } }
    /// ```
    public static func `static`(content: @escaping () throws -> KvHttpResponseProvider) -> KvHttpResponse {
        .init { implementationConfiguration in
            KvHttpResponseImplementation(clientCallbacks: implementationConfiguration.clientCallbacks,
                                         responseProvider: content)
        }
    }


    /// - Returns: A builder of dynamic HTTP response.
    ///
    /// Builders of dynamic HTTP responses are used to configure handling of URL query, request headers and body.
    /// When builder is configured, call `.content`() method to get instance of ``KvHttpResponse``.
    ///
    /// The callback provided to `.content`() method is passed with a request input, e.g. containing processed URL query, request headers, body.
    ///
    /// Below is an example of a dynamic HTTP response with generated UUID. Format of returned UUID depends on *string* flag in URL query.
    /// ```swift
    /// KvHttpResponse.dynamic
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
    /// KvHttpResponse.dynamic
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
    /// KvHttpResponse.dynamic
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
    ///         KvHttpResponse.static { .string { "Top profiles" } }
    ///     }
    ///     KvHttpResponse.dynamic
    ///         .subpathFilter { $0.components.count == 1 }
    ///         .subpathFlatMap { UInt($0.components.first!).map { .accepted($0) } ?? .rejected }
    ///         .content { input in .string { "Profile \(input.subpath)" } }
    /// }
    /// ```
    @inlinable
    public static var `dynamic`: InitialDynamicResponse { .init() }



    // MARK: : KvResponse

    public typealias Body = KvNeverResponse



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
        var clientCallbacks: ClientCallbacks?

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
    /// Below is an example where custom 413 (Payload Too Large) response is provided when request body exceeds limit:
    ///
    /// ```swift
    /// KvHttpResponse.dynamic
    ///    .requestBody(.data.bodyLengthLimit(1024))
    ///    .content { input in .binary { input.requestBody ?? .init() } }
    ///    .onIncident { incident in
    ///        guard incident.defaultStatus == .payloadTooLarge else { return nil }
    ///        return .payloadTooLarge.string("Payload is too large. Limit is 1024 bytes.")
    ///    }
    /// ```
    ///
    /// Incident handlers can be provided for responses in groups with ``KvResponseGroup/onHttpIncident(_:)``.
    ///
    /// See: ``onError(_:)``.
    @inlinable
    public func onIncident(_ block: @escaping (KvHttpIncident) throws -> KvHttpResponseProvider?) -> KvHttpResponse {
        modified {
            $0.clientCallbacks = .accumulate(.init(onHttpIncident: { try? block($0) }), into: $0.clientCallbacks)
        }
    }


    /// Declares callback for errors of processing requests to the response.
    ///
    /// Previously declared value is replaced.
    ///
    /// Error callbacks can be provided for responses in groups with ``KvResponseGroup/onError(_:)``.
    ///
    /// See: ``onIncident(_:)``.
    @inlinable
    public func onError(_ block: @escaping (Error) -> Void) -> KvHttpResponse {
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
        let clientCallbacks: ClientCallbacks?


        init(_ responseGroupConfiguration: KvResponseGroupConfiguration?, _ responseConfiguration: Configuration?) {
            self.httpRequestBody = responseGroupConfiguration?.httpRequestBody
            self.clientCallbacks = .accumulate(responseConfiguration?.clientCallbacks, into: responseGroupConfiguration?.clientCallbacks)
        }

    }

}


// MARK: .DynamicResponse

extension KvHttpResponse {

    /// Type of dynamic HTTP response builder.
    ///
    /// See ``KvHttpResponse/dynamic`` for details.
    public struct DynamicResponse<QueryItemGroup, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>
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

        /// Shorthand auxiliary method.
        private func makeImplementation<QueryParser>(
            _ queryParser: QueryParser,
            _ implementationConfiguration: ImplementationConfiguration,
            _ callback: @escaping (Input) throws -> KvHttpResponseProvider
        ) -> KvHttpResponseImplementation<QueryParser, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>
        where QueryParser : KvUrlQueryParserProtocol, QueryParser.Value == QueryItemGroup.Value
        {
            var body = configuration.requestBody

            if let baseBodyConfiguration = implementationConfiguration.httpRequestBody {
                body = body.with(baseConfiguration: baseBodyConfiguration)
            }

            return KvHttpResponseImplementation(subpathFilter: configuration.subpathFilter,
                                                urlQueryParser: queryParser,
                                                headCallback: configuration.requestHeadCallback,
                                                body: body,
                                                clientCallbacks: implementationConfiguration.clientCallbacks,
                                                responseProvider: callback)
        }

    }

}


// MARK: Completion for Empty Query

extension KvHttpResponse.DynamicResponse where QueryItemGroup == KvEmptyUrlQueryItemGroup {

    /// - Parameter callback: Function to be called for each request with a request input.
    ///
    /// - Returns: Configured instance of ``KvHttpResponse``.
    public func content(_ callback: @escaping (Input) throws -> KvHttpResponseProvider) -> KvHttpResponse {
        return .init { implementationConfiguration in
            makeImplementation(KvEmptyUrlQueryParser(), implementationConfiguration, callback)
        }
    }

}


// MARK: Completion for Raw Queries

extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvRawUrlQueryItemGroupProtocol {

    /// - Parameter callback: Function to be called for each request with a request input.
    ///
    /// - Returns: Configured instance of ``KvHttpResponse``.
    public func content(_ callback: @escaping (Input) throws -> KvHttpResponseProvider) -> KvHttpResponse {
        return .init { implementationConfiguration in
            makeImplementation(KvRawUrlQueryParser(for: configuration.queryItemGroup), implementationConfiguration, callback)
        }
    }

}


// MARK: Completion for Structured Queries

extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvUrlQueryItemImplementationProvider {

    /// - Parameter callback: Function to be called for each request with a request input.
    ///
    /// - Returns: Configured instance of ``KvHttpResponse``.
    public func content(_ callback: @escaping (Input) throws -> KvHttpResponseProvider) -> KvHttpResponse {
        return .init { implementationConfiguration in
            makeImplementation(KvUrlQueryParser(for: configuration.queryItemGroup), implementationConfiguration, callback)
        }
    }

}


// MARK: Initialization

public typealias InitialDynamicResponse = KvHttpResponse.DynamicResponse<KvEmptyUrlQueryItemGroup, KvHttpRequestIgnoredHeaders, KvHttpRequestVoidBodyValue, KvUnavailableUrlSubpath, Void>


extension InitialDynamicResponse {

    @usableFromInline
    init() {
        self.init(with: .init(subpathFilter: { _ in .accepted(()) },
                              queryItemGroup: .init(),
                              requestHeadCallback: { _ in .success(.init()) },
                              requestBody: KvHttpRequestProhibitedBody()))
    }

}


// MARK: Configuring Auxiliaries

extension KvHttpResponse.DynamicResponse {

    @usableFromInline
    @inline(__always)
    func map<Q, H, B, S, SFV>(_ transform: (Configuration) -> KvHttpResponse.DynamicResponse<Q, H, B, S, SFV>.Configuration) -> KvHttpResponse.DynamicResponse<Q, H, B, S, SFV>
    where Q : KvUrlQueryItemGroup
    {
        .init(with: transform(configuration))
    }


    @usableFromInline
    @inline(__always)
    func mapQuery<Q>(_ transform: (QueryItemGroup) -> Q) -> KvHttpResponse.DynamicResponse<Q, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>
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

extension KvHttpResponse.DynamicResponse where QueryItemGroup == KvEmptyUrlQueryItemGroup {

    public typealias MappingRaw<T> = KvHttpResponse.DynamicResponse<KvRawUrlQueryItemGroup<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/dynamic`` for examples.
    ///
    /// - Note: Initially response matches empty URL query.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> KvHttpResponse.DynamicResponse<KvUrlQueryItemGroupOfOne<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue> {
        mapQuery { _ in .init(item) }
    }


    /// Provides custom processing of URL query.
    ///
    /// Transformation result is available in the input passed to the response callback.
    ///
    /// Transformation block always return the result. So response will always match any URL query.
    /// Avoid use of such responses in overloading by URL query. To be able to reject URL queries use ``KvHttpResponse/DynamicResponse/queryFlatMap(_:)-41y06`` modifier.
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
    /// If processing of URL query always succeeds then ``KvHttpResponse/DynamicResponse/queryMap(_:)-5hsld`` modifier should be used instead.
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

extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvUrlQueryItemGroupOfOneProtocol {

    public typealias AmmendedUpToTwo<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingOne<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/dynamic`` for examples.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> AmmendedUpToTwo<T> {
        mapQuery { $0.ammended(item) }
    }


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.Value) -> T) -> MappingOne<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.Value) -> KvResponse.QueryResult<T>) -> MappingOne<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: Query of Two Elements

// TODO: Apply parameter packs from Swift 5.9.
extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvUrlQueryItemGroupOfTwoProtocol {

    public typealias AmmendedUpToThree<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingTwo<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/dynamic`` for examples.
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

extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvUrlQueryItemGroupOfThreeProtocol {

    public typealias AmmendedUpToFour<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingThree<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/dynamic`` for examples.
    @inlinable
    public func query<T>(_ item: KvUrlQueryItem<T>) -> AmmendedUpToFour<T> {
        mapQuery { $0.ammended(item) }
    }


    /// Replaces query value in the input with the result of transformation.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value) -> T) -> MappingThree<T> {
        mapQuery { $0.map(transform) }
    }


    /// Replaces query value in the input with the result of transformation or rejects URL query.
    ///
    /// It's convenient to wrap tuples of query items into dedicated structures.
    /// Also tuples of query values in the input become single values and can be appended with `.query`() modifers. So 10 element query tuple limit can be bypassed.
    @inlinable
    public func queryFlatMap<T>(_ transform: @escaping (QueryItemGroup.G0.Value, QueryItemGroup.G1.Value, QueryItemGroup.G2.Value) -> KvResponse.QueryResult<T>) -> MappingThree<T> {
        mapQuery { $0.flatMap(transform) }
    }

}


// MARK: Query of Four Elements

extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvUrlQueryItemGroupOfFourProtocol {

    public typealias AmmendedUpToFive<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingFour<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/dynamic`` for examples.
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

extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvUrlQueryItemGroupOfFiveProtocol {

    public typealias AmmendedUpToSix<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingFive<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/dynamic`` for examples.
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

extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvUrlQueryItemGroupOfSixProtocol {

    public typealias AmmendedUpToSeven<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingSix<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/dynamic`` for examples.
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

extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvUrlQueryItemGroupOfSevenProtocol {

    public typealias AmmendedUpToEight<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingSeven<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/dynamic`` for examples.
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

extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvUrlQueryItemGroupOfEightProtocol {

    public typealias AmmendedUpToNine<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingEight<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/dynamic`` for examples.
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

extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvUrlQueryItemGroupOfNineProtocol {

    public typealias AmmendedUpToTen<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Ammended<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>

    public typealias MappingNine<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


    /// Appends a structured URL query item to the receiver's input.
    ///
    /// This URL query item will be correctly parsed and processed depending on it's configuration. All structured query items are passed to the response's callback.
    ///
    /// Consider `.queryMap`() and `.queryFlatMap`() modifiers to provide convenient processing of query items and to bypass the 10 element limit in the query tuple in the input.
    /// See ``KvHttpResponse/dynamic`` for examples.
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

extension KvHttpResponse.DynamicResponse where QueryItemGroup : KvUrlQueryItemGroupOfTenProtocol {

    public typealias MappingTen<T> = KvHttpResponse.DynamicResponse<QueryItemGroup.Mapped<T>, RequestHeaders, RequestBodyValue, Subpath, SubpathValue>


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

extension KvHttpResponse.DynamicResponse where RequestHeaders == KvHttpRequestIgnoredHeaders {

    /// Adds transformation of HTTP request headers.
    ///
    /// The result of transformation is available in the input passed to the callback. Use this method to collect some data from HTTP request headers and then use it in the callback.
    ///
    /// See ``requestHeadersFlatMap(_:)-77jot`` to reject HTTP requests by their headers.
    @inlinable
    public func requestHeadersMap<H>(_ transform: @escaping (KvHttpServer.RequestHeaders) -> H) -> HandlingRequestHeaders<H> {
        requestHeadersFlatMap { .success(transform($0)) }
    }


    /// Adds transformation and validation of HTTP request headers.
    ///
    /// The result of succeeded transformation is available in the input passed to the callback. Use this method to collect some data from HTTP request headers and then use it in the callback.
    ///
    /// See ``requestHeadersMap(_:)-6fhnp`` if there is no need to validate headers of HTTP requests.
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

extension KvHttpResponse.DynamicResponse {

    public typealias HandlingRequestHeaders<H> = KvHttpResponse.DynamicResponse<QueryItemGroup, H, RequestBodyValue, Subpath, SubpathValue>


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

extension KvHttpResponse.DynamicResponse where RequestBodyValue == KvHttpRequestVoidBodyValue {

    public typealias HandlingRequestBody<B> = KvHttpResponse.DynamicResponse<QueryItemGroup, RequestHeaders, B, Subpath, SubpathValue>


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

extension KvHttpResponse.DynamicResponse where Subpath == KvUnavailableUrlSubpath {

    public typealias HandlingSubpath<T> = KvHttpResponse.DynamicResponse<QueryItemGroup, RequestHeaders, RequestBodyValue, KvUrlSubpath, T>


    /// Enables processing of URL subpaths.
    ///
    /// For example if response is declared at "/a/b" path then it's returned for "/a/b" path and any subpath.
    /// The subpath is provided as instance of ``KvUrlSubpath`` at ``KvHttpResponse/DynamicResponse/Input``.``KvHttpResponseInput/subpath``.
    ///
    /// Below is a simple example returning the subpath:
    /// ```swift
    /// struct Server : KvServer {
    ///     var body: some KvResponseGroup {
    ///     KvGroup("a/b") {
    ///         KvHttpResponse.dynamic
    ///             .subpath
    ///             .content { input in .string { input.subpath.joined } }
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// Use ``subpathFlatMap(_:)-dytv`` or ``subpathFilter(_:)-1y5iv`` modifiers to provide additional filtering by subpath.
    @inlinable
    public var subpath: HandlingSubpath<KvUrlSubpath> {
        subpathFlatMap { .accepted($0) }
    }


    /// Analog of ``subpathFlatMap(_:)-dytv`` modifier returning a boolean value.
    ///
    /// See: ``subpath``, ``subpathFlatMap(_:)-dytv``.
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
    ///         KvHttpResponse.static { .string { "Top profiles" } }
    ///     }
    ///     KvHttpResponse.dynamic
    ///         .subpathFilter { $0.components.count == 1 }
    ///         .subpathFlatMap { Int($0.components.first!).map { .accepted($0) } ?? .rejected }
    ///         .content { input in .string { "Profile \(input.subpath)" } }
    /// }
    /// ```
    ///
    /// See: ``subpath``, ``subpathFilter(_:)-1y5iv``.
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


extension KvHttpResponse.DynamicResponse where Subpath == KvUrlSubpath {

    public typealias MappedSubpath<T> = KvHttpResponse.DynamicResponse<QueryItemGroup, RequestHeaders, RequestBodyValue, KvUrlSubpath, T>


    /// Adds additional subpath filter. See ``subpathFilter(_:)-1y5iv`` for details.
    @inlinable
    public func subpathFilter(_ predicate: @escaping (SubpathValue) -> Bool) -> Self {
        subpathFlatMap { predicate($0) ? .accepted($0) : .rejected }
    }


    /// Adds additional subpath filter. See ``subpathFlatMap(_:)-dytv`` for details.
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
