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
//  KvUrlQueryParser.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 19.06.2023.
//

import Foundation

import kvKit



// MARK: - KvUrlQueryParserProtocol

/// Base protocol for URL query parsers.
protocol KvUrlQueryParserProtocol {

    typealias Status = KvUrlQueryParserStatus


    var status: Status { get }


    func reset()

}



// MARK: - KvUrlQuerySerialParser

/// Protocol for parsers processing URL query serially item by item.
protocol KvSerialUrlQueryParser : KvUrlQueryParserProtocol {

    /// - Returns: Status of the receiver at the moment the method returns.
    func parse(_ urlQueryItem: KvHttpResponse.RawUrlQuery.Element) -> Status

}



// MARK: - KvUrlQuerySerialParser

/// Protocol for parsers processing entire URL query at once.
protocol KvEntireUrlQueryParser : KvUrlQueryParserProtocol {

    /// - Returns: Status of the receiver at the moment the method returns.
    func parse(_ urlQuery: KvHttpResponse.RawUrlQuery?) -> Status

}



// MARK: - KvUrlQueryParserStatus

enum KvUrlQueryParserStatus : Equatable {

    /// Parser is waiting for required URL query items.
    case incomplete
    /// Parser has successfully processed all required URL query items and hasn't got unexpeted items.
    case complete
    /// Some URL query item has been processed with error.
    case failure

}



// MARK: - KvUrlQueryParseResult

/// Represents cases of URL query parsing and validation result.
public enum KvUrlQueryParseResult<Wrapped> {
    case success(Wrapped)
    case failure
}


extension KvUrlQueryParseResult {

    @inlinable
    public init(catching throwingBlock: () throws -> Wrapped) {
        do { self = .success(try throwingBlock()) }
        catch { self = .failure }
    }


    @inlinable
    public func map<R>(_ transform: (Wrapped) -> R) -> KvUrlQueryParseResult<R> {
        switch self {
        case .success(let value):
            return .success(transform(value))
        case .failure:
            return .failure
        }
    }


    @inlinable
    public func flatMap<R>(_ transform: (Wrapped) -> KvUrlQueryParseResult<R>) -> KvUrlQueryParseResult<R> {
        switch self {
        case .success(let value):
            return transform(value)
        case .failure:
            return .failure
        }
    }

}



// MARK: - KvUrlQueryParseResultProvider

protocol KvUrlQueryParseResultProvider {

    associatedtype Value


    func parseResult() -> KvUrlQueryParseResult<Value>

}



// MARK: - KvEmptyUrlQueryParser

class KvEmptyUrlQueryParser : KvSerialUrlQueryParser, KvUrlQueryParseResultProvider {

    typealias Value = Void


    private(set) var status: Status = .complete


    // MARK: Operations

    func reset() {
        status = .complete
    }


    func parse(_ urlQueryItem: KvHttpResponse.RawUrlQuery.Element) -> Status {
        status = .failure
        return status
    }


    func parseResult() -> KvUrlQueryParseResult<Value> {
        switch status {
        case .complete:
            return .success(())
        case .failure, .incomplete:
            return .failure
        }
    }

}



// MARK: - KvRawUrlQueryParser

class KvRawUrlQueryParser<Value> : KvEntireUrlQueryParser, KvUrlQueryParseResultProvider {

    private(set) var status: Status = .incomplete


    init<G>(for item: G) where G : KvRawUrlQueryItemGroupProtocol, G.Value == Value {
        transform = item.transform
    }


    private let transform: KvRawUrlQueryItemGroup<Value>.Transform
    private var value: Value?


    // MARK: : KvUrlQueryParserProtocol

    func reset() {
        status = .incomplete
        value = nil
    }


    func parse(_ urlQuery: KvHttpResponse.RawUrlQuery?) -> Status {
        switch status {
        case .incomplete:
            switch transform(urlQuery) {
            case .success(let value):
                self.value = value
                status = .complete
            case .failure:
                status = .failure
            }

        case .complete:
            #if DEBUG
            KvDebug.pause("Warning: attempt to parse an URL query when raw parser is in `.complete` status")
            #endif
            break

        case .failure:
            break
        }

        return status
    }


