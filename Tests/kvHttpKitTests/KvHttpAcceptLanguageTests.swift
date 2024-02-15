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
//  KvHttpAcceptLanguageTests.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 12.02.2024.
//

import XCTest

@testable import kvHttpKit



final class KvHttpAcceptLanguageTests : XCTestCase {

    // MARK: - testIterator()

    func testIterator() {
        typealias Iterator = KvHttpAcceptLanguage.Iterator

        func E(_ languageTag: Iterator.Element.LanguageTag, _ weight: Double, _ index: Int) -> Iterator.Element {
            .init(languageTag: languageTag, rank: .init(weight: weight, index: index))
        }

        func E(_ languageTag: String, _ weight: Double, _ index: Int) -> Iterator.Element { E(.some(languageTag), weight, index) }

        func Assert(_ header: String, expecting expected: Iterator.Element...) {
            let result = Array(IteratorSequence(Iterator(header)))
            var resultIterator = result.makeIterator()

            var expectedIterator = expected.makeIterator()
            var index = 0

            var isInputPrinted = false

            func OneTimeInputMessage() -> String {
                guard !isInputPrinted else { return "" }
                isInputPrinted = true

                return "; result: \(result); expected: \(expected)"
            }

            while let r = resultIterator.next() {
                defer { index += 1 }

                guard let e = expectedIterator.next()
                else { return XCTFail("Unexpected element in result \(result) at \(index) index\(OneTimeInputMessage())") }

                XCTAssertEqual(r.rank.index, index, "Element \(r) at \(index) index has unexpected index in the rank\(OneTimeInputMessage())")
                XCTAssertEqual(r.languageTag, e.languageTag, "Element \(r) at \(index) index has unexpected language tag; expecting \(e.languageTag)\(OneTimeInputMessage())")
                XCTAssertEqual(r.rank.weight, e.rank.weight, accuracy: 1e-4, "Element \(r) at \(index) index has unexpected weight; expecting \(e.rank.weight)\(OneTimeInputMessage())")
            }

            XCTAssertNil(expectedIterator.next(), "Result \(result) contains less elements then expected\(OneTimeInputMessage())")
        }

        // Success

        Assert("")
        Assert("   ")

        Assert("en", expecting: E("en", 1.0, 0))
        Assert("*", expecting: E(.wildcard, 1.0, 0))

        Assert("en-US;q=1"    , expecting: E("en-US", 1.0  , 0))
        Assert("en-US;q=1."   , expecting: E("en-US", 1.0  , 0))
        Assert("en-US;q=1.0"  , expecting: E("en-US", 1.0  , 0))
        Assert("en-US;q=0"    , expecting: E("en-US", 0.0  , 0))
        Assert("en-US;q=0."   , expecting: E("en-US", 0.0  , 0))
        Assert("en-US;q=0.0"  , expecting: E("en-US", 0.0  , 0))
        Assert("en-US;q=0.833", expecting: E("en-US", 0.833, 0))

        Assert("en-US,*;q=0.5,zh-Hans;q=0.833",
               expecting: E("en-US", 1.0, 0), E(.wildcard, 0.5, 1), E("zh-Hans", 0.833, 2))
        Assert("  en-US  ,  *;q=0.5   ,  zh-Hans;q=0.833   , en-GB   ",
               expecting: E("en-US", 1.0, 0), E(.wildcard, 0.5, 1), E("zh-Hans", 0.833, 2), E("en-GB", 1.0, 3))

        // Errors

        Assert("en,", expecting: E("en", 1.0, 0))
        Assert("  en   ,   ", expecting: E("en", 1.0, 0))

        Assert("en zh")

        Assert(",en")
        Assert("en;")
        Assert("en ;")
        Assert("en ;q=1")
        Assert("en;q")
        Assert("en;q  ")
        Assert("en;q=")
        Assert("en;q=  ")
        Assert("en;q=2")
        Assert("en;q=-1")
        Assert("en;q=1.001")
        Assert("en;q=0.1234")
        Assert("en q=0.123")
        Assert("en;q+0.123")

        Assert("q=0.123")

        Assert("en-US,* ;q=0.5,zh-Hans;q=0.833",
               expecting: E("en-US", 1.0, 0))
        Assert("en-US,*; q=0.5,zh-Hans;q=0.833",
               expecting: E("en-US", 1.0, 0))
        Assert("en-US,*;q=0.5,zh- Hans;q=0.833",
               expecting: E("en-US", 1.0, 0), E(.wildcard, 0.5, 1))
    }

}
