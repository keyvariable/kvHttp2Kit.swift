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
//  KvHttpCollectingBodyRequestHandler.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 31.05.2023.
//

import Foundation



/// Request handler collecting body fragments and then handling entire body.
open class KvHttpCollectingBodyRequestHandler : KvHttpRequestHandler {

    public typealias BodyLimits = KvHttpRequest.BodyLimits

    public typealias ResponseBlock = (Data?) async -> KvHttpResponseProvider?



    public let bodyLimits: BodyLimits



    @usableFromInline
    let responseBlock: ResponseBlock

    @usableFromInline
    var bodyData: Data?



    /// - Parameter responseBlock: Block passed with collected request body data if available and returning response to be send to a client.
    @inlinable
    public init(bodyLimits: BodyLimits, responseBlock: @escaping ResponseBlock) {
        self.bodyLimits = bodyLimits
        self.responseBlock = responseBlock
    }



    // MARK: : KvHttpRequestHandler

    /// See ``KvHttpRequestHandler``.
    @inlinable public var contentLengthLimit: UInt { bodyLimits.contentLength }
    /// See ``KvHttpRequestHandler``.
    @inlinable public var implicitBodyLengthLimit: UInt { bodyLimits.implicit }


    /// See ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didReceiveBodyBytes bytes: UnsafeRawBufferPointer) {
        bodyData?.append(bytes.assumingMemoryBound(to: UInt8.self))
        ?? (bodyData = .init(bytes))
    }


    /// Invokes the receiver's `.responseBlock` passed with the colleted body data and returns the result.
    ///
    /// - Returns: Invocation result of the receiver's `.responseBlock` passed with the colleted body data.
    ///
    /// See ``KvHttpRequestHandler``.
    @inlinable
    open func httpClientDidReceiveEnd(_ httpClient: KvHttpChannel.Client) async -> KvHttpResponseProvider? {
        await responseBlock(bodyData)
    }


    /// Override it to handle errors. Default implementation just prints error message to console.
    ///
    /// See ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
        print("\(type(of: self)) did catch error: \(error)")
    }

}
