//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2024 Svyatoslav Popov (info@keyvar.com).
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
//  KvHttpAcceptLanguage.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 12.02.2024.
//

public struct KvHttpAcceptLanguage { private init() { }

    // MARK: .Iterator

    /// Parses [`Accept-Language`](https://www.rfc-editor.org/rfc/rfc9110#section-12.5.4) HTTP header
    /// returning individual language tags with rank based on the quality and index.
    public struct Iterator : IteratorProtocol {

        public init(_ value: String) {
            characters = value.makeIterator()
        }


        private var characters: String.Iterator
        private var nextElementIndex: Int = 0


        // MARK: .Element

        public struct Element {

            /// A lowercased language tag.
            public let languageTag: LanguageTag
            public let rank: Rank


            // MARK: .LanguageTag

            public enum LanguageTag : Equatable {
                /// A lowercased language tag.
                case some(String)
                /// `*` token.
                case wildcard
            }


            // MARK: .Rank

            public struct Rank : Comparable {

                public let weight: Double
                /// Index in the list.
                public let index: Int


                // MARK: : Comparable

                public static func <(lhs: Rank, rhs: Rank) -> Bool {
                    if lhs.weight < rhs.weight { return true }
                    guard lhs.weight == rhs.weight else { return false }

                    return lhs.index < rhs.index
                }

            }

        }


        // MARK: : IteratorProtocol

        public mutating func next() -> Element? {

            enum State {
                case leadingWhitespace
                case tag
                /// Waiting for optional semicolon after `*` wildcard tag.
                case wildcard
                case q
                case equality
                /// Waiting for integer part of the quality value.
                case int
                /// Waiting for dot after integer part
                case dot(zeroFracFlag: Bool)
                /// Waiting for fractional part of the quality value.
                ///
                /// Associated value is index of expected fractional part digit.
                /// As stated in [RFC 9110, section 12.4.2](https://www.rfc-editor.org/rfc/rfc9110#section-12.4.2) the fractional part must be of maximum 3 digits.
                case frac(Int)
                /// Waiting for fractional part of the quality value.
                ///
                /// Parser expects only zeroes in fractional part when integer part is 1.
                /// As stated in [RFC 9110, section 12.4.2](https://www.rfc-editor.org/rfc/rfc9110#section-12.4.2) the fractional part must be of maximum 3 digits.
                case fracZero(Int)
                case trailingWhitespace
            }


            var state: State = .leadingWhitespace

            var tag = String()
            var weight: Double = 1.0
            var weightDigitScale: Double = 0.1


            /// It's designated to stop iteration when an element token is parsed.
            func EmitElement() -> Element {
                defer { nextElementIndex += 1 }

                return .init(languageTag: !tag.isEmpty ? .some(tag) : .wildcard,
                             rank: .init(weight: weight, index: nextElementIndex))
            }


            /// It's designated to stop iteration on errors.
            func InvalidateAndReturnNil() -> Element? {
                characters = "".makeIterator()
                return nil
            }


            while let c = characters.next() {
                switch state {
                case .leadingWhitespace:
                    if c.isWhitespace { break }
                    else if c.isLetter {
                        tag += c.lowercased()
                        state = .tag
                    }
                    else if c.isNumber {
                        tag += String(c)
                        state = .tag
                    }
                    else if c == "*" {
                        // `tag` is empty to indicate wildcard.
                        state = .wildcard
                    }
                    else { return InvalidateAndReturnNil() }

                case .tag:
                    if c.isLetter {
                        tag += c.lowercased()
                    }
                    else if c == "-" || c.isNumber {
                        tag += String(c)
                    }
                    else if c.isWhitespace {
                        state = .trailingWhitespace
                    }
                    else {
                        switch c {
                        case ",":
                            return EmitElement()
                        case ";":
                            state = .q
                        default:
                            return InvalidateAndReturnNil()
                        }
                    }

                case .wildcard:
                    if c.isWhitespace {
                        state = .trailingWhitespace
                    }
                    else {
                        switch c {
                        case ",":
                            return EmitElement()
                        case ";":
                            state = .q
                        default:
                            return InvalidateAndReturnNil()
                        }
                    }

                case .q:
                    switch c {
                    case "q", "Q":
                        state = .equality
                    default:
                        return InvalidateAndReturnNil()
                    }

                case .equality:
                    guard c == "=" else { return InvalidateAndReturnNil() }

                    state = .int

                case .int:
                    switch c {
                    case "0":
                        weight = 0.0
                        state = .dot(zeroFracFlag: false)
                    case "1":
                        assert(weight == 1.0)
                        state = .dot(zeroFracFlag: true)
                    default:
                        return InvalidateAndReturnNil()
                    }

                case .dot(let zeroFracFlag):
                    switch c {
                    case ".":
                        state = !zeroFracFlag ? .frac(0) : .fracZero(0)
                    case ",":
                        return EmitElement()
                    default:
                        if c.isWhitespace {
                            state = .trailingWhitespace
                        }
                        else { return InvalidateAndReturnNil() }
                    }

                case .frac(let digitIndex):
                    guard c != "," else { return EmitElement() }
                    guard !c.isWhitespace else {
                        state = .trailingWhitespace
                        break
                    }

                    guard digitIndex < 3,
                          let ascii = c.asciiValue
                    else { return InvalidateAndReturnNil() }

                    let digit: Int = numericCast(consume ascii) - 48 /* "0".asciiValue */
                    guard digit >= 0, digit <= 9 else { return InvalidateAndReturnNil() }

                    weight += Double(digit) * weightDigitScale
                    weightDigitScale *= 0.1

                    state = .frac(digitIndex + 1)

                case .fracZero(let digitIndex):
                    guard c != "," else { return EmitElement() }
                    guard !c.isWhitespace else {
                        state = .trailingWhitespace
                        break
                    }

                    guard digitIndex < 3,
                          c == "0"
                    else { return InvalidateAndReturnNil() }

                    state = .fracZero(digitIndex + 1)

                case .trailingWhitespace:
                    if c == "," { return EmitElement() }
                    else if !c.isWhitespace {
                        return InvalidateAndReturnNil()
                    }
                }
            }

            switch state {
            case .leadingWhitespace, .q, .equality, .int:
                return InvalidateAndReturnNil()
            case .tag, .wildcard, .dot(_), .frac(_), .fracZero(_), .trailingWhitespace:
                return EmitElement()
            }
        }

    }

}
