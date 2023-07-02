//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2023 Svyatoslav Popov.
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
//  KvUrlQueryItemGroup.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 12.06.2023.
//

// MARK: - KvUrlQueryItemGroup

public protocol KvUrlQueryItemGroup {

    associatedtype Value

}



// MARK: - KvRawUrlQueryItemGroupProtocol

public protocol KvRawUrlQueryItemGroupProtocol : KvUrlQueryItemGroup {

    typealias Transform = (KvHttpResponse.RawUrlQuery?) -> KvUrlQueryParseResult<Value>

    var transform: Transform { get }

}



// MARK: - KvUrlQueryItemGroupMap

public struct KvUrlQueryItemGroupMap<Source, Value> : KvUrlQueryItemGroup
where Source : KvUrlQueryItemGroup
{

    public typealias Transform = (Source.Value) -> KvUrlQueryParseResult<Value>


    @usableFromInline
    let source: Source

    @usableFromInline
    let transform: Transform


    @usableFromInline
    init(_ source: Source, transform: @escaping Transform) {
        self.source = source
        self.transform = transform
    }


    @usableFromInline
    init(_ source: Source, transform: @escaping (Source.Value) -> Value) {
        self.init(source, transform: { .success(transform($0)) })
    }

}



// MARK: - KvRawUrlQueryItemGroup

public struct KvRawUrlQueryItemGroup<Value> : KvRawUrlQueryItemGroupProtocol {

    public let transform: Transform


    @usableFromInline
    init(_ transform: @escaping Transform) {
        self.transform = transform
    }


    @usableFromInline
    init(_ transform: @escaping (KvHttpResponse.RawUrlQuery?) -> Value) {
        self.init { .success(transform($0)) }
    }

}



// MARK: - KvEmptyUrlQueryItemGroup

public struct KvEmptyUrlQueryItemGroup : KvUrlQueryItemGroup {

    public typealias Value = Void

}



// MARK: - KvUrlQueryItemGroupOfOne

public protocol KvUrlQueryItemGroupOfOneProtocol : KvUrlQueryItemGroup {

    typealias Ammended<T> = KvUrlQueryItemGroupOfTwo<Self, KvUrlQueryItemGroupOfOne<T>>
    typealias Mapped<T> = KvUrlQueryItemGroupMap<Self, T>

    func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T>

}


extension KvUrlQueryItemGroupOfOneProtocol {

    @inlinable
    public func map<T>(_ transform: @escaping (Value) -> T) -> Mapped<T> { .init(self, transform: transform) }


    @inlinable
    public func flatMap<T>(_ transform: @escaping (Value) -> KvUrlQueryParseResult<T>) -> Mapped<T> { .init(self, transform: transform) }

}


public struct KvUrlQueryItemGroupOfOne<Value> : KvUrlQueryItemGroupOfOneProtocol {

    @usableFromInline
    let item: KvUrlQueryItem<Value>


    @usableFromInline
    init(_ item: KvUrlQueryItem<Value>) {
        self.item = item
    }


    @inlinable
    public func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T> { .init(self, .init(item)) }

}



// MARK: - KvUrlQueryItemGroupOfTwo

public protocol KvUrlQueryItemGroupOfTwoProtocol : KvUrlQueryItemGroup
where Value == (G0.Value, G1.Value)
{

    associatedtype G0 : KvUrlQueryItemGroup
    associatedtype G1 : KvUrlQueryItemGroup

    typealias Ammended<T> = KvUrlQueryItemGroupOfThree<G0, G1, KvUrlQueryItemGroupOfOne<T>>
    typealias Mapped<T> = KvUrlQueryItemGroupMap<Self, T>

    func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T>

}


extension KvUrlQueryItemGroupOfTwoProtocol {

    @inlinable
    public func map<T>(_ transform: @escaping (G0.Value, G1.Value) -> T) -> Mapped<T> { .init(self, transform: transform) }


