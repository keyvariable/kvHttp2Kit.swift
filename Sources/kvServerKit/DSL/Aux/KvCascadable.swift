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
//  KvCascadable.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 10.10.2023.
//

// MARK: - KvCascadable

/// This protocol is used for cascaded configurations.
public protocol KvCascadable {

    /// - Returns: Composition where *addition* is one level deeper in the hierarchy.
    static func overlay(_ addition: Self, over base: Self) -> Self

    /// - Returns: Composition where *addition* and *base* are on the same level in the hierarchy.
    static func accumulate(_ addition: Self, into base: Self) -> Self

}


extension KvCascadable {

    @inlinable
    public static func overlay(_ addition: Self, over base: Self) -> Self { accumulate(addition, into: base) }

}



// MARK: - KvDefaultOverlayCascadable

public protocol KvDefaultOverlayCascadable : KvCascadable {

    static func overlay(_ addition: Self?, over base: Self) -> Self

    static func overlay(_ addition: Self, over base: Self?) -> Self

    static func overlay(_ addition: Self?, over base: Self?) -> Self?

}


extension KvDefaultOverlayCascadable {

    @inlinable
    public static func overlay(_ addition: Self?, over base: Self) -> Self { addition.map { overlay($0, over: base) } ?? base }


    @inlinable
    public static func overlay(_ addition: Self, over base: Self?) -> Self { base.map { overlay(addition, over: $0) } ?? addition }


    @inlinable
    public static func overlay(_ addition: Self?, over base: Self?) -> Self? { base.map { overlay(addition, over: $0) } ?? addition }

}



// MARK: - KvReplacingOverlayCascadable

public protocol KvReplacingOverlayCascadable : KvCascadable {

    static func overlay(_ addition: Self?, over base: Self) -> Self?

    static func overlay(_ addition: Self, over base: Self?) -> Self

    static func overlay(_ addition: Self?, over base: Self?) -> Self?

}


extension KvReplacingOverlayCascadable {

    @usableFromInline
    static func overlay(_ addition: Self, over base: Self) -> Self { addition }

    @usableFromInline
    static func overlay(_ addition: Self?, over base: Self) -> Self? { addition }

    @usableFromInline
    static func overlay(_ addition: Self, over base: Self?) -> Self { addition }

    @usableFromInline
    static func overlay(_ addition: Self?, over base: Self?) -> Self? { addition }

}



// MARK: - KvDefaultAccumulationCascadable

public protocol KvDefaultAccumulationCascadable : KvCascadable {

    static func accumulate(_ addition: Self?, into base: Self) -> Self

    static func accumulate(_ addition: Self, into base: Self?) -> Self

    static func accumulate(_ addition: Self?, into base: Self?) -> Self?

}


extension KvDefaultAccumulationCascadable {

    @inlinable
    public static func accumulate(_ addition: Self?, into base: Self) -> Self { addition.map { accumulate($0, into: base) } ?? base }


    @inlinable
    public static func accumulate(_ addition: Self, into base: Self?) -> Self { base.map { accumulate(addition, into: $0) } ?? addition }


    @inlinable
    public static func accumulate(_ addition: Self?, into base: Self?) -> Self? { base.map { accumulate(addition, into: $0) } ?? addition }

}
