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
@usableFromInline
class KvHttpRequestContext {

    let method: KvHttpMethod
    let url: URL
    let urlComponents: URLComponents
    /// Path components are not part of *URLComponents*.
    let pathComponents: ArraySlice<String>


    init?(from head: KvHttpServer.RequestHead) {
        guard let url = URL(string: head.uri),
              let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        method = head.method
        self.url = url
        self.urlComponents = urlComponents
        pathComponents = KvHttpRequestContext.normalizedPathComponents(from: url)
    }


    // MARK: Auxiliaries

    private static func normalizedPathComponents(from url: URL) -> ArraySlice<String> {
        let c = url.pathComponents

        guard !c.isEmpty else { return [ ] }

        let lowerBound = c.startIndex.advanced(by: c.first! != "/" ? 0 : 1)
        let upperBound = c.endIndex.advanced(by: c.count <= 1 || c.last! != "/" ? 0 : -1)

        return c[lowerBound ..< upperBound]
    }

}