    @inlinable
    public func flatMap<T>(_ transform: @escaping (G0.Value, G1.Value) -> KvUrlQueryParseResult<T>) -> Mapped<T> { .init(self, transform: transform) }

}


public struct KvUrlQueryItemGroupOfTwo<G0, G1> : KvUrlQueryItemGroupOfTwoProtocol
where G0 : KvUrlQueryItemGroup, G1 : KvUrlQueryItemGroup
{

    @usableFromInline let g0: G0
    @usableFromInline let g1: G1


    @usableFromInline
    init(_ g0: G0, _ g1: G1) {
        (self.g0, self.g1) = (g0, g1)
    }


    @inlinable
    public func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T> { .init(g0, g1, .init(item)) }

}



// MARK: - KvUrlQueryItemGroupOfThree

public protocol KvUrlQueryItemGroupOfThreeProtocol : KvUrlQueryItemGroup
where Value == (G0.Value, G1.Value, G2.Value)
{

    associatedtype G0 : KvUrlQueryItemGroup
    associatedtype G1 : KvUrlQueryItemGroup
    associatedtype G2 : KvUrlQueryItemGroup

    typealias Ammended<T> = KvUrlQueryItemGroupOfFour<G0, G1, G2, KvUrlQueryItemGroupOfOne<T>>
    typealias Mapped<T> = KvUrlQueryItemGroupMap<Self, T>

    func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T>

}

extension KvUrlQueryItemGroupOfThreeProtocol {

    @inlinable
    public func map<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value) -> T) -> Mapped<T> { .init(self, transform: transform) }


    @inlinable
    public func flatMap<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value) -> KvUrlQueryParseResult<T>) -> Mapped<T> { .init(self, transform: transform) }

}


public struct KvUrlQueryItemGroupOfThree<G0, G1, G2> : KvUrlQueryItemGroupOfThreeProtocol
where G0 : KvUrlQueryItemGroup, G1 : KvUrlQueryItemGroup, G2 : KvUrlQueryItemGroup
{

    @usableFromInline let g0: G0
    @usableFromInline let g1: G1
    @usableFromInline let g2: G2


    @inlinable
    public init(_ g0: G0, _ g1: G1, _ g2: G2) {
        (self.g0, self.g1, self.g2) = (g0, g1, g2)
    }


    @inlinable
    public func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T> { .init(g0, g1, g2, .init(item)) }

}



// MARK: - KvUrlQueryItemGroupOfFour

public protocol KvUrlQueryItemGroupOfFourProtocol : KvUrlQueryItemGroup
where Value == (G0.Value, G1.Value, G2.Value, G3.Value)
{

    associatedtype G0 : KvUrlQueryItemGroup
    associatedtype G1 : KvUrlQueryItemGroup
    associatedtype G2 : KvUrlQueryItemGroup
    associatedtype G3 : KvUrlQueryItemGroup

    typealias Ammended<T> = KvUrlQueryItemGroupOfFive<G0, G1, G2, G3, KvUrlQueryItemGroupOfOne<T>>
    typealias Mapped<T> = KvUrlQueryItemGroupMap<Self, T>

    func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T>

}

extension KvUrlQueryItemGroupOfFourProtocol {

    @inlinable
    public func map<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value) -> T) -> Mapped<T> { .init(self, transform: transform) }


    @inlinable
    public func flatMap<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value) -> KvUrlQueryParseResult<T>) -> Mapped<T> { .init(self, transform: transform) }

}


public struct KvUrlQueryItemGroupOfFour<G0, G1, G2, G3> : KvUrlQueryItemGroupOfFourProtocol
where G0 : KvUrlQueryItemGroup, G1 : KvUrlQueryItemGroup, G2 : KvUrlQueryItemGroup, G3 : KvUrlQueryItemGroup
{

    @usableFromInline let g0: G0
    @usableFromInline let g1: G1
    @usableFromInline let g2: G2
    @usableFromInline let g3: G3


    @inlinable
    public init(_ g0: G0, _ g1: G1, _ g2: G2, _ g3: G3) {
        (self.g0, self.g1, self.g2, self.g3) = (g0, g1, g2, g3)
    }


    @inlinable
    public func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T> { .init(g0, g1, g2, g3, .init(item)) }

}