    // MARK: : KvUrlQueryParseResultProvider

    func parseResult() -> KvUrlQueryParseResult<Value> {
        switch status {
        case .complete:
            guard let value = value else { return .failure }
            return .success(value)
        case .failure, .incomplete:
            return .failure
        }
    }

}


// MARK: - KvUrlQueryParser

class KvUrlQueryParser<Value> : KvSerialUrlQueryParser, KvUrlQueryParseResultProvider {

    private(set) var status: Status = .incomplete


    init<ItemGroup>(for itemGroup: ItemGroup)
    where ItemGroup : KvUrlQueryItemGroup & KvUrlQueryItemImplementationProvider, ItemGroup.Value == Value
    {
        var numberOfRequiredValues = 0
        var itemParsers: [String : KvUrlQueryValueParserInternalProtocol] = .init()

        valueContainer = itemGroup.makeImplementation({ name, parser in
            let parser = parser as! any KvUrlQueryValueParserInternalProtocol

            numberOfRequiredValues += parser.isRequired ? 1 : 0

            if let oldValue = itemParsers.updateValue(parser, forKey: name) {
                assertionFailure("Warninig: value parser for URL query item named \"\(name)\" has been replaced")

                numberOfRequiredValues -= oldValue.isRequired ? 1 : 0
            }
        })

        assert(numberOfRequiredValues == itemParsers.values.reduce(0, { $0 + ($1.isRequired ? 1 : 0) }))

        self.itemParsers = itemParsers
        self.numberOfRequiredValues = numberOfRequiredValues
        numberOfMissingRequiredValues = numberOfRequiredValues
    }


    private let itemParsers: [String : KvUrlQueryValueParserInternalProtocol]
    private let valueContainer: KvUrlQueryValueContainer<Value>

    private let numberOfRequiredValues: Int
    private var numberOfMissingRequiredValues: Int


    // MARK: : KvUrlQueryParserProtocol

    func reset() {
        status = numberOfRequiredValues > 0 ? .incomplete : .complete

        itemParsers.values.forEach { $0.reset() }

        numberOfMissingRequiredValues = numberOfRequiredValues
    }


    func parse(_ urlQueryItem: KvHttpResponse.RawUrlQuery.Element) -> Status {

        func WhenParserSucceeded(_ body: (KvUrlQueryValueParserInternalProtocol) -> Void) {
            guard let itemParser = itemParsers[urlQueryItem.name] else {
                status = .failure
                return
            }

            switch itemParser.parse(urlQueryItem.value) {
            case .success:
                body(itemParser)

            case .alreadyDone:
                break

            case .failure:
                status = .failure
            }
        }


        switch status {
        case .incomplete:
            WhenParserSucceeded { itemParser in
                guard itemParser.isRequired else { return }

                numberOfMissingRequiredValues -= 1
                assert(numberOfMissingRequiredValues >= 0)

                guard numberOfMissingRequiredValues == 0 else { return }

                status = .complete
            }

        case .complete:
            WhenParserSucceeded { itemParser in
                assert(!itemParser.isRequired)
                assert(numberOfMissingRequiredValues == 0)
            }

        case .failure:
            break
        }

        return status
    }


    // MARK: : KvUrlQueryParseResultProvider

    func parseResult() -> KvUrlQueryParseResult<Value> {
        switch status {
        case .complete:
            return valueContainer.valueBlock() ?? .failure
        case .failure, .incomplete:
            return .failure
        }
    }

}



// MARK: - KvUrlQueryValueParserProtocol

// TODO: Make it fileprivate or internal
/// - Note: It's constrained to `AnyObject` to disable copy by value.
public protocol KvUrlQueryValueParserProtocol : AnyObject { }



// MARK: - KvUrlQueryValueParserInternalProtocol

fileprivate protocol KvUrlQueryValueParserInternalProtocol : KvUrlQueryValueParserProtocol {

    typealias ParseResult = KvUrlQueryValueParseResult


    var isRequired: Bool { get }


    func reset()

    func parse(_ rawValue: String?) -> ParseResult

}



