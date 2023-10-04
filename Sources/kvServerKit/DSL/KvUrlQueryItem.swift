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
//  KvUrlQueryItem.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 12.07.2023.
//

/// A type representing item of URL query item.
///
/// Use fabrics to create instances of *KvUrlQueryItem*.
///
/// Below is an example for various URL query item declarations:
///
/// ```swift
/// KvHttpResponse.dynamic
///     .query(.required("int", of: Int.self))
///     .query(.optional("string"))
///     .query(.optional("float", of: Float.self))
///     .query(.required("base64", parseBlock: { $0.flatMap { Data(base64Encoded: $0) } ?? .failure } ))
///     .query(.bool("flag"))
///     .query(.void("void"))
///     .content(callback)
/// ```
public struct KvUrlQueryItem<Value> {

    @usableFromInline
    let name: String

    @usableFromInline
    let defaultBlock: (() -> Value)?

    @usableFromInline
    let parseBlock: (String?) -> KvUrlQueryParseResult<Value>


    @usableFromInline
    var isRequired: Bool { defaultBlock == nil }


    @usableFromInline
    init(name: String, defaultBlock: (() -> Value)?, parseBlock: @escaping (String?) -> KvUrlQueryParseResult<Value>) {
        self.name = name
        self.defaultBlock = defaultBlock
        self.parseBlock = parseBlock
    }

}


// MARK: Arbitrary Type

extension KvUrlQueryItem {

    /// - Returns: A declaration of required URL query item where raw value is parsed with custom *parseBlock*.
    ///
    /// The type of the resulting value is `Value`.
    ///
    /// If an URL query doesn't contain item named *name* or *parseBlock* fails then the response doen't match the request.
    @inlinable
    public static func `required`(_ name: String, parseBlock: @escaping (String?) -> KvUrlQueryParseResult<Value>) -> Self {
        .init(name: name, defaultBlock: nil, parseBlock: parseBlock)
    }


    /// - Returns: A declaration of optional URL query item where raw value is parsed with custom *parseBlock*.
    ///
    /// The type of the resulting value is `Value?`.
    ///
    /// If an URL query doesn't contain item named *name* then the resulting value is `nil`.
    @inlinable
    public static func `optional`<Wrapped>(_ name: String, parseBlock: @escaping (String?) -> KvUrlQueryParseResult<Value>) -> Self
    where Value == Optional<Wrapped>
    {
        .init(name: name, defaultBlock: { nil }, parseBlock: parseBlock)
    }

}


// MARK: Value == Void

extension KvUrlQueryItem where Value == Void {

    /// - Returns: A declaration of required URL query item having to value. E.g. "?a" URL.
    ///
    /// The type of the resulting value is `Void`.
    ///
    /// If an URL query doesn't contain item named *name* or the item has a value then the response doen't match the request.
    @inlinable
    public static func void(_ name: String) -> Self {
        .required(name) { rawValue in
            switch rawValue {
            case .none:
                return .success(())
            case .some:
                return .failure
            }
        }
    }

}


// MARK: Value == Bool

extension KvUrlQueryItem where Value == Bool {

    /// - Returns: A declaration of optional boolean URL query item.
    ///
    /// The type of the resulting value is `Bool`.
    ///
    /// If an URL query doesn't contain item named *name* then the resulting value is `false`.
    /// Also:
    /// - `false` is returned for "false", "FALSE", "False", "no", "NO", "No", "0";
    /// - `true` is returned for `nil`, "true", "TRUE", "True", "yes", "YES", "Yes", "1".
    @inlinable
    public static func bool(_ name: String) -> Self {
        .init(name: name, defaultBlock: { false }) { rawValue in
            switch rawValue {
            case .none, "true", "TRUE", "True", "yes", "YES", "Yes", "1":
                return .success(true)

            case "false", "FALSE", "False", "no", "NO", "No", "0":
                return .success(false)

            default:
                return .failure
            }
        }
    }

}


// MARK: Value == String

extension KvUrlQueryItem where Value == String {

    /// - Returns: A declaration of required URL query item where the result is raw value as is or an empty string whether the item has a value.
    ///
    /// The type of the resulting value is `String`.
    ///
    /// If an URL query doesn't contain item named *name* then the response doen't match the request.
    @inlinable
    public static func `required`(_ name: String) -> Self {
        .required(name) { rawValue in .success(rawValue ?? "") }
    }

}


// MARK: Value == String?

extension KvUrlQueryItem where Value == String? {

    /// - Returns: A declaration of required URL query item where the result is raw value as is.
    ///
    /// The type of the resulting value is `String?`.
    ///
    /// If an URL query doesn't contain item named *name* then the response doen't match the request.
    @inlinable
    public static func `required`(_ name: String) -> Self {
        .required(name, parseBlock: KvUrlQueryParseResult.success(_:))
    }


    /// - Returns: A declaration of optional URL query item where the result is raw value as is or `nil` whether the item has a value.
    ///
    /// The type of the resulting value is `String?`.
    ///
    /// If an URL query doesn't contain item named *name* then the resulting value is `nil`.
    @inlinable
    public static func `optional`(_ name: String) -> Self {
        .optional(name, parseBlock: KvUrlQueryParseResult.success(_:))
    }

}


// MARK: Value : LosslessStringConvertible

extension KvUrlQueryItem where Value : LosslessStringConvertible {

    /// - Returns: A declaration of required URL query item where raw value is parsed with standard `LosslessStringConvertible.init?(_ description: String)` method of the resulting type.
    ///
    /// The type of the resulting value is `Value`.
    ///
    /// If an URL query doesn't contain item named *name* or `LosslessStringConvertible.init?(_ description: String)` returns `nil` then the response doen't match the request.
    @inlinable
    public static func `required`(_ name: String, of type: Value.Type) -> Self {
        .required(name) { rawValue in
            guard let value = rawValue.flatMap(Value.init(_:)) else { return .failure }

            return .success(value)
        }
    }

}


extension KvUrlQueryItem {

    /// - Returns: A declaration of required URL query item where raw value is parsed with standard `LosslessStringConvertible.init?(_ description: String)` method of the resulting type.
    ///
    /// The type of the resulting value is `Value?`.
    ///
    /// If an URL query doesn't contain item named *name* then the response doen't match the request.
    @inlinable
    public static func `required`<Wrapped>(_ name: String, of type: Value.Type) -> Self
    where Value == Optional<Wrapped>, Wrapped : LosslessStringConvertible
    {
        .required(name, parseBlock: optionalParseBlock(_:))
    }


    /// - Returns: A declaration of optional URL query item where raw value is parsed with standard `LosslessStringConvertible.init?(_ description: String)` method of the resulting type.
    ///
    /// The type of the resulting value is `Value?`.
    ///
    /// If an URL query doesn't contain item named *name* then the resulting value is `nil`.
    @inlinable
    public static func `optional`<Wrapped>(_ name: String, of type: Wrapped.Type) -> Self
    where Value == Optional<Wrapped>, Wrapped : LosslessStringConvertible
    {
        .optional(name, parseBlock: optionalParseBlock(_:))
    }


    @usableFromInline
    static func optionalParseBlock<Wrapped>(_ rawValue: String?) -> KvUrlQueryParseResult<Value>
    where Value == Optional<Wrapped>, Wrapped : LosslessStringConvertible
    {
        guard let rawValue = rawValue else { return .success(nil) }
        guard let value = Wrapped(rawValue) else { return .failure }

        return .success(value)
    }

}
