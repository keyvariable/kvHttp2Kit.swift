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
//  KvRFC9110.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 12.10.2023.
//

import Foundation



/// Collection of auxliaries related to RFC9110 standard.
public struct KvRFC9110 {

    private init() { }

}



// MARK: .Date

extension KvRFC9110 {

    // TODO: Replace underlying standard `DateFormatter` with fast implementation with no mutual access.
    public struct DateFormatter {

        @usableFromInline
        static let shared = make()


        private init() { }


        // MARK: Operations

        /// - Returns: An instance of `DateFormatter` configured to operate with RFC9110 dates. E.g. Last-Modified or If-Modified-Since.
        public static func make() -> Foundation.DateFormatter {
            let formatter = Foundation.DateFormatter()

            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(abbreviation: "GMT")!
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"

            return formatter
        }


        /// - Returns: Date from RFC9110 string representation.
        @inlinable
        public static func date(from string: String) -> Date? {
            shared.date(from: string)
        }


        /// - Returns: RFC9110 string representation from given *date*.
        @inlinable
        public static func string(from date: Date) -> String {
            shared.string(from: date)
        }

    }

}