// MARK: - KvUrlQueryValueParseResult

// TODO: Make it fileprivate or internal
public enum KvUrlQueryValueParseResult {

    case success
    case alreadyDone
    case failure

}



// MARK: - KvUrlQueryValueParser

// TODO: Make it fileprivate or internal
public class KvUrlQueryValueParser<Value> : KvUrlQueryValueParserInternalProtocol {

    fileprivate var isRequired: Bool { defaultBlock == nil }


    fileprivate init(for queryItem: KvUrlQueryItem<Value>) {
        defaultBlock = queryItem.defaultBlock
        parseBlock = queryItem.parseBlock
    }


    private var value: KvUrlQueryParseResult<Value>?

    private let defaultBlock: (() -> Value)?

    private let parseBlock: (String?) -> KvUrlQueryParseResult<Value>


    // MARK: Operations

    /// - Note: Nil means missing required value.
    fileprivate func result() -> KvUrlQueryParseResult<Value>? { value ?? defaultBlock.map { block in .success(block()) } }


    fileprivate func reset() {
        value = nil
    }


    fileprivate func parse(_ rawValue: String?) -> ParseResult {
        switch value {
        case .none:
            switch parseBlock(rawValue) {
            case .success(let value):
                self.value = .success(value)
                return .success

            case .failure:
                self.value = .failure
                return .failure
            }

        case .some:
            return .alreadyDone
        }
    }

}



// MARK: - KvUrlQueryValueContainer

// TODO: Make it fileprivate or internal
public struct KvUrlQueryValueContainer<Value> {

    /// - Note: Nil means missing required value.
    fileprivate typealias ValueBlock = () -> KvUrlQueryParseResult<Value>?

    /// It's invoked with name of URL query item and the item's value parser.
    fileprivate typealias ParserCallback = (String, KvUrlQueryValueParserInternalProtocol) -> Void


    fileprivate let valueBlock: ValueBlock


    fileprivate init(_ valueBlock: @escaping ValueBlock) {
        self.valueBlock = valueBlock
    }

}



// MARK: - KvUrlQueryValueKit

