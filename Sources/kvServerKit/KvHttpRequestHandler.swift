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
//  KvHttpRequestHandler.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 30.05.2023.
//

/// Protocol for request handlers. See provided common request handlers.
public protocol KvHttpRequestHandler : AnyObject {

    /// Maximum acceptable value of `Content-Length` header.
    ///
    /// See ``implicitBodyLengthLimit``.
    var contentLengthLimit: UInt { get }
    /// Maximum acceptable number of bytes in request body when `Content-Length` header is missing. Pass 0 if request must have no body or empty body.
    ///
    /// See ``contentLengthLimit``.
    var implicitBodyLengthLimit: UInt { get }


    /// It's invoked when server receives bytes from the client related with the request.
    /// This method can be invoked multiple times for each received part of the request body.
    /// When all the request body bytes are passed to request handler, ``httpClientDidReceiveEnd(_:)`` method is invoked.
    func httpClient(_ httpClient: KvHttpChannel.Client, didReceiveBodyBytes bytes: UnsafeRawBufferPointer)

    /// It's invoked when the request is completely received (including it's body bytes) and is ready to be handled.
    func httpClientDidReceiveEnd(_ httpClient: KvHttpChannel.Client) async -> KvHttpResponseProvider?

    /// - Note: The client will continue to process requests.
    func httpClient(_ httpClient: KvHttpChannel.Client, didCatch error: Error)
    
}
