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
//  KvHttpRequestBody.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 19.06.2023.
//

import Foundation



// MARK: - KvHttpRequestBody

public protocol KvHttpRequestBody {

    associatedtype Value

}



// MARK: - KvHttpRequestBodyInternal

@usableFromInline
protocol KvHttpRequestBodyInternal : KvHttpRequestBody {

    typealias Configuration = KvHttpRequestBodyConfiguration

    typealias ClientCallbacks = KvResponseGroupConfiguration.ClientCallbacks
    typealias ResponseBlock = (Value) throws -> KvHttpResponseProvider


    func with(baseConfiguration: Configuration) -> Self

    func makeRequestHandler(_ clientCallbacks: ClientCallbacks?, responseBlock: @escaping ResponseBlock) -> KvHttpRequestHandler

}



// MARK: - KvHttpRequestBodyConfiguration

@usableFromInline
struct KvHttpRequestBodyConfiguration : KvDefaultOverlayCascadable, KvDefaultAccumulationCascadable {

    @usableFromInline
    static let empty: Self = .init()
    

    @usableFromInline
    var bodyLengthLimit: UInt {
        get { _bodyLengthLimit ?? KvHttpRequest.Constants.bodyLengthLimit }
        set { _bodyLengthLimit = newValue }
    }
    @usableFromInline
    var _bodyLengthLimit: UInt?


    @usableFromInline
    init(bodyLengthLimit: UInt? = nil) {
        self._bodyLengthLimit = bodyLengthLimit
    }


    // MARK: : KvCascadable

    @usableFromInline
    static func accumulate(_ addition: Self, into base: Self) -> Self {
        .init(bodyLengthLimit: addition._bodyLengthLimit ?? base._bodyLengthLimit)
    }

}



// MARK: - KvHttpRequestVoidBodyValue

public struct KvHttpRequestVoidBodyValue {

    internal init() { }

}



// MARK: - KvHttpRequestProhibitedBody

/// This type declares absence (or zero length) of body in HTTP request.
public struct KvHttpRequestProhibitedBody : KvHttpRequestBodyInternal {

    public typealias Value = KvHttpRequestVoidBodyValue


    @usableFromInline
    var configuration: Configuration { .init(bodyLengthLimit: 0) }


    @usableFromInline
    init() { }


    // MARK: : KvHttpRequestBodyInternal

    @usableFromInline
    func with(baseConfiguration: Configuration) -> Self { self }

    @usableFromInline
    func makeRequestHandler(_ clientCallbacks: ClientCallbacks?, responseBlock: @escaping ResponseBlock) -> KvHttpRequestHandler {
        RequestHandler(clientCallbacks) {
            try responseBlock(.init())
        }
    }


    // MARK: .RequestHandler

    private class RequestHandler : KvHttpHeadOnlyRequestHandler {

        init(_ clientCallbacks: ClientCallbacks?, responseBlock: @escaping KvHttpHeadOnlyRequestHandler.ResponseBlock) {
            self.clientCallbacks = clientCallbacks

            super.init(responseBlock: responseBlock)
        }


        private let clientCallbacks: ClientCallbacks?


        // MARK: : KvHttpRequestHandler

        override func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.RequestIncident) -> KvHttpResponseProvider? {
            clientCallbacks?.onHttpIncident?(incident)
        }


        override func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
            clientCallbacks?.onError?(error)
        }

    }

}



// MARK: - KvHttpRequestRequiredBody

/// Protocol for declarations of HTTP request bodies.
///
/// Use fabrics and modifiers of conforming types: ``KvHttpRequestDataBody``, ``KvHttpRequestJsonBody``, ``KvHttpRequestReducingBody``.
public protocol KvHttpRequestRequiredBody : KvHttpRequestBody {

    // MARK: Modifiers

    /// This modifier declares limit for length of request body.
    ///
    /// Previously declared value is replaced.
    ///
    /// See: ``KvResponseGroup/httpBodyLengthLimit(_:)``.
    func bodyLengthLimit(_ value: UInt) -> Self

}



// MARK: - KvHttpRequestRequiredBodyInternal

@usableFromInline
protocol KvHttpRequestRequiredBodyInternal : KvHttpRequestBodyInternal, KvHttpRequestRequiredBody {

    var configuration: Configuration { get set }

}


extension KvHttpRequestRequiredBodyInternal {

    // MARK: : KvHttpRequestBodyInternal

    @usableFromInline
    func with(baseConfiguration: Configuration) -> Self {
        var copy = self
        copy.configuration = .overlay(copy.configuration, over: baseConfiguration)
        return copy
    }


    // MARK: Operations

    @usableFromInline
    @inline(__always)
    func modified(_ transform: (inout Configuration) -> Void) -> Self {
        var copy = self
        transform(&copy.configuration)
        return copy
    }


    // MARK: Modifiers

    /// This modifier declares limit in bytes for length of request body.
    ///
    /// Previously declared value is replaced.
    @inlinable
    public func bodyLengthLimit(_ value: UInt) -> Self {
        modified { $0.bodyLengthLimit = value }
    }

}