// MARK: - KvUrlQueryItemGroupOfFive

public protocol KvUrlQueryItemGroupOfFiveProtocol : KvUrlQueryItemGroup
where Value == (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value)
{

    associatedtype G0 : KvUrlQueryItemGroup
    associatedtype G1 : KvUrlQueryItemGroup
    associatedtype G2 : KvUrlQueryItemGroup
    associatedtype G3 : KvUrlQueryItemGroup
    associatedtype G4 : KvUrlQueryItemGroup

    typealias Ammended<T> = KvUrlQueryItemGroupOfSix<G0, G1, G2, G3, G4, KvUrlQueryItemGroupOfOne<T>>
    typealias Mapped<T> = KvUrlQueryItemGroupMap<Self, T>

    func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T>

}

extension KvUrlQueryItemGroupOfFiveProtocol {

    @inlinable
    public func map<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value) -> T) -> Mapped<T> { .init(self, transform: transform) }


    @inlinable
    public func flatMap<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value) -> KvUrlQueryParseResult<T>) -> Mapped<T> { .init(self, transform: transform) }

}


public struct KvUrlQueryItemGroupOfFive<G0, G1, G2, G3, G4> : KvUrlQueryItemGroupOfFiveProtocol
where G0 : KvUrlQueryItemGroup, G1 : KvUrlQueryItemGroup, G2 : KvUrlQueryItemGroup, G3 : KvUrlQueryItemGroup, G4 : KvUrlQueryItemGroup
{

    @usableFromInline let g0: G0
    @usableFromInline let g1: G1
    @usableFromInline let g2: G2
    @usableFromInline let g3: G3
    @usableFromInline let g4: G4


    @inlinable
    public init(_ g0: G0, _ g1: G1, _ g2: G2, _ g3: G3, _ g4: G4) {
        (self.g0, self.g1, self.g2, self.g3, self.g4) = (g0, g1, g2, g3, g4)
    }


    @inlinable
    public func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T> { .init(g0, g1, g2, g3, g4, .init(item)) }

}



// MARK: - KvUrlQueryItemGroupOfSix

public protocol KvUrlQueryItemGroupOfSixProtocol : KvUrlQueryItemGroup
where Value == (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value)
{

    associatedtype G0 : KvUrlQueryItemGroup
    associatedtype G1 : KvUrlQueryItemGroup
    associatedtype G2 : KvUrlQueryItemGroup
    associatedtype G3 : KvUrlQueryItemGroup
    associatedtype G4 : KvUrlQueryItemGroup
    associatedtype G5 : KvUrlQueryItemGroup

    typealias Ammended<T> = KvUrlQueryItemGroupOfSeven<G0, G1, G2, G3, G4, G5, KvUrlQueryItemGroupOfOne<T>>
    typealias Mapped<T> = KvUrlQueryItemGroupMap<Self, T>

    func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T>

}

extension KvUrlQueryItemGroupOfSixProtocol {

    @inlinable
    public func map<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value) -> T) -> Mapped<T> { .init(self, transform: transform) }


    @inlinable
    public func flatMap<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value) -> KvUrlQueryParseResult<T>) -> Mapped<T> { .init(self, transform: transform) }

}


