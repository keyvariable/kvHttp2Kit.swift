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
//  KvForEach.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 04.07.2023.
//

/// `KvForEach()` provides dynamic list of responses.
///
/// Let `urls` is an array of file URLs.  Then code providing responses with contents of the files can be implemented as shown below:
///
///     KvForEach(urls) { url in
///         KvGroup(url.path) {
///             KvHttpResponse.static {
///                 guard let stream = InputStream(url: url) else { return .internalServerError }
///                 return .binary(stream)
///             }
///         }
///     }
///
/// Also it can be used to provide responses for all cases of an enumeration.
///
/// - Note: The content is generated once before server is started. Any changes in ``data`` after ``content`` block is invoked take no effect.
public struct KvForEach<Data, Content> where Data : Sequence {

    /// Collection of data that is used to generate content dynamically.
    let data: Data

    /// A function returning content for an element of the receiver's ``data``.
    let content: (Data.Element) -> Content


    @usableFromInline
    init(data: Data, content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.content = content
    }

}



// MARK: : KvResponseGroup where Content : KvResponse

extension KvForEach : KvResponseGroup where Content : KvResponseGroup {

    public typealias Body = KvNeverResponseGroup


    /// Creates dynamically generated collection of response groups from given *data* sequence.
    @inlinable
    public init(_ data: Data, @KvResponseGroupBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data: data, content: content)
    }

}



// MARK: : KvResponseGroup where Content : KvResponse

extension KvForEach : KvResponseGroupInternalProtocol where Self : KvResponseGroup {

    func insertResponses<A>(to accumulator: A) where A : KvResponseAccumulator {
        data.forEach {
            content($0).insertResponses(to: accumulator)
        }
    }

}
