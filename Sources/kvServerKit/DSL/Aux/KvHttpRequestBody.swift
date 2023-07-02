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
//  KvHttpRequestBody.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 19.06.2023.
//

import Foundation



// MARK: - KvHttpRequestBody

public class KvHttpRequestBody<Value> {

    public typealias Value = Value

    public typealias BodyLimits = KvHttpRequest.BodyLimits



    @usableFromInline
    typealias ResponseBlock = (Value) async throws -> KvHttpResponseProvider



    @usableFromInline
    var configuration: Configuration



    fileprivate init(with configuration: Configuration = .init()) {
        self.configuration = configuration
    }



    // MARK: Required Methods to Override

    func makeRequestHandler(responseBlock: @escaping ResponseBlock) -> KvHttpRequestHandler {
        fatalError("This implementation must never be invoked")
    }



    // MARK: .Configuration

    @usableFromInline
    struct Configuration {

        @usableFromInline
        var bodyLimits: BodyLimits


        @usableFromInline
        init(bodyLimits: BodyLimits = 16384 /* 16 KiB */) {
            self.bodyLimits = bodyLimits
        }

    }



    // MARK: Operations

    /// It's designated to unwrap result of *ResponseBlock*.
    fileprivate func catching(_ block: () async throws -> KvHttpResponseProvider) async -> KvHttpResponseProvider {
        do { return try await block() }
        catch {
#if DEBUG
            return .internalServerError.string("\(error)")
#else // !DEBUG
            return .internalServerError
#endif // !DEBUG
        }
    }

}



// MARK: - KvHttpRequestVoidBodyValue

public struct KvHttpRequestVoidBodyValue {

    init() { }

}



// MARK: - KvHttpRequestProhibitedBody

public class KvHttpRequestProhibitedBody : KvHttpRequestBody<KvHttpRequestVoidBodyValue> {

    @usableFromInline
    init() {
        super.init(with: .init(bodyLimits: 0))
    }


    override func makeRequestHandler(responseBlock: @escaping ResponseBlock) -> KvHttpRequestHandler {
        KvHttpHeadOnlyRequestHandler {
            await self.catching { try await responseBlock(.init()) }
        }
    }

}



// MARK: - KvHttpRequestRequiredBody

/// Base class for declarations of HTTP request body
///
/// See it's fabrics and modifiers.
public class KvHttpRequestRequiredBody<Value> : KvHttpRequestBody<Value> { }



// MARK: Modifiers

extension KvHttpRequestRequiredBody {

    @usableFromInline
    @inline(__always)
    func map(_ transform: (inout Configuration) -> Void) -> Self {
        transform(&configuration)
        return self
    }


    /// This modifier declares limits for HTTP body and related headers. E.g. there are limits for length of the body and for value of `Content-Length` HTTP header.
    ///
    /// Previously declared values are replaced.
    ///
    /// See: ``bodyLimits(contentLength:)``, ``bodyLimits(implicit:)``, ``BodyLimits``.
    @inlinable
    public func bodyLimits(_ bodyLimits: BodyLimits) -> Self {
        map { $0.bodyLimits = bodyLimits }
    }


    /// This modifier declares limit for value of `Content-Length` HTTP header.
    ///
    /// Previously declared value is replaced.
    ///
    /// See: ``bodyLimits(_:)``, ``bodyLimits(implicit:)``.
    @inlinable
    public func bodyLimits(contentLength: UInt) -> Self {
        map { $0.bodyLimits.contentLength = contentLength }
    }


    /// This modifier declares limit for length of HTTP request body.
    ///
    /// Previously declared value is replaced.
    ///
    /// See: ``bodyLimits(contentLength:)``, ``bodyLimits(implicit:)``.
    @inlinable
    public func bodyLimits(implicit: UInt) -> Self {
        map { $0.bodyLimits.implicit = implicit }
    }

}



// MARK: - KvHttpRequestReducingBody

@usableFromInline
class KvHttpRequestReducingBody<PartialResult> : KvHttpRequestRequiredBody<PartialResult> {

    @usableFromInline
    let requestHandlerProvider: (KvHttpRequestReducingBody, @escaping ResponseBlock) -> KvHttpRequestHandler


    @usableFromInline
    init(_ initialResult: PartialResult,
         _ nextPartialResult: @escaping (PartialResult, UnsafeRawBufferPointer) -> PartialResult)
    {
        requestHandlerProvider = { body, responseBlock in
            KvHttpReducingRequestHandler(
                bodyLimits: body.configuration.bodyLimits,
                initial: initialResult,
                nextPartialResult: nextPartialResult,
                responseBlock: { partialResult in
                    await body.catching { try await responseBlock(partialResult) }
                }
            )
        }
    }


