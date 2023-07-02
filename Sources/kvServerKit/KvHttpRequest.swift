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
//  KvHttpRequest.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 31.05.2023.
//

public class KvHttpRequest {

    private init() { }



    // MARK: Typealiases

    public typealias Handler = KvHttpRequestHandler

    public typealias CollectingBodyHandler = KvHttpCollectingBodyRequestHandler
    public typealias HeadOnlyHandler = KvHttpHeadOnlyRequestHandler
    public typealias JsonHandler = KvHttpJsonRequestHandler



    // MARK: .BodyLimits

    public struct BodyLimits : ExpressibleByIntegerLiteral {

        /// Maximum acceptable value of `Content-Length` header.
        public var contentLength: UInt

        /// Maximum acceptable number of bytes in request body when `Content-Length` header is missing. Pass 0 if request must have no body or empty body.
        public var implicit: UInt


        /// Memberwise initializer.
        @inlinable
        public init(contentLength: UInt, implicit: UInt) {
            self.contentLength = contentLength
            self.implicit = implicit
        }


        /// Initializes an instance where all the limits are equal to given value.
        @inlinable public init(_ value: UInt) { self.init(contentLength: value, implicit: value) }


        // MARK: : ExpressibleByIntegerLiteral

        @inlinable public init(integerLiteral value: UInt) { self.init(value) }

    }

}