fileprivate struct KvUrlQueryValueKit {

    typealias ParseResult<T> = KvUrlQueryParseResult<T>


    private init() { }


    @inline(__always)
    static func flatMap<V0, T>(_ r0: ParseResult<V0>?, transform: (V0) -> ParseResult<T>?) -> ParseResult<T>? {
        switch r0 {
        case .success(let v0):
            return transform(v0)
        case .failure:
            return .failure
        case .none:
            return nil
        }
    }


    @inline(__always)
    static func flatMap<V0, V1, T>(
        _ r0: ParseResult<V0>?, _ r1: ParseResult<V1>?,
        transform: (V0, V1) -> ParseResult<T>?
    ) -> ParseResult<T>?
    {
        flatMap(r1) { v in
            flatMap(r0) { transform($0, v) }
        }
    }


    @inline(__always)
    static func flatMap<V0, V1, V2, T>(
        _ r0: ParseResult<V0>?, _ r1: ParseResult<V1>?, _ r2: ParseResult<V2>?,
        transform: (V0, V1, V2) -> ParseResult<T>?
    ) -> ParseResult<T>?
    {
        flatMap(r2) { v in
            flatMap(r0, r1) { transform($0, $1, v) }
        }
    }


    @inline(__always)
    static func flatMap<V0, V1, V2, V3, T>(
        _ r0: ParseResult<V0>?, _ r1: ParseResult<V1>?, _ r2: ParseResult<V2>?, _ r3: ParseResult<V3>?,
        transform: (V0, V1, V2, V3) -> ParseResult<T>?
    ) -> ParseResult<T>?
    {
        flatMap(r3) { v in
            flatMap(r0, r1, r2) { transform($0, $1, $2, v) }
        }
    }


    @inline(__always)
    static func flatMap<V0, V1, V2, V3, V4, T>(
        _ r0: ParseResult<V0>?, _ r1: ParseResult<V1>?, _ r2: ParseResult<V2>?, _ r3: ParseResult<V3>?, _ r4: ParseResult<V4>?,
        transform: (V0, V1, V2, V3, V4) -> ParseResult<T>?
    ) -> ParseResult<T>?
    {
        flatMap(r4) { v in
            flatMap(r0, r1, r2, r3) { transform($0, $1, $2, $3, v) }
        }
    }


    @inline(__always)
    static func flatMap<V0, V1, V2, V3, V4, V5, T>(
        _ r0: ParseResult<V0>?, _ r1: ParseResult<V1>?, _ r2: ParseResult<V2>?, _ r3: ParseResult<V3>?, _ r4: ParseResult<V4>?,
        _ r5: ParseResult<V5>?,
        transform: (V0, V1, V2, V3, V4, V5) -> ParseResult<T>?
    ) -> ParseResult<T>?
    {
        flatMap(r5) { v in
            flatMap(r0, r1, r2, r3, r4) { transform($0, $1, $2, $3, $4, v) }
        }
    }


    @inline(__always)
    static func flatMap<V0, V1, V2, V3, V4, V5, V6, T>(
        _ r0: ParseResult<V0>?, _ r1: ParseResult<V1>?, _ r2: ParseResult<V2>?, _ r3: ParseResult<V3>?, _ r4: ParseResult<V4>?,
        _ r5: ParseResult<V5>?, _ r6: ParseResult<V6>?,
        transform: (V0, V1, V2, V3, V4, V5, V6) -> ParseResult<T>?
    ) -> ParseResult<T>?
    {
        flatMap(r6) { v in
            flatMap(r0, r1, r2, r3, r4, r5) { transform($0, $1, $2, $3, $4, $5, v) }
        }
    }


    @inline(__always)
    static func flatMap<V0, V1, V2, V3, V4, V5, V6, V7, T>(
        _ r0: ParseResult<V0>?, _ r1: ParseResult<V1>?, _ r2: ParseResult<V2>?, _ r3: ParseResult<V3>?, _ r4: ParseResult<V4>?,
        _ r5: ParseResult<V5>?, _ r6: ParseResult<V6>?, _ r7: ParseResult<V7>?,
        transform: (V0, V1, V2, V3, V4, V5, V6, V7) -> ParseResult<T>?
    ) -> ParseResult<T>?
    {
        flatMap(r7) { v in
            flatMap(r0, r1, r2, r3, r4, r5, r6) { transform($0, $1, $2, $3, $4, $5, $6, v) }
        }
    }


    @inline(__always)
    static func flatMap<V0, V1, V2, V3, V4, V5, V6, V7, V8, T>(
        _ r0: ParseResult<V0>?, _ r1: ParseResult<V1>?, _ r2: ParseResult<V2>?, _ r3: ParseResult<V3>?, _ r4: ParseResult<V4>?,
        _ r5: ParseResult<V5>?, _ r6: ParseResult<V6>?, _ r7: ParseResult<V7>?, _ r8: ParseResult<V8>?,
        transform: (V0, V1, V2, V3, V4, V5, V6, V7, V8) -> ParseResult<T>?
    ) -> ParseResult<T>?
    {
        flatMap(r8) { v in
            flatMap(r0, r1, r2, r3, r4, r5, r6, r7) { transform($0, $1, $2, $3, $4, $5, $6, $7, v) }
        }
    }


    @inline(__always)
    static func flatMap<V0, V1, V2, V3, V4, V5, V6, V7, V8, V9, T>(
        _ r0: ParseResult<V0>?, _ r1: ParseResult<V1>?, _ r2: ParseResult<V2>?, _ r3: ParseResult<V3>?, _ r4: ParseResult<V4>?,
        _ r5: ParseResult<V5>?, _ r6: ParseResult<V6>?, _ r7: ParseResult<V7>?, _ r8: ParseResult<V8>?, _ r9: ParseResult<V9>?,
        transform: (V0, V1, V2, V3, V4, V5, V6, V7, V8, V9) -> ParseResult<T>?
    ) -> ParseResult<T>?
    {
        flatMap(r9) { v in
            flatMap(r0, r1, r2, r3, r4, r5, r6, r7, r8) { transform($0, $1, $2, $3, $4, $5, $6, $7, $8, v) }
        }
    }

}