public struct KvUrlQueryItemGroupOfSix<G0, G1, G2, G3, G4, G5> : KvUrlQueryItemGroupOfSixProtocol
where G0 : KvUrlQueryItemGroup, G1 : KvUrlQueryItemGroup, G2 : KvUrlQueryItemGroup, G3 : KvUrlQueryItemGroup, G4 : KvUrlQueryItemGroup,
      G5 : KvUrlQueryItemGroup
{

    @usableFromInline let g0: G0
    @usableFromInline let g1: G1
    @usableFromInline let g2: G2
    @usableFromInline let g3: G3
    @usableFromInline let g4: G4
    @usableFromInline let g5: G5


    @inlinable
    public init(_ g0: G0, _ g1: G1, _ g2: G2, _ g3: G3, _ g4: G4, _ g5: G5) {
        (self.g0, self.g1, self.g2, self.g3, self.g4, self.g5) = (g0, g1, g2, g3, g4, g5)
    }


    @inlinable
    public func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T> { .init(g0, g1, g2, g3, g4, g5, .init(item)) }

}



// MARK: - KvUrlQueryItemGroupOfSeven

public protocol KvUrlQueryItemGroupOfSevenProtocol : KvUrlQueryItemGroup
where Value == (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value)
{

    associatedtype G0 : KvUrlQueryItemGroup
    associatedtype G1 : KvUrlQueryItemGroup
    associatedtype G2 : KvUrlQueryItemGroup
    associatedtype G3 : KvUrlQueryItemGroup
    associatedtype G4 : KvUrlQueryItemGroup
    associatedtype G5 : KvUrlQueryItemGroup
    associatedtype G6 : KvUrlQueryItemGroup

    typealias Ammended<T> = KvUrlQueryItemGroupOfEight<G0, G1, G2, G3, G4, G5, G6, KvUrlQueryItemGroupOfOne<T>>
    typealias Mapped<T> = KvUrlQueryItemGroupMap<Self, T>

    func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T>

}

extension KvUrlQueryItemGroupOfSevenProtocol {

    @inlinable
    public func map<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value) -> T) -> Mapped<T> { .init(self, transform: transform) }


    @inlinable
    public func flatMap<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value) -> KvUrlQueryParseResult<T>) -> Mapped<T> { .init(self, transform: transform) }

}


public struct KvUrlQueryItemGroupOfSeven<G0, G1, G2, G3, G4, G5, G6> : KvUrlQueryItemGroupOfSevenProtocol
where G0 : KvUrlQueryItemGroup, G1 : KvUrlQueryItemGroup, G2 : KvUrlQueryItemGroup, G3 : KvUrlQueryItemGroup, G4 : KvUrlQueryItemGroup,
      G5 : KvUrlQueryItemGroup, G6 : KvUrlQueryItemGroup
{

    @usableFromInline let g0: G0
    @usableFromInline let g1: G1
    @usableFromInline let g2: G2
    @usableFromInline let g3: G3
    @usableFromInline let g4: G4
    @usableFromInline let g5: G5
    @usableFromInline let g6: G6


    @inlinable
    public init(_ g0: G0, _ g1: G1, _ g2: G2, _ g3: G3, _ g4: G4, _ g5: G5, _ g6: G6) {
        (self.g0, self.g1, self.g2, self.g3, self.g4, self.g5, self.g6) = (g0, g1, g2, g3, g4, g5, g6)
    }


    @inlinable
    public func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T> { .init(g0, g1, g2, g3, g4, g5, g6, .init(item)) }

}



// MARK: - KvUrlQueryItemGroupOfEight

public protocol KvUrlQueryItemGroupOfEightProtocol : KvUrlQueryItemGroup
where Value == (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value, G7.Value)
{

    associatedtype G0 : KvUrlQueryItemGroup
    associatedtype G1 : KvUrlQueryItemGroup
    associatedtype G2 : KvUrlQueryItemGroup
    associatedtype G3 : KvUrlQueryItemGroup
    associatedtype G4 : KvUrlQueryItemGroup
    associatedtype G5 : KvUrlQueryItemGroup
    associatedtype G6 : KvUrlQueryItemGroup
    associatedtype G7 : KvUrlQueryItemGroup

    typealias Ammended<T> = KvUrlQueryItemGroupOfNine<G0, G1, G2, G3, G4, G5, G6, G7, KvUrlQueryItemGroupOfOne<T>>
    typealias Mapped<T> = KvUrlQueryItemGroupMap<Self, T>

    func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T>

}

