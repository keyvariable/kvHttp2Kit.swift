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
//  KvHttpRequestPreconditions.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 08.10.2023.
//

import Foundation

import kvHttpKit

import NIOHTTP1



struct KvHttpRequestPreconditions {

    var entityTag: EntityTag?
    var modificationDate: ModificationDate?



    // MARK: .EntityTag

    enum EntityTag {
        /// Associated header value is in String format to prevent redundant deserialization when this precondition is actually unused.
        case ifMatch(String)
        /// Associated header value is in String format to prevent redundant deserialization when this precondition is actually unused.
        case ifNoneMatch(String)
    }



    // MARK: .ModificationDate

    enum ModificationDate {
        /// Associated header value is in String format to prevent redundant deserialization when this precondition is actually unused.
        case ifModifiedSince(String)
        /// Associated header value is in String format to prevent redundant deserialization when this precondition is actually unused.
        case ifUnmodifiedSince(String)
    }



    // MARK: .RequestContext

    struct RequestContext {

        let method: HTTPMethod


        // MARK: Auxiliaries

        @inline(__always)
        fileprivate var isGetOrHeadMethod: Bool {
            switch method {
            case .GET, .HEAD:
                return true
            default:
                return false
            }
        }

    }



    // MARK: Operations

    /// - Returns: `Nil` when initial *response* meets preconditions or a replacement response (e.g. 304) otherwise.
    func process(for response: KvHttpResponseContent, in context: RequestContext) -> KvHttpResponseContent? {
        processEntityTag(for: response, in: context)
        ?? processModificationDate(for: response, in: context)
    }


    private func processEntityTag(for response: KvHttpResponseContent, in context: RequestContext) -> KvHttpResponseContent? {
        switch entityTag {
        case .ifMatch(let rawValues):
            guard let element = response.entityTag,
                  !element.options.contains(.weak)
            else {
                switch EntityTagParser.validate(rawValues) {
                case .success:
                    return .preconditionFailed
                case .failure(_):
                    return nil /*Precondition ignored*/
                }
            }

            switch EntityTagParser.is(element, in: rawValues) {
            case .success(let isContained):
                return isContained ? nil : .preconditionFailed
            case .failure(_):
                // Header is ignored on a parse failure.
                return nil
            }

        case .ifNoneMatch(let rawValues):
            guard let element = response.entityTag else { return nil }

            switch EntityTagParser.is(element, in: rawValues) {
            case .success(false):
                return nil
            case .success(true):
                return context.isGetOrHeadMethod ? .notModified : .preconditionFailed
            case .failure(_):
                // Header is ignored on a parse failure.
                return nil
            }

        case .none:
            return nil
        }
    }


    private func processModificationDate(for response: KvHttpResponseContent, in context: RequestContext) -> KvHttpResponseContent? {
        guard let date = response.modificationDate else { return nil /*Ignored*/ }

        switch modificationDate {
        case .ifModifiedSince(let rawValue):
            guard context.isGetOrHeadMethod else { return nil /*Precondition ignored*/ }

            if case .ifNoneMatch(_) = entityTag { return nil /*Precondition ignored*/ }

            guard let minimumDate = KvRFC9110.DateFormatter.date(from: rawValue)
            else { return nil /* Incorrect dates must be ignored [RFC 9110, 13.1.3](https://www.rfc-editor.org/rfc/rfc9110#section-13.1.3). */ }

            guard date > minimumDate else { return .notModified }

        case .ifUnmodifiedSince(let rawValue):
            if case .ifNoneMatch(_) = entityTag { return nil /*Precondition ignored*/ }
            
            guard let maximumDate = KvRFC9110.DateFormatter.date(from: rawValue)
            else { return nil /* Incorrect dates must be ignored [RFC 9110, 13.1.4](https://www.rfc-editor.org/rfc/rfc9110#section-13.1.4). */ }

            // - Note: Generally 2xx is allowed [RFC 9110, 13.1.4](https://www.rfc-editor.org/rfc/rfc9110#section-13.1.4).
            guard date <= maximumDate else { return .preconditionFailed }

        case .none:
            break
        }

        return nil/*TRUE*/
    }



    // MARK: .EntityTagParser

    /// - Note: It's internal to be visible for unit-tests.
    internal struct EntityTagParser {