// MARK: - KvUrlQueryItemImplementationProvider

// TODO: Make it fileprivate or internal
public protocol KvUrlQueryItemImplementationProvider {

    associatedtype Value

    typealias ParserCallback = (String, KvUrlQueryValueParserProtocol) -> Void

    func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value>

}



// MARK: - KvUrlQueryItemGroupMap

extension KvUrlQueryItemGroupMap : KvUrlQueryItemImplementationProvider where Source : KvUrlQueryItemImplementationProvider {

    public func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value> {
        let c = source.makeImplementation(parserCallback)

        return .init {
            c.valueBlock()?.flatMap(transform)
        }
    }

}



// MARK: - KvUrlQueryItemGroupOfOne

extension KvUrlQueryItemGroupOfOne : KvUrlQueryItemImplementationProvider {

    public func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value> {
        let parser = KvUrlQueryValueParser(for: item)

        parserCallback(item.name, parser)

        return .init {
            parser.result()
        }
    }

}



// MARK: - KvUrlQueryItemGroupOfTwo

extension KvUrlQueryItemGroupOfTwo : KvUrlQueryItemImplementationProvider
where G0 : KvUrlQueryItemImplementationProvider, G1 : KvUrlQueryItemImplementationProvider
{

    public func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value> {
        let c0 = g0.makeImplementation(parserCallback)
        let c1 = g1.makeImplementation(parserCallback)

        return .init {
            KvUrlQueryValueKit.flatMap(c0.valueBlock(), c1.valueBlock(),
                                       transform: { .success(($0, $1)) })
        }
    }

}



// MARK: - KvUrlQueryItemGroupOfThree

extension KvUrlQueryItemGroupOfThree : KvUrlQueryItemImplementationProvider
where G0 : KvUrlQueryItemImplementationProvider, G1 : KvUrlQueryItemImplementationProvider, G2 : KvUrlQueryItemImplementationProvider
{

    public func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value> {
        let c0 = g0.makeImplementation(parserCallback)
        let c1 = g1.makeImplementation(parserCallback)
        let c2 = g2.makeImplementation(parserCallback)

        return .init {
            KvUrlQueryValueKit.flatMap(c0.valueBlock(), c1.valueBlock(), c2.valueBlock(),
                                       transform: { .success(($0, $1, $2)) })
        }
    }

}



// MARK: - KvUrlQueryItemGroupOfFour

extension KvUrlQueryItemGroupOfFour : KvUrlQueryItemImplementationProvider
where G0 : KvUrlQueryItemImplementationProvider, G1 : KvUrlQueryItemImplementationProvider, G2 : KvUrlQueryItemImplementationProvider,
      G3 : KvUrlQueryItemImplementationProvider
{

    public func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value> {
        let c0 = g0.makeImplementation(parserCallback)
        let c1 = g1.makeImplementation(parserCallback)
        let c2 = g2.makeImplementation(parserCallback)
        let c3 = g3.makeImplementation(parserCallback)

        return .init {
            KvUrlQueryValueKit.flatMap(c0.valueBlock(), c1.valueBlock(), c2.valueBlock(), c3.valueBlock(),
                                       transform: { .success(($0, $1, $2, $3)) })
        }
    }

}



// MARK: - KvUrlQueryItemGroupOfFive