extension KvUrlQueryItemGroupOfEightProtocol {

    @inlinable
    public func map<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value, G7.Value) -> T) -> Mapped<T> { .init(self, transform: transform) }


    @inlinable
    public func flatMap<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value, G7.Value) -> KvUrlQueryParseResult<T>) -> Mapped<T> { .init(self, transform: transform) }

}


public struct KvUrlQueryItemGroupOfEight<G0, G1, G2, G3, G4, G5, G6, G7> : KvUrlQueryItemGroupOfEightProtocol
where G0 : KvUrlQueryItemGroup, G1 : KvUrlQueryItemGroup, G2 : KvUrlQueryItemGroup, G3 : KvUrlQueryItemGroup, G4 : KvUrlQueryItemGroup,
      G5 : KvUrlQueryItemGroup, G6 : KvUrlQueryItemGroup, G7 : KvUrlQueryItemGroup
{

    @usableFromInline let g0: G0
    @usableFromInline let g1: G1
    @usableFromInline let g2: G2
    @usableFromInline let g3: G3
    @usableFromInline let g4: G4
    @usableFromInline let g5: G5
    @usableFromInline let g6: G6
    @usableFromInline let g7: G7


    @inlinable
    public init(_ g0: G0, _ g1: G1, _ g2: G2, _ g3: G3, _ g4: G4, _ g5: G5, _ g6: G6, _ g7: G7) {
        (self.g0, self.g1, self.g2, self.g3, self.g4, self.g5, self.g6, self.g7) = (g0, g1, g2, g3, g4, g5, g6, g7)
    }


    @inlinable
    public func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T> { .init(g0, g1, g2, g3, g4, g5, g6, g7, .init(item)) }

}



// MARK: - KvUrlQueryItemGroupOfNine

public protocol KvUrlQueryItemGroupOfNineProtocol : KvUrlQueryItemGroup
where Value == (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value, G7.Value, G8.Value)
{

    associatedtype G0 : KvUrlQueryItemGroup
    associatedtype G1 : KvUrlQueryItemGroup
    associatedtype G2 : KvUrlQueryItemGroup
    associatedtype G3 : KvUrlQueryItemGroup
    associatedtype G4 : KvUrlQueryItemGroup
    associatedtype G5 : KvUrlQueryItemGroup
    associatedtype G6 : KvUrlQueryItemGroup
    associatedtype G7 : KvUrlQueryItemGroup
    associatedtype G8 : KvUrlQueryItemGroup

    typealias Ammended<T> = KvUrlQueryItemGroupOfTen<G0, G1, G2, G3, G4, G5, G6, G7, G8, KvUrlQueryItemGroupOfOne<T>>
    typealias Mapped<T> = KvUrlQueryItemGroupMap<Self, T>

    func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T>

}

extension KvUrlQueryItemGroupOfNineProtocol {

    @inlinable
    public func map<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value, G7.Value, G8.Value) -> T) -> Mapped<T> { .init(self, transform: transform) }


    @inlinable
    public func flatMap<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value, G7.Value, G8.Value) -> KvUrlQueryParseResult<T>) -> Mapped<T> { .init(self, transform: transform) }

}


