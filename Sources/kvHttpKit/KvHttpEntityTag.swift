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
//  KvHttpEntityTag.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 28.10.2023.
//

import Foundation

import kvKit



/// Representation of HTTP entity tags.
public struct KvHttpEntityTag {

    /// Value of entity tag.
    public let value: String
    /// Options of entity tag. E.g. weak state.
    public let options: Options


    @usableFromInline
    init(safeValue: String, options: Options = [ ]) {
        self.value = safeValue
        self.options = options
    }


    /// Initializes entity tag from a raw string.
    ///
    /// - Warning: It's recommended to avoid this initializer due to performance penalty. Initializer validates passed *value*. Use fabrics.
    @inlinable
    public init?(_ value: String, options: Options = [ ]) {
        guard value.allSatisfy({ $0 != "\"" && $0 != "\0" }) else { return nil }

        self.init(safeValue: value, options: options)
    }


    // MARK: Fabrics

    /// - Returns: An instance where value is the result of `data.base64EncodedString()`.
    ///
    /// - SeeAlso: ``base64(withBytesOf:options:)``.
    @inlinable
    public static func base64(_ data: Data, options: Options = [ ]) -> Self {
        .init(safeValue: data.base64EncodedString(), options: options)
    }


    /// - Returns: An instance where value is a Base64 representation of bytes of *x*.
    ///
    /// - Note: `Data.base64EncodedString()` method with default encoding options is used.
    ///
    /// - SeeAlso: ``base64(_:options:)``.
    @inlinable
    public static func base64<T>(withBytesOf x: T, options: Options = [ ]) -> Self {
        .init(safeValue: KvStringKit.base64(withBytesOf: x), options: options)
    }


    /// - Returns: An instance where value is a hexadecimal representation of bytes from *data*.
    @inlinable
    public static func hex<D>(_ data: D, options: Options = [ ]) -> Self
    where D : DataProtocol
    {
        .init(safeValue: KvBase16.encodeAsString(data), options: options)
    }


    /// - Returns: An instance where value is a hexadecimal representation of bytes of *x*.
    @inlinable
    public static func hex<T>(withBytesOf x: T, options: Options = [ ]) -> Self {
        withUnsafeBytes(of: x) {
            .hex($0, options: options)
        }
    }


    /// - Returns: An instance where value is a standard string representation of given UUID.
    @inlinable
    public static func uuid(_ value: UUID, options: Options = [ ]) -> Self {
        .init(safeValue: value.uuidString, options: options)
    }


    // MARK: .Options

    /// Options of entity tags. E.g. weak state.
    public struct Options : OptionSet {

        /// Weak state option constant.
        public static let weak: Self = .init(rawValue: 1 << 0)


        // MARK: : OptionSet

        public let rawValue: UInt

        @inlinable public init(rawValue: UInt) { self.rawValue = rawValue }
    }


    // MARK: Operations

    /// HTTP representation of the receiver.
    @inlinable
    public var httpRepresentation: String {
        !options.contains(.weak) ? "\"\(value)\"" : "W/\"\(value)\""
    }
}
