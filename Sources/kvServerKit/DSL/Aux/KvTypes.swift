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
//  KvTypes.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 14.10.2023.
//

// MARK: - KvFilterResult

/// Filtering result type. It's used to indicate filtering result and provide additional context that can be used later.
public enum KvFilterResult<Accepted> {

    case accepted(Accepted)
    case rejected


    // MARK: Fabrics

    /// - Returns: Unwrapped *optional* accosiated with ``accepted(_:)-swift.enum.case`` or ``rejected-swift.enum.case`` otherwise.
    @inlinable
    public static func unwrapping(_ optional: Accepted?) -> Self {
        switch optional {
        case .some(let value):
            return .accepted(value)
        case .none:
            return .rejected
        }
    }


    // MARK: Operations

    @inlinable
    public func map<A>(_ transformation: (Accepted) throws -> A) rethrows -> KvFilterResult<A> {
        switch self {
        case .accepted(let value):
            return .accepted(try transformation(value))
        case .rejected:
            return .rejected
        }
    }


    @inlinable
    public func flatMap<A>(_ transformation: (Accepted) throws -> KvFilterResult<A>) rethrows -> KvFilterResult<A> {
        switch self {
        case .accepted(let value):
            return try transformation(value)
        case .rejected:
            return .rejected
        }
    }

}