    @usableFromInline
    init(into initialResult: PartialResult,
         _ updateAccumulatingResult: @escaping (inout PartialResult, UnsafeRawBufferPointer) -> Void)
    {
        requestHandlerProvider = { body, responseBlock in
            KvHttpReducingRequestHandler(
                bodyLimits: body.configuration.bodyLimits,
                into: initialResult,
                updateAccumulatingResult: updateAccumulatingResult,
                responseBlock: { partialResult in
                    await body.catching { try await responseBlock(partialResult) }
                }
            )
        }
    }


    // MARK: : KvHttpRequestBody

    override func makeRequestHandler(responseBlock: @escaping ResponseBlock) -> KvHttpRequestHandler {
        requestHandlerProvider(self, responseBlock)
    }

}


extension KvHttpRequestRequiredBody {

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
    ///     KvHttpResponse.dynamic
    ///         .requestBody(.reduce(0 as UInt8, { accumulator, buffer in
    ///             buffer.reduce(accumulator, &+)
    ///         }))
    ///         .content {
    ///             .string("0x" + String($0.requestBody, radix: 16, uppercase: true))
    ///         }
    ///
    @inlinable
    public static func reduce(
        _ initialResult: Value,
        _ nextPartialResult: @escaping (Value, UnsafeRawBufferPointer) -> Value
    ) -> KvHttpRequestRequiredBody<Value>
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
    ) -> KvHttpRequestRequiredBody<Value>
    {
        KvHttpRequestReducingBody(into: initialResult, updateAccumulatingResult)
    }

}



// MARK: - KvHttpRequestDataBody

@usableFromInline
class KvHttpRequestDataBody : KvHttpRequestRequiredBody<Data?> {

    @usableFromInline
    init() { }


    override func makeRequestHandler(responseBlock: @escaping ResponseBlock) -> KvHttpRequestHandler {
        KvHttpCollectingBodyRequestHandler(
            bodyLimits: configuration.bodyLimits,
            responseBlock: { data in
                await self.catching { try await responseBlock(data) }
            }
        )
    }

}


extension KvHttpRequestRequiredBody {

    /// - Returns: An HTTP request body handler collecting the received bytes into standard *Data*.
    ///
    /// The resulting type of body processing result is `Data?`.
    /// If the body is empty or missing then the result is `nil`.
    ///
    /// Below is an example of an echo response:
    ///
    ///     KvHttpResponse.dynamic
    ///         .requestBody(.data)
    ///         .content { .binary($0.requestBody ?? Data()) }
    ///
    @inlinable
    public static var data: KvHttpRequestRequiredBody<Data?> { KvHttpRequestDataBody() }

}



// MARK: - KvHttpRequestJsonBody

@usableFromInline
class KvHttpRequestJsonBody<Value : Decodable> : KvHttpRequestRequiredBody<Value> {

    override func makeRequestHandler(responseBlock: @escaping ResponseBlock) -> KvHttpRequestHandler {
        KvHttpJsonRequestHandler<Value>(
            bodyLimits: configuration.bodyLimits,
            responseBlock: { value in
                switch value {
                case .success(let payload):
                    return await self.catching {
                        try await responseBlock(payload)
                    }
#if DEBUG
                case .failure(let error):
                    return .badRequest.string("\(error)")
#else // !DEBUG
                case .failure:
                    return .badRequest
#endif // !DEBUG
                }
            }
        )
    }

}


extension KvHttpRequestRequiredBody {

    /// - Returns: An HTTP request body handler decoding received bytes as a JSON.
    ///
    /// The resulting type of body processing result is `T`. If the body is missing or can't be decoded then simple response with 400 (Bad Request) status code is returned.
    ///
    /// Below is an example of response decoding JSON respresentation of standard *DateComponents* and returning received date in ISO 8601 format.
    ///
    ///     KvHttpResponse.dynamic
    ///         .requestBody(.json(of: DateComponents.self))
    ///         .content {
    ///             guard let date = $0.requestBody.date else { return .badRequest }
    ///             return .string(date.formatted(.iso8601))
    ///         }
    ///
    public static func json<T : Decodable>(of type: T.Type) -> KvHttpRequestRequiredBody<T> { KvHttpRequestJsonBody<T>() }

}
