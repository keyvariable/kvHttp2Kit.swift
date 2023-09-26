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



    // MARK: .Constants

    public struct Constants {

        /// Default limit for requests having body.
        @inlinable public static var bodyLengthLimit: UInt { 16384 /* 16 KiB */ }

    }

}
