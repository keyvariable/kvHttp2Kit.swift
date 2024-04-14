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

import kvHttpKit



/// Ignores all the request body bytes.
///
/// Note that the body limits are applied.
public class KvHttpIgnoringBodyRequestHandler : KvHttpRequestHandler {

    public typealias ResponseBlock = (KvHttpResponseProvider) -> Void



    /// See ``KvHttpRequestHandler/bodyLengthLimit`` for details.
    public let bodyLengthLimit: UInt



    @usableFromInline
    let responseBlock: ResponseBlock



    /// - Parameter bodyLengthLimit: See ``KvHttpRequestHandler/bodyLengthLimit`` for details. Default value is ``KvHttpRequest/Constants/bodyLengthLimit``.
    /// - Parameter responseBlock: Block passed with collected request body data if available and returning response to be send to a client.
    @inlinable
    public init(bodyLengthLimit: UInt = KvHttpRequest.Constants.bodyLengthLimit, responseBlock: @escaping ResponseBlock) {
        self.bodyLengthLimit = bodyLengthLimit
        self.responseBlock = responseBlock
    }



    // MARK: : KvHttpRequestHandler

    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable
    public func httpClient(_ httpClient: KvHttpChannel.Client, didReceiveBodyBytes bytes: UnsafeRawBufferPointer) { }


    /// Invokes the receiver's `.responseBlock` passed with the colleted body data and returns the result.
    ///
    /// - Returns: Invocation result of the receiver's `.responseBlock` passed with the colleted body data.
    ///
    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable
    public func httpClientDidReceiveEnd(_ httpClient: KvHttpChannel.Client, completion: KvHttpResponseProvider) {
        responseBlock(completion)
    }


    /// A trivial implementation of ``KvHttpRequestHandler/httpClient(_:didCatch:)-32d8h``.
    /// Override it to provide custom incident handling. 
    ///
    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.RequestIncident) -> KvHttpResponseContent? {
        return nil
    }


    /// Override it to handle errors. Default implementation just prints error message to console.
    ///
    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable
    public func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
        print("\(type(of: self)) did catch error: \(error)")
    }

}
