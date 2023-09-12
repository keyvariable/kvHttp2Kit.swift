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
//  KvHttpReducingRequestHandler.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 23.06.2023.
//

/// Processes request body fragments when they are received and collects the result until the body is completely processed.
///
/// This handler is designated to process request bodies on the fly minimizing memory usage and improving performance of large body processing.
///
/// See: ``init(bodyLimits:initial:nextPartialResult:responseBlock:)``, ``init(bodyLimits:into:updateAccumulatingResult:responseBlock:)``.
open class KvHttpReducingRequestHandler<PartialResult> : KvHttpRequestHandler {

    public typealias BodyLimits = KvHttpRequest.BodyLimits

    public typealias ResponseBlock = (PartialResult) async -> KvHttpResponseProvider?



    public let bodyLimits: BodyLimits



    @usableFromInline
    let bodyCallback: (UnsafeRawBufferPointer) -> Void

    @usableFromInline
    let responseBlock: () async -> KvHttpResponseProvider?



    /// The partial result and received body fragments are passed to *nextPartialResult* block and partial result is replaced with value returned by *nextPartialResult*.
    /// When entire body is processed, last partial result is passed to *responseBlock*.
    ///
    /// See: ``init(bodyLimits:into:updateAccumulatingResult:responseBlock:)``.
    @inlinable
    public init(bodyLimits: BodyLimits,
                initial initialResult: PartialResult,
                nextPartialResult: @escaping (PartialResult, UnsafeRawBufferPointer) -> PartialResult,
                responseBlock: @escaping ResponseBlock)
    {
        var partialResult = initialResult

        self.bodyLimits = bodyLimits
        self.bodyCallback = { bytes in
            partialResult = nextPartialResult(partialResult, bytes)
        }
        self.responseBlock = {
            await responseBlock(partialResult)
        }
    }


    /// The mutable partial result and received body fragments are passed to *updateAccumulatingResult* block.
    /// When entire body is processed, partial result is passed to *responseBlock*.
    ///
    /// See: ``init(bodyLimits:initial:nextPartialResult:responseBlock:)``.
    @inlinable
    public init(bodyLimits: BodyLimits,
                into initialResult: PartialResult,
                updateAccumulatingResult: @escaping (inout PartialResult, UnsafeRawBufferPointer) -> Void,
                responseBlock: @escaping ResponseBlock)
    {
        var partialResult = initialResult

        self.bodyLimits = bodyLimits
        self.bodyCallback = { bytes in
            updateAccumulatingResult(&partialResult, bytes)
        }
        self.responseBlock = {
            await responseBlock(partialResult)
        }
    }



    // MARK: : KvHttpRequestHandler

    /// See ``KvHttpRequestHandler``.
    @inlinable public var contentLengthLimit: UInt { bodyLimits.contentLength }
    /// See ``KvHttpRequestHandler``.
    @inlinable public var implicitBodyLengthLimit: UInt { bodyLimits.implicit }


    /// See ``KvHttpRequestHandler``.
    @inlinable
    open func httpClient(_ httpClient: KvHttpChannel.Client, didReceiveBodyBytes bytes: UnsafeRawBufferPointer) {
        bodyCallback(bytes)
    }


    /// Invokes the receiver's `.responseBlock` passed with the colleted body data and returns the result.
    ///
    /// - Returns: Invocation result of the receiver's `.responseBlock` passed with the colleted body data.
    ///
    /// See ``KvHttpRequestHandler``.
    @inlinable
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