extension KvUrlQueryItemGroupOfFive : KvUrlQueryItemImplementationProvider
where G0 : KvUrlQueryItemImplementationProvider, G1 : KvUrlQueryItemImplementationProvider, G2 : KvUrlQueryItemImplementationProvider,
      G3 : KvUrlQueryItemImplementationProvider, G4 : KvUrlQueryItemImplementationProvider
{

    public func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value> {
        let c0 = g0.makeImplementation(parserCallback)
        let c1 = g1.makeImplementation(parserCallback)
        let c2 = g2.makeImplementation(parserCallback)
        let c3 = g3.makeImplementation(parserCallback)
        let c4 = g4.makeImplementation(parserCallback)

        return .init {
            KvUrlQueryValueKit.flatMap(c0.valueBlock(), c1.valueBlock(), c2.valueBlock(), c3.valueBlock(), c4.valueBlock(),
                                       transform: { .success(($0, $1, $2, $3, $4)) })
        }
    }

}



// MARK: - KvUrlQueryItemGroupOfSix

extension KvUrlQueryItemGroupOfSix : KvUrlQueryItemImplementationProvider
where G0 : KvUrlQueryItemImplementationProvider, G1 : KvUrlQueryItemImplementationProvider, G2 : KvUrlQueryItemImplementationProvider,
      G3 : KvUrlQueryItemImplementationProvider, G4 : KvUrlQueryItemImplementationProvider, G5 : KvUrlQueryItemImplementationProvider
{

    public func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value> {
        let c0 = g0.makeImplementation(parserCallback)
        let c1 = g1.makeImplementation(parserCallback)
        let c2 = g2.makeImplementation(parserCallback)
        let c3 = g3.makeImplementation(parserCallback)
        let c4 = g4.makeImplementation(parserCallback)
        let c5 = g5.makeImplementation(parserCallback)

        return .init {
            KvUrlQueryValueKit.flatMap(c0.valueBlock(), c1.valueBlock(), c2.valueBlock(), c3.valueBlock(), c4.valueBlock(),
                                       c5.valueBlock(),
                                       transform: { .success(($0, $1, $2, $3, $4, $5)) })
        }
    }

}



// MARK: - KvUrlQueryItemGroupOfSeven

extension KvUrlQueryItemGroupOfSeven : KvUrlQueryItemImplementationProvider
where G0 : KvUrlQueryItemImplementationProvider, G1 : KvUrlQueryItemImplementationProvider, G2 : KvUrlQueryItemImplementationProvider,
      G3 : KvUrlQueryItemImplementationProvider, G4 : KvUrlQueryItemImplementationProvider, G5 : KvUrlQueryItemImplementationProvider,
      G6 : KvUrlQueryItemImplementationProvider
{

    public func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value> {
        let c0 = g0.makeImplementation(parserCallback)
        let c1 = g1.makeImplementation(parserCallback)
        let c2 = g2.makeImplementation(parserCallback)
        let c3 = g3.makeImplementation(parserCallback)
        let c4 = g4.makeImplementation(parserCallback)
        let c5 = g5.makeImplementation(parserCallback)
        let c6 = g6.makeImplementation(parserCallback)

        return .init {
            KvUrlQueryValueKit.flatMap(c0.valueBlock(), c1.valueBlock(), c2.valueBlock(), c3.valueBlock(), c4.valueBlock(),
                                       c5.valueBlock(), c6.valueBlock(),
                                       transform: { .success(($0, $1, $2, $3, $4, $5, $6)) })
        }
    }

}



// MARK: - KvUrlQueryItemGroupOfEight

extension KvUrlQueryItemGroupOfEight : KvUrlQueryItemImplementationProvider
where G0 : KvUrlQueryItemImplementationProvider, G1 : KvUrlQueryItemImplementationProvider, G2 : KvUrlQueryItemImplementationProvider,
      G3 : KvUrlQueryItemImplementationProvider, G4 : KvUrlQueryItemImplementationProvider, G5 : KvUrlQueryItemImplementationProvider,
      G6 : KvUrlQueryItemImplementationProvider, G7 : KvUrlQueryItemImplementationProvider
{

    public func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value> {
        let c0 = g0.makeImplementation(parserCallback)
        let c1 = g1.makeImplementation(parserCallback)
        let c2 = g2.makeImplementation(parserCallback)
        let c3 = g3.makeImplementation(parserCallback)
        let c4 = g4.makeImplementation(parserCallback)
        let c5 = g5.makeImplementation(parserCallback)
        let c6 = g6.makeImplementation(parserCallback)
        let c7 = g7.makeImplementation(parserCallback)

        return .init {
            KvUrlQueryValueKit.flatMap(c0.valueBlock(), c1.valueBlock(), c2.valueBlock(), c3.valueBlock(), c4.valueBlock(),
                                       c5.valueBlock(), c6.valueBlock(), c7.valueBlock(),
                                       transform: { .success(($0, $1, $2, $3, $4, $5, $6, $7)) })
        }
    }

}



