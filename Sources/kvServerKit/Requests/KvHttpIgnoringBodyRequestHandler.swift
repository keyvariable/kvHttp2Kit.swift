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
//  KvHttpIgnoringBodyRequestHandler.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 28.06.2023.
//

/// Ignores all the request body bytes.
///
/// Note that the body limits are applied.
public class KvHttpIgnoringBodyRequestHandler : KvHttpRequestHandler {

    public typealias BodyLimits = KvHttpRequest.BodyLimits

    public typealias ResponseBlock = () async -> KvHttpResponseProvider?



    public let bodyLimits: BodyLimits



    @usableFromInline
    let responseBlock: () async -> KvHttpResponseProvider?



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
    public func httpClient(_ httpClient: KvHttpChannel.Client, didReceiveBodyBytes bytes: UnsafeRawBufferPointer) { }


    /// Invokes the receiver's `.responseBlock` passed with the colleted body data and returns the result.
    ///
    /// - Returns: Invocation result of the receiver's `.responseBlock` passed with the colleted body data.
    ///
    /// See ``KvHttpRequestHandler``.
    @inlinable
    public func httpClientDidReceiveEnd(_ httpClient: KvHttpChannel.Client) async -> KvHttpResponseProvider? {
        await responseBlock()
    }


    /// Override it to handle errors. Default implementation just prints error message to console.
    ///
    /// See ``KvHttpRequestHandler``.
    @inlinable
    public func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
        print("\(type(of: self)) did catch error: \(error)")
    }

}
