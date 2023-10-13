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
//  KvUrlSubpath.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 13.10.2023.
//

// MARK: - KvUrlSubpathProtocol

/// Protocol the subpath representations conform to.
public protocol KvUrlSubpathProtocol {

    var components: ArraySlice<String> { get }

    var joined: String { get }


    init(with components: ArraySlice<String>)

}



// MARK: - KvUnavailableUrlSubpath

/// Special type representing subpath when it's unavailable.
public struct KvUnavailableUrlSubpath : KvUrlSubpathProtocol {

    @inlinable
    public var components: ArraySlice<String> { [ ] }

    @inlinable
    public var joined: String { "" }


    @inlinable
    public init(with components: ArraySlice<String>) { assert(components.isEmpty || (components.count == 1 && components[0] == "/")) }

}



// MARK: - KvUrlSubpath

/// Representaion of subpath in ``KvHttpResponse/DynamicResponse/Context`` of ``KvHttpResponse/DynamicResponse``.
public struct KvUrlSubpath : KvUrlSubpathProtocol {

    /// Sequence of path components.
    public let components: ArraySlice<String>

    /// The receiver's *components* joined with standard path separator.
    @inlinable
    public var joined: String { components.joined(separator: "/") }


    @inlinable
    public init(with components: ArraySlice<String>) { self.components = components }

}