// MARK: - KvHttpRequestReducingBody

/// See ``reduce(_:_:)`` and ``reduce(into:_:)`` fabrics for details.
public struct KvHttpRequestReducingBody<PartialResult> : KvHttpRequestRequiredBodyInternal {

    public typealias Value = PartialResult


    @usableFromInline
    var configuration: Configuration = .init()

    let requestHandlerProvider: (Self, ClientCallbacks?, @escaping ResponseBlock) -> KvHttpRequestHandler


    @usableFromInline
    init(_ initialResult: PartialResult,
         _ nextPartialResult: @escaping (PartialResult, UnsafeRawBufferPointer) -> PartialResult)
    {
        requestHandlerProvider = { body, clientCallbacks, responseBlock in
            RequestHandler(
                body.configuration,
                initial: initialResult,
                nextPartialResult: nextPartialResult,
                clientCallbacks,
                responseBlock: responseBlock
            )
        }
    }


    @usableFromInline
    init(into initialResult: PartialResult,
         _ updateAccumulatingResult: @escaping (inout PartialResult, UnsafeRawBufferPointer) -> Void)
    {
        requestHandlerProvider = { body, clientCallbacks, responseBlock in
            RequestHandler(
                body.configuration,
                into: initialResult,
                updateAccumulatingResult: updateAccumulatingResult,
                clientCallbacks,
                responseBlock: responseBlock
            )
        }
    }


    // MARK: Fabrics

    /// - Returns: An HTTP request body handler processing request body fragments when they are received and collecting the result until the body is completely processed.
    ///
    /// This handler is designated to process request bodies on the fly minimizing memory usage and improving performance of large body processing.
    ///
    /// The resulting type of body processing result is type of *initialResult*.
    /// If the body is empty or missing then the result is equal to given *initialResult*.
    ///
    /// Consider ``reduce(into:_:)`` when it's beter to mutate partial result then return new partual result values.
    ///
    /// Below is an example of response returning plain text representation of cyclic sum of bytes in an HTTP request body.
    ///
    /// ```swift
    /// KvHttpResponse.dynamic
    ///     .requestBody(.reduce(0 as UInt8, { accumulator, buffer in
    ///         buffer.reduce(accumulator, &+)
    ///     }))
    ///     .content { input in
    ///         .string { "0x" + String(input.requestBody, radix: 16, uppercase: true) }
    ///     }
    /// ```
    @inlinable
    public static func reduce(
        _ initialResult: Value,
        _ nextPartialResult: @escaping (Value, UnsafeRawBufferPointer) -> Value
    ) -> KvHttpRequestReducingBody<Value>
    {
        KvHttpRequestReducingBody(initialResult, nextPartialResult)
    }


    /// - Returns: An HTTP request body handler processing request body fragments when they are received and collecting the result until the body is completely processed.
    ///
    /// The resulting type of body processing result is type of *initialResult*.
    /// If the body is empty or missing then the result is equal to given *initialResult*.
    ///
    /// This handler is designated to process request bodies on the fly minimizing memory usage and improving performance of large body processing.
    ///
    /// This method is similar to ``reduce(_:_:)`` excepth that collected partial result is collected in mutable first argument of *updateAccumulatingResult* block and the block returns *Void*.
    @inlinable
    public static func reduce(
        into initialResult: Value,
        _ updateAccumulatingResult: @escaping (inout Value, UnsafeRawBufferPointer) -> Void
    ) -> KvHttpRequestReducingBody<Value>
    {
        KvHttpRequestReducingBody(into: initialResult, updateAccumulatingResult)
    }


    // MARK: : KvHttpRequestBodyInternal

    @usableFromInline
    func makeRequestHandler(_ clientCallbacks: ClientCallbacks?, responseBlock: @escaping ResponseBlock) -> KvHttpRequestHandler {
        requestHandlerProvider(self, clientCallbacks, responseBlock)
    }


    // MARK: .RequestHandler

    private class RequestHandler : KvHttpReducingRequestHandler<PartialResult> {

        init(_ configuration: Configuration,
             initial initialResult: PartialResult,
             nextPartialResult: @escaping (PartialResult, UnsafeRawBufferPointer) throws -> PartialResult,
             _ clientCallbacks: ClientCallbacks?,
             responseBlock: @escaping KvHttpReducingRequestHandler<PartialResult>.ResponseBlock
        ) {
            self.clientCallbacks = clientCallbacks

            super.init(bodyLengthLimit: configuration.bodyLengthLimit,
                       initial: initialResult,
                       nextPartialResult: nextPartialResult,
                       responseBlock: responseBlock)
        }


        init(_ configuration: Configuration,
             into initialResult: PartialResult,
             updateAccumulatingResult: @escaping (inout PartialResult, UnsafeRawBufferPointer) throws -> Void,
             _ clientCallbacks: ClientCallbacks?,
             responseBlock: @escaping KvHttpReducingRequestHandler<PartialResult>.ResponseBlock
        ) {
            self.clientCallbacks = clientCallbacks

            super.init(bodyLengthLimit: configuration.bodyLengthLimit,
                       into: initialResult,
                       updateAccumulatingResult: updateAccumulatingResult,
                       responseBlock: responseBlock)
        }


