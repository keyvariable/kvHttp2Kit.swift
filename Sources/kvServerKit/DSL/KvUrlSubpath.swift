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

import Foundation



// MARK: - KvUrlSubpathProtocol

/// Protocol the subpath representations conform to.
public protocol KvUrlSubpathProtocol {

    var components: ArraySlice<String> { get }

    var joined: String { get }


    init(safeComponents: ArraySlice<String>)

}



// MARK: - KvUnavailableUrlSubpath

/// Special type representing subpath when it's unavailable.
public struct KvUnavailableUrlSubpath : KvUrlSubpathProtocol {

    @inlinable
    public var components: ArraySlice<String> { [ ] }

    @inlinable
    public var joined: String { "" }


    @inlinable
    public init(safeComponents: ArraySlice<String>) { assert(components.isEmpty || (components.count == 1 && components[0] == "/")) }

}



// MARK: - KvUrlSubpath

/// Representaion of subpath in ``KvHttpResponse/DynamicResponse/Input`` of ``KvHttpResponse/DynamicResponse``.
public struct KvUrlSubpath : KvUrlSubpathProtocol {

    /// Sequence of path components.
    public let components: ArraySlice<String>


    /// Splits any of *components* containing path separators. The resulting components are used to initialize an instance.
    @inlinable
    public init(with components: ArraySlice<String>) {
        var iterator = components.enumerated().makeIterator()

        while let (offset, component) = iterator.next() {
            if let separatorIndex = component.firstIndex(of: "/") {
                var safeComonents = Array(components.prefix(offset))

                func Append<S : StringProtocol>(_ component: S) {
                    safeComonents.append(contentsOf: component[separatorIndex...]
                        .split(separator: "/", omittingEmptySubsequences: true)
                        .lazy.map { String($0) })
                }

                safeComonents.append(.init(component.prefix(upTo: separatorIndex)))
                Append(component[separatorIndex...])

                while let (_, component) = iterator.next() {
                    Append(component)
                }

                self.init(safeComponents: .init(safeComonents))
                return
            }
        }

        self.init(safeComponents: components)
    }


    /// Splits given *path* to path components and initializes an instance with the result.
    @inlinable
    public init(path: String) {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map { String($0) }
        self.init(safeComponents: ArraySlice(components))
    }


    /// - Warning: Provided components must not contain path separators and invalid characters.
    @inlinable
    public init(safeComponents: ArraySlice<String>) {
        assert(safeComponents.allSatisfy { !$0.contains("/") })

        self.components = safeComponents
    }


    // MARK: Operations

    /// A booelan value indicating whether the receiver is empty.
    @inlinable
    public var isEmpty: Bool { components.isEmpty }

    /// The receiver's *components* joined with standard path separator.
    @inlinable
    public var joined: String { components.joined(separator: "/") }


    /// A copy where occurences of "." and ".." special components are resolved.
    ///
    /// - Note: Empty subpath is the root. So standardized "a/../../b" is "b".
    @inlinable
    public var standardized: KvUrlSubpath {
        let standardizedComponents = components.reduce(into: Array<String>(), { partialResult, component in
            switch component {
            case ".":
                break
            case "..":
                guard !partialResult.isEmpty else { break }
                partialResult.removeLast()
            default:
                partialResult.append(component)
            }
        })

        return .init(with: .init(standardizedComponents))
    }


    /// - Returns: A boolean value indicating whether the receiver contains entire *prefix* subpath at the beginning.
    @inlinable
    public func starts(with prefix: KvUrlSubpath) -> Bool {
        components.starts(with: prefix.components)
    }


    /// - Returns: A slice of the receiver containing up to given number of components.
    @inlinable
    public func prefix(_ count: Int) -> KvUrlSubpath {
        .init(safeComponents: components.prefix(count))
    }


    /// - Returns: A slice of the receiver containing all but given number of components.
    @inlinable
    public func dropFirst(_ count: Int = 1) -> KvUrlSubpath {
        .init(safeComponents: components.dropFirst(count))
    }

}


// MARK: : Hashable

extension KvUrlSubpath : Hashable { }


// MARK: ExpressibleByStringLiteral

extension KvUrlSubpath : ExpressibleByStringLiteral {

    @inlinable
    public init(stringLiteral value: StringLiteralType) { self.init(path: value) }

}


// MARK: : ExpressibleByArrayLiteral

extension KvUrlSubpath : ExpressibleByArrayLiteral {

    @inlinable
    public init(arrayLiteral elements: String...) {
        self.init(with: elements[elements.indices])
    }

}
