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
//  KvHttpRequestContext.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 30.09.2023.
//

import Foundation



/// It's used to identify responses in a dispatcher.
public class KvHttpRequestContext {

    public let method: KvHttpMethod
    public let urlComponents: URLComponents

    /// Decomposed path.
    /// - Note: *URLComponents* contains only composed path.
    public private(set) lazy var path: KvUrlSubpath = .init(path: urlComponents.path)


    init?(_ client: KvHttpChannel.Client, _ head: KvHttpServer.RequestHead) {
        guard let isSecureHTTP = client.httpChannel?.configuration.http.isSecure else { return nil }

        let uri = "\(isSecureHTTP ? "https" : "http")://\((head.headers.first(name: "host") ?? ""))\(head.uri)"

        guard let urlComponents = URLComponents(string: uri) else { return nil }

        self.method = head.method
        self.urlComponents = urlComponents
    }

}