        private let clientCallbacks: ClientCallbacks?


        // MARK: : KvHttpRequestHandler

        override func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.RequestIncident) -> KvHttpResponseProvider? {
            clientCallbacks?.onHttpIncident?(incident)
        }


        override func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
            clientCallbacks?.onError?(error)
        }

    }

}



// MARK: - KvHttpRequestDataBody

/// See ``data`` fabric for details.
public struct KvHttpRequestDataBody : KvHttpRequestRequiredBodyInternal {

    public typealias Value = Data?


    @usableFromInline
    var configuration: Configuration = .init()


    @usableFromInline
    init() { }


    // MARK: Fabrics

    /// - Returns: An HTTP request body handler collecting the received bytes into standard *Data*.
    ///
    /// The resulting type of body processing result is `Data?`.
    /// If the body is empty or missing then the result is `nil`.
    ///
    /// Below is an example of an echo response:
    ///
    /// ```swift
    /// KvHttpResponse.dynamic
    ///     .requestBody(.data)
    ///     .content { input in
    ///         guard let data: Data = input.requestBody else { return .badRequest }
    ///         return .binary({ data }).contentLength(data.count)
    ///     }
    /// ```
    @inlinable
    public static var data: KvHttpRequestDataBody { KvHttpRequestDataBody() }


    // MARK: : KvHttpRequestBodyInternal

    @usableFromInline
    func makeRequestHandler(_ clientCallbacks: ClientCallbacks?, responseBlock: @escaping ResponseBlock) -> KvHttpRequestHandler {
        RequestHandler(configuration, clientCallbacks, responseBlock: responseBlock)
    }


    // MARK: .RequestHandler

    private class RequestHandler : KvHttpCollectingBodyRequestHandler {

        init(_ configuration: Configuration, _ clientCallbacks: ClientCallbacks? , responseBlock: @escaping KvHttpCollectingBodyRequestHandler.ResponseBlock) {
            self.clientCallbacks = clientCallbacks

            super.init(bodyLengthLimit: configuration.bodyLengthLimit, responseBlock: responseBlock)
        }


        private let clientCallbacks: ClientCallbacks?


        // MARK: : KvHttpRequestHandler

        override func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.RequestIncident) -> KvHttpResponseProvider? {
            clientCallbacks?.onHttpIncident?(incident)
        }


        override func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
            clientCallbacks?.onError?(error)
        }

    }

}



// MARK: - KvHttpRequestJsonBody

/// See ``json(of:)`` fabric for details.
public struct KvHttpRequestJsonBody<Value : Decodable> : KvHttpRequestRequiredBodyInternal {

    public typealias Value = Value


    @usableFromInline
    var configuration: Configuration = .init()


    @usableFromInline
    init() { }


    // MARK: Fabrics

    /// - Returns: An HTTP request body handler decoding received bytes as a JSON.
    ///
    /// The resulting type of body processing result is `T`. If the body is missing or can't be decoded then simple response with 400 (Bad Request) status code is returned.
    ///
    /// Below is an example of response decoding JSON respresentation of standard *DateComponents* and returning received date in ISO 8601 format.
    ///
    /// ```swift
    /// KvHttpResponse.dynamic
    ///     .requestBody(.json(of: DateComponents.self))
    ///     .content {
    ///         guard let date = $0.requestBody.date else { return .badRequest }
    ///         return .string { ISO8601DateFormatter().string(from: date) }
    ///     }
    /// ```
    @inlinable
    public static func json<T : Decodable>(of type: T.Type) -> KvHttpRequestJsonBody<T> { KvHttpRequestJsonBody<T>() }


    // MARK: : KvHttpRequestBodyInternal

    @usableFromInline
    func makeRequestHandler(_ clientCallbacks: ClientCallbacks?, responseBlock: @escaping ResponseBlock) -> KvHttpRequestHandler {
        RequestHandler(configuration, clientCallbacks, responseBlock: responseBlock)
    }


    // MARK: .RequestHandler

    private class RequestHandler : KvHttpJsonRequestHandler<Value> {

        init(_ configuration: Configuration, _ clientCallbacks: ClientCallbacks?, responseBlock: @escaping KvHttpJsonRequestHandler<Value>.ResponseBlock) {
            self.clientCallbacks = clientCallbacks

            super.init(bodyLengthLimit: configuration.bodyLengthLimit, responseBlock: responseBlock)
        }


        private let clientCallbacks: ClientCallbacks?


        // MARK: : KvHttpRequestHandler

        override func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.RequestIncident) -> KvHttpResponseProvider? {
            clientCallbacks?.onHttpIncident?(incident)
        }


        override func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
            clientCallbacks?.onError?(error)
        }

    }

}