// MARK: - KvUrlQueryItemGroupOfNine

extension KvUrlQueryItemGroupOfNine : KvUrlQueryItemImplementationProvider
where G0 : KvUrlQueryItemImplementationProvider, G1 : KvUrlQueryItemImplementationProvider, G2 : KvUrlQueryItemImplementationProvider,
      G3 : KvUrlQueryItemImplementationProvider, G4 : KvUrlQueryItemImplementationProvider, G5 : KvUrlQueryItemImplementationProvider,
      G6 : KvUrlQueryItemImplementationProvider, G7 : KvUrlQueryItemImplementationProvider, G8 : KvUrlQueryItemImplementationProvider
{

    public func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value> {
        let c0 = g0.makeImplementation(parserCallback)
        let c1 = g1.makeImplementation(parserCallback)
        let c2 = g2.makeImplementation(parserCallback)
        let c3 = g3.makeImplementation(parserCallback)
        let c4 = g4.makeImplementation(parserCallback)
        let c5 = g5.makeImplementation(parserCallback)
        let c6 = g6.makeImplementation(parserCallback)
        let c7 = g7.makeImplementation(parserCallback)
        let c8 = g8.makeImplementation(parserCallback)

        return .init {
            KvUrlQueryValueKit.flatMap(c0.valueBlock(), c1.valueBlock(), c2.valueBlock(), c3.valueBlock(), c4.valueBlock(),
                                       c5.valueBlock(), c6.valueBlock(), c7.valueBlock(), c8.valueBlock(),
                                       transform: { .success(($0, $1, $2, $3, $4, $5, $6, $7, $8)) })
        }
    }

}



// MARK: - KvUrlQueryItemGroupOfTen

extension KvUrlQueryItemGroupOfTen : KvUrlQueryItemImplementationProvider
where G0 : KvUrlQueryItemImplementationProvider, G1 : KvUrlQueryItemImplementationProvider, G2 : KvUrlQueryItemImplementationProvider,
      G3 : KvUrlQueryItemImplementationProvider, G4 : KvUrlQueryItemImplementationProvider, G5 : KvUrlQueryItemImplementationProvider,
      G6 : KvUrlQueryItemImplementationProvider, G7 : KvUrlQueryItemImplementationProvider, G8 : KvUrlQueryItemImplementationProvider,
      G9 : KvUrlQueryItemImplementationProvider
{

    public func makeImplementation(_ parserCallback: ParserCallback) -> KvUrlQueryValueContainer<Value> {
        let c0 = g0.makeImplementation(parserCallback)
        let c1 = g1.makeImplementation(parserCallback)
        let c2 = g2.makeImplementation(parserCallback)
        let c3 = g3.makeImplementation(parserCallback)
        let c4 = g4.makeImplementation(parserCallback)
        let c5 = g5.makeImplementation(parserCallback)
        let c6 = g6.makeImplementation(parserCallback)
        let c7 = g7.makeImplementation(parserCallback)
        let c8 = g8.makeImplementation(parserCallback)
        let c9 = g9.makeImplementation(parserCallback)

        return .init {
            KvUrlQueryValueKit.flatMap(c0.valueBlock(), c1.valueBlock(), c2.valueBlock(), c3.valueBlock(), c4.valueBlock(),
                                       c5.valueBlock(), c6.valueBlock(), c7.valueBlock(), c8.valueBlock(), c9.valueBlock(),
                                       transform: { .success(($0, $1, $2, $3, $4, $5, $6, $7, $8, $9)) })
        }
    }

}