public struct KvUrlQueryItemGroupOfNine<G0, G1, G2, G3, G4, G5, G6, G7, G8> : KvUrlQueryItemGroupOfNineProtocol
where G0 : KvUrlQueryItemGroup, G1 : KvUrlQueryItemGroup, G2 : KvUrlQueryItemGroup, G3 : KvUrlQueryItemGroup, G4 : KvUrlQueryItemGroup,
      G5 : KvUrlQueryItemGroup, G6 : KvUrlQueryItemGroup, G7 : KvUrlQueryItemGroup, G8 : KvUrlQueryItemGroup
{

    @usableFromInline let g0: G0
    @usableFromInline let g1: G1
    @usableFromInline let g2: G2
    @usableFromInline let g3: G3
    @usableFromInline let g4: G4
    @usableFromInline let g5: G5
    @usableFromInline let g6: G6
    @usableFromInline let g7: G7
    @usableFromInline let g8: G8


    @inlinable
    public init(_ g0: G0, _ g1: G1, _ g2: G2, _ g3: G3, _ g4: G4, _ g5: G5, _ g6: G6, _ g7: G7, _ g8: G8) {
        (self.g0, self.g1, self.g2, self.g3, self.g4, self.g5, self.g6, self.g7, self.g8) = (g0, g1, g2, g3, g4, g5, g6, g7, g8)
    }


    @inlinable
    public func ammended<T>(_ item: KvUrlQueryItem<T>) -> Ammended<T> { .init(g0, g1, g2, g3, g4, g5, g6, g7, g8, .init(item)) }

}



// MARK: - KvUrlQueryItemGroupOfTen

public protocol KvUrlQueryItemGroupOfTenProtocol : KvUrlQueryItemGroup
where Value == (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value, G7.Value, G8.Value, G9.Value)
{

    associatedtype G0 : KvUrlQueryItemGroup
    associatedtype G1 : KvUrlQueryItemGroup
    associatedtype G2 : KvUrlQueryItemGroup
    associatedtype G3 : KvUrlQueryItemGroup
    associatedtype G4 : KvUrlQueryItemGroup
    associatedtype G5 : KvUrlQueryItemGroup
    associatedtype G6 : KvUrlQueryItemGroup
    associatedtype G7 : KvUrlQueryItemGroup
    associatedtype G8 : KvUrlQueryItemGroup
    associatedtype G9 : KvUrlQueryItemGroup

    typealias Mapped<T> = KvUrlQueryItemGroupMap<Self, T>

}


extension KvUrlQueryItemGroupOfTenProtocol {

    @inlinable
    public func map<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value, G7.Value, G8.Value, G9.Value) -> T) -> Mapped<T> { .init(self, transform: transform) }


    @inlinable
    public func flatMap<T>(_ transform: @escaping (G0.Value, G1.Value, G2.Value, G3.Value, G4.Value, G5.Value, G6.Value, G7.Value, G8.Value, G9.Value) -> KvUrlQueryParseResult<T>) -> Mapped<T> { .init(self, transform: transform) }

}


public struct KvUrlQueryItemGroupOfTen<G0, G1, G2, G3, G4, G5, G6, G7, G8, G9> : KvUrlQueryItemGroupOfTenProtocol
where G0 : KvUrlQueryItemGroup, G1 : KvUrlQueryItemGroup, G2 : KvUrlQueryItemGroup, G3 : KvUrlQueryItemGroup, G4 : KvUrlQueryItemGroup,
      G5 : KvUrlQueryItemGroup, G6 : KvUrlQueryItemGroup, G7 : KvUrlQueryItemGroup, G8 : KvUrlQueryItemGroup, G9 : KvUrlQueryItemGroup
{

    @usableFromInline let g0: G0
    @usableFromInline let g1: G1
    @usableFromInline let g2: G2
    @usableFromInline let g3: G3
    @usableFromInline let g4: G4
    @usableFromInline let g5: G5
    @usableFromInline let g6: G6
    @usableFromInline let g7: G7
    @usableFromInline let g8: G8
    @usableFromInline let g9: G9


    @inlinable
    public init(_ g0: G0, _ g1: G1, _ g2: G2, _ g3: G3, _ g4: G4, _ g5: G5, _ g6: G6, _ g7: G7, _ g8: G8, _ g9: G9) {
        (self.g0, self.g1, self.g2, self.g3, self.g4, self.g5, self.g6, self.g7, self.g8, self.g9) = (g0, g1, g2, g3, g4, g5, g6, g7, g8, g9)
    }

}
