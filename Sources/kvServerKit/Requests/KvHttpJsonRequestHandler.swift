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
//  KvHttpJsonRequestHandler.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 31.05.2023.
//

import Foundation



/// Passes body data to JSON decoder.
///
/// - Note: Requests having no body are ignored and `nil` response are returned.
open class KvHttpJsonRequestHandler<T : Decodable> : KvHttpRequestHandler {

    public typealias BodyLimits = KvHttpRequest.BodyLimits

    public typealias ResponseBlock = (Result<T, Error>) async -> KvHttpResponseProvider?



    @inlinable public var bodyLimits: BodyLimits { underlying.bodyLimits }



    /// - Parameter responseBlock: Block passed with result of decoding collected request body data and returning response to be send to a client.
    @inlinable
    public init(bodyLimits: BodyLimits, responseBlock: @escaping ResponseBlock) {
        underlying = .init(bodyLimits: bodyLimits, responseBlock: { data in
            guard let data = data else { return nil }

            let result = Result {
                try JSONDecoder().decode(T.self, from: data)
            }

            return await responseBlock(result)
        })
    }



    @usableFromInline
    internal let underlying: KvHttpCollectingBodyRequestHandler

    

    // MARK: : KvHttpRequestHandler

    /// See ``KvHttpRequestHandler``.
    @inlinable public var contentLengthLimit: UInt { bodyLimits.contentLength }
    /// See ``KvHttpRequestHandler``.
    @inlinable public var implicitBodyLengthLimit: UInt { bodyLimits.implicit }


    /// See ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didReceiveBodyBytes bytes: UnsafeRawBufferPointer) {
        underlying.httpClient(httpClient, didReceiveBodyBytes: bytes)
    }


    /// Invokes the receiver's `.responseBlock` passed with the colleted body data and returns the result.
    ///
    /// - Returns: Invocation result of the receiver's `.responseBlock` passed with the colleted body data.
    ///
    /// See ``KvHttpRequestHandler``.
    @inlinable
    open func httpClientDidReceiveEnd(_ httpClient: KvHttpChannel.Client) async -> KvHttpResponseProvider? {
        await underlying.httpClientDidReceiveEnd(httpClient)
    }


    /// Override it to handle errors. Default implementation just prints error message to console.
    ///
    /// See ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
        print("\(type(of: self)) did catch error: \(error)")
    }

}
