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
//  KvHttpResponseInput.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 14.10.2023.
//

/// Type representing processed content of an HTTP request declared as ``KvHttpResponse``. It's passed to the response's content callback.
public struct KvHttpResponseInput<QueryValue, RequestHeaders, RequestBodyValue, SubpathValue> {

    /// Result of URL query processing. Use related modifiers of ``KvHttpResponse/ParameterizedResponse`` to enable processing of URL query.
    public let query: QueryValue

    /// Result of custom handler of HTTP request headers. Use related modifiers of ``KvHttpResponse/ParameterizedResponse`` to provide custom handler of HTTP request headers.
    public let requestHeaders: RequestHeaders

    /// Result of HTTP request body processing. Use related modifiers of ``KvHttpResponse/ParameterizedResponse`` to enable processing of HTTP request body.
    public let requestBody: RequestBodyValue

    /// When processing of URL subpath is enabled it's a path relative to response's position the URL hierarchy or value tranformed by custom callback.
    /// See ``KvHttpResponse/ParameterizedResponse/subpath`` modifier for details.
    public let subpath: SubpathValue

}
