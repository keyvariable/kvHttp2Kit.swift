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
//  KvHttpHeadOnlyRequestHandler.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 31.05.2023.
//

/// Simple handler for requests having no body. It just sends response passed to the initializer.
open class KvHttpHeadOnlyRequestHandler : KvHttpRequestHandler {

    public typealias ResponseBlock = () throws -> KvHttpResponseProvider?



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

    /// See ``KvHttpRequestHandler/bodyLengthLimit`` for details.
    @inlinable public var bodyLengthLimit: UInt { 0 }


    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable public func httpClient(_ httpClient: KvHttpChannel.Client, didReceiveBodyBytes bytes: UnsafeRawBufferPointer) { }


    /// - Returns: Value of the receiver's `.response` property.
    ///
    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable
    open func httpClientDidReceiveEnd(_ httpClient: KvHttpChannel.Client) throws -> KvHttpResponseProvider? {
        return try responseBlock()
    }


    /// A trivial implementation of ``KvHttpRequestHandler/httpClient(_:didCatch:)-32t5p``.
    /// Override it to provide custom incident handling. 
    ///
    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didCatch incident: KvHttpChannel.RequestIncident) -> KvHttpResponseProvider? {
        return nil
    }


    /// Override it to handle errors. Default implementation just prints error message to console.
    ///
    /// - SeeAlso ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error) {
        print("\(type(of: self)) did catch error: \(error)")
    }

}
