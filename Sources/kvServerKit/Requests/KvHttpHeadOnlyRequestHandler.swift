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
//  KvHttpHeadOnlyRequestHandler.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 31.05.2023.
//

/// Simple handler for requests having no body. It just sends response passed to the initializer.
open class KvHttpHeadOnlyRequestHandler : KvHttpRequestHandler {

    public typealias ResponseBlock = () async -> KvHttpResponseProvider?



    @usableFromInline
    let responseBlock: ResponseBlock



    /// - Parameter response: Value to be sent to a client.
    @inlinable
    public init(responseBlock: @escaping ResponseBlock) {
        self.responseBlock = responseBlock
    }



    /// Initializes request handler producing constant response.
    ///
    /// - Parameter response: Value to be sent to a client.
    @inlinable
    public convenience init(response: KvHttpResponseProvider?) {
        self.init { response }
    }


    
    // MARK: : KvHttpRequestHandler

    /// See ``KvHttpRequestHandler``.
    public var contentLengthLimit: UInt { 0 }
    /// See ``KvHttpRequestHandler``.
    public var implicitBodyLengthLimit: UInt { 0 }


    /// See ``KvHttpRequestHandler``.
    public func httpClient(_ httpClient: KvHttpChannel.Client, didReceiveBodyBytes bytes: UnsafeRawBufferPointer) { }


    /// - Returns: Value of the receiver's `.response` property.
    ///
    /// See ``KvHttpRequestHandler``.
    open func httpClientDidReceiveEnd(_ httpClient: KvHttpChannel.Client) async -> KvHttpResponseProvider? {
        await responseBlock()
    }


    /// Override it to handle errors. Default implementation just prints error message to console.
    ///
    /// See ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
        print("\(type(of: self)) did catch error: \(error)")
    }

}