        /// - Returns: Boolean value or parse error. The boolean value indicates whether *rawValues* contains *element*.
        ///
        /// Implementation uses FSM pattern.
        static func `is`(_ element: KvHttpEntityTag, in rawValues: String) -> Result<Bool, ParseError> {
            let isWeak = element.options.contains(.weak)
            var valueIterator = element.value.makeIterator()

            var isValueContained = false

            return parse(
                rawValues,
                onWildcard: { isValueContained = true },
                onWeakFlag: { $0 == isWeak && !isValueContained },
                onValueCharacter: { $0 == valueIterator.next() },
                onCommit: { isValueContained = isValueContained || (valueIterator.next() == nil) },
                onReset: { valueIterator = element.value.makeIterator() }
            )
            .map { isValueContained }
        }


        static func validate(_ rawValues: String) -> Result<Void, ParseError> {
            parse(rawValues, onWildcard: { }, onWeakFlag: { _ in true }, onValueCharacter: { _ in true }, onCommit: { }, onReset: { })
        }


        /// - Parameter onWeakFlag: Takes the weak state of an item and returns a boolean value indicating whether the item to be ignored.
        @inline(__always)
        private static func parse(_ input: String,
                                  onWildcard: () -> Void,
                                  onWeakFlag: (Bool) -> Bool,
                                  onValueCharacter: (Character) -> Bool,
                                  onCommit: () -> Void,
                                  onReset: () -> Void
        ) -> Result<Void, ParseError> {

            /// States of the FSM.
            enum State {
                /// Waiting for an item or ‘\*’ (if *first* is true), ignoring whitespace.
                case whitespace(first: Bool)
                /// Waiting for slash.
                case slash(ignoringItem: Bool)
                /// Waiting for left quote.
                case leftQuote(ignoringItem: Bool)
                /// Waiting for a value character or right quote.
                case value(ignoringItem: Bool)
                /// Waiting for comma after enclosing quote.
                case comma
                /// Waiting for whitespace only after valid wildcard‘\*’.
                case wildcard
            }


            var inputIterator = input.makeIterator()
            var state: State = .whitespace(first: true)

            while let c = inputIterator.next() {
                switch state {
                case .whitespace(let isFirst):
                    if c == "\"" {
                        state = .value(ignoringItem: !onWeakFlag(false))
                    }
                    else if c == "W" {
                        state = .slash(ignoringItem: !onWeakFlag(true))
                    }
                    else if isFirst, c == "*" {
                        state = .wildcard
                        onWildcard()
                    }
                    else if !c.isWhitespace {
                        return .failure(.unexpectedLeadingItemCharacter(c))
                    }

                case .slash(let ignoringItem):
                    guard c == "/" else { return .failure(.expectedSlash(c)) }

                    state = .leftQuote(ignoringItem: ignoringItem)

                case .leftQuote(let ignoringItem):
                    guard c == "\"" else { return .failure(.expectedLeadingQuote(c)) }

                    state = .value(ignoringItem: ignoringItem)

                case .value(ignoringItem: true):
                    if c == "\"" {
                        state = .comma
                        onReset()
                    }

                case .value(ignoringItem: false):
                    if c == "\"" {
                        onCommit()
                        state = .comma
                        onReset()
                    }
                    else if !onValueCharacter(c) {
                        state = .value(ignoringItem: true)
                    }

                case .comma:
                    if c == "," {
                        state = .whitespace(first: false)
                    }
                    else if !c.isWhitespace {
                        return .failure(.expectedComma(c))
                    }

                case .wildcard:
                    guard c.isWhitespace else { return .failure(.invalidWildcard(c)) }
                }
            }

            switch state {
            case .whitespace(first: true), .comma, .wildcard:
                return .success(())
            case .whitespace(first: false), .slash, .leftQuote, .value:
                return .failure(.unexpectedEnd)
            }
        }


        // MARK: .ParseError

        enum ParseError : LocalizedError, Equatable {

            case expectedComma(Character)
            case expectedLeadingQuote(Character)
            case expectedSlash(Character)
            case invalidWildcard(Character)
            case unexpectedEnd
            case unexpectedLeadingItemCharacter(Character)


            // MARK: : LocalizedError

            var errorDescription: String? {
                switch self {
                case .expectedComma(let character):
                    return "Comma is expected after ETag but ‘\(character)’ has encountered"
                case .expectedLeadingQuote(let character):
                    return "Quotation mark is expected after ‘W/’ but ‘\(character)’ has encountered"
                case .expectedSlash(let character):
                    return "Slash is expected after ‘W’ but ‘\(character)’ has encountered"
                case .invalidWildcard(let character):
                    return "Unexpected character ‘\(character)’ in wildcard value"
                case .unexpectedEnd:
                    return "Unexpected end of ETag list"
                case .unexpectedLeadingItemCharacter(let character):
                    return "Unexpected character ‘\(character)’ at the beginning of a ETag"
                }
            }
        }

    }

}
