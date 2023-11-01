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
//  KvUrlPath.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 29.10.2023.
//

import Foundation

import kvKit



// MARK: - KvUrlPathProtocol

/// A protocol for typea representing a path as collection of path components.
public protocol KvUrlPathProtocol : Hashable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation, ExpressibleByArrayLiteral {

    associatedtype Components : RandomAccessCollection where Components.Element == Substring

    associatedtype SubSequence : KvUrlPathProtocol


    var components: Components { get }

    var isEmpty: Bool { get }
    var joined: String { get }

    var standardized: Self { get }
    var joinedStandardized: String { get }


    init()

    init(with components: [Substring])
    init<C>(with components: C) where C : Sequence, C.Element == Substring
    init<C>(with components: C) where C : Sequence, C.Element : StringProtocol

    init(path: String)

    init<S>(path: S) where S : StringProtocol


    subscript(index: Components.Index) -> Substring { get }

    subscript<R>(range: R) -> SubSequence where R : RangeExpression, R.Bound == Components.Index { get }


    func starts<P>(with prefix: P) -> Bool where P : KvUrlPathProtocol

    func prefix(_ maxLength: Int) -> SubSequence
    func prefix(while predicate: (Substring) throws -> Bool) rethrows -> SubSequence
    func prefix(upTo end: Components.Index) -> SubSequence
    func prefix(through position: Components.Index) -> SubSequence

    func dropFirst(_ count: Int) -> SubSequence


    static func +(lhs: Self, rhs: Self) -> KvUrlPath
    static func +<P>(lhs: Self, rhs: P) -> KvUrlPath where P : KvUrlPathProtocol

}


extension KvUrlPathProtocol {

    // MARK: Subscripts

    /// - Returns: Path component at given *index*.
    @inlinable
    public subscript(index: Components.Index) -> Components.Element { components[index] }



    // MARK: Operations

    /// A boolean value indicating whether the receiver is empty.
    @inlinable
    public var isEmpty: Bool { components.isEmpty }

    /// The receiver's *components* joined with standard path separator.
    @inlinable
    public var joined: String { components.joined(separator: .init(KvUrlPath.separator)) }

}



// MARK: - KvUrlPath

/// A type representing a path as collection of path components.
public struct KvUrlPath : KvUrlPathProtocol, ExpressibleByStringLiteral, ExpressibleByArrayLiteral {

    public static var separator: Character { "/" }



    /// Path components without path separators.
    public var components: [Substring] { _components }


    @usableFromInline
    var _components: [Substring]



    /// Initializes empty instance.
    ///
    /// - Tip: Consider ``empty-swift.type.property``.
    @inlinable
    public init() { _components = [ ] }


    /// Initializes an instance from arbitrary *path*.
    @inlinable
    public init<P>(_ path: P) where P : KvUrlPathProtocol { _components = Array(path.components) }


    /// - Parameter safeComponents: Array of components guaranteed to be valid.
    @usableFromInline
    init(safeComponents: [Substring]) { self._components = safeComponents }


    /// - Parameter safeComponents: Sequence of components guaranteed to be valid.
    @usableFromInline
    init<C>(safeComponents: C) where C : Sequence, C.Element == Substring
    { self._components = Array(safeComponents) }


    /// - Parameter safeComponents: Collection of components guaranteed to be valid.
    @usableFromInline
    init<C>(safeComponents: C) where C : Collection, C.Element : StringProtocol
    { self._components = safeComponents.map { .init($0) } }


    /// Splits any of *components* containing path separators. The resulting components are used to initialize an instance.
    @inlinable
    public init(with components: [Substring]) {
        var iterator = components.enumerated().makeIterator()

        // - NOTE: Algorithm below creates copy only when there is a component containing a path separator.

        while let (offset, component) = iterator.next() {
            if let separatorIndex = component.firstIndex(of: KvUrlPath.separator) {
                var safeComponents = Array(components.prefix(offset))

                func Append(_ component: Substring) {
                    safeComponents.append(contentsOf: component[separatorIndex...]
                        .split(separator: KvUrlPath.separator, omittingEmptySubsequences: true))
                }

                safeComponents.append(.init(component.prefix(upTo: separatorIndex)))
                Append(component[separatorIndex...])

                while let (_, component) = iterator.next() {
                    Append(component)
                }

                self.init(safeComponents: .init(safeComponents))
                return
            }
        }

        self.init(safeComponents: components)
    }


    /// Splits any of *components* containing path separators. The resulting components are used to initialize an instance.
    @inlinable
    public init<C>(with components: C) where C : Sequence, C.Element == Substring {

        // - NOTE: Algorithm below creates new collection anyway due to generic sequence is not an array.

        self.init(safeComponents: components.flatMap {
            $0.split(separator: KvUrlPath.separator, omittingEmptySubsequences: true)
        })
    }


    /// Splits any of *components* containing path separators. The resulting components are used to initialize an instance.
    @inlinable
    public init<C>(with components: C) where C : Sequence, C.Element : StringProtocol {

        // - NOTE: Algorithm below creates new collection anyway due to generic sequence is not an array.

        self.init(safeComponents: components.flatMap {
            $0.split(separator: KvUrlPath.separator, omittingEmptySubsequences: true)
        })
    }


    /// Splits given *path* to path components and initializes an instance with the result.
    @inlinable
    public init(path: String) { self.init(safeComponents: path.split(separator: KvUrlPath.separator, omittingEmptySubsequences: true)) }


    /// Splits given *path* to path components and initializes an instance with the result.
    @inlinable
    public init<S>(path: S) where S : StringProtocol { self.init(safeComponents: path.split(separator: KvUrlPath.separator, omittingEmptySubsequences: true)) }



    // MARK: Fabrics

    /// A shared empty instance.
    public static let empty: Self = .init(safeComponents: [ ])



    // MARK: : ExpressibleByStringLiteral

    /// Initializes from path as a astring literal.
    @inlinable
    public init(stringLiteral value: StringLiteralType) { self.init(path: value) }



    // MARK: : ExpressibleByArrayLiteral

    /// Processes elements of given array literal and initializes an instance with the resulting components.
    @inlinable
    public init(arrayLiteral elements: Substring...) { self.init(with: elements) }



    // MARK: Subscripts

    /// - Returns: Slice of the receiver matching given index *range*.
    @inlinable
    public subscript<R>(range: R) -> SubSequence
    where R : RangeExpression, R.Bound == Components.Index
    {
        SubSequence(safeComponents: components[range])
    }



    // MARK: Mutation

    /// Appends given path to the receiver.
    @inlinable
    public mutating func append(_ rhs: KvUrlPath) { _components.append(contentsOf: rhs._components) }


    /// Appends given path to the receiver.
    @inlinable
    public mutating func append<P>(_ rhs: P) where P : KvUrlPathProtocol { _components.append(contentsOf: rhs.components) }



    // MARK: Operations

    /// A copy where occurrences of "." and ".." special components are resolved.
    /// If there is no "." and ".." special components then the receiver is just returned.
    ///
    /// - Note: Empty subpath is the root. So standardized "a/../../b" is "b".
    ///
    /// - SeeAlso: ``joinedStandardized``.
    @inlinable
    public var standardized: KvUrlPath {
        guard let index = components.firstIndex(where: {
            switch $0 {
            case ".", "..":
                return true
            default:
                return false
            }
        })
        else { return self } /* The is nothing to change */

        var accumulator = Array(components.prefix(upTo: index))

        components[index...].forEach { component in
            switch component {
            case ".":
                break
            case "..":
                guard !accumulator.isEmpty else { break }
                accumulator.removeLast()
            default:
                accumulator.append(component)
            }
        }

        return .init(safeComponents: accumulator)
    }

    /// The result of `self.standardized.joined`.
    ///
    /// - Important: It's faster then consequent calls to ``standardized`` and ``joined``.
    @inlinable
    public var joinedStandardized: String {
        guard let index = components.firstIndex(where: {
            switch $0 {
            case ".", "..":
                return true
            default:
                return false
            }
        })
        else { return joined }

        var accumulator = Accumulator(initial: components[..<index])

        components[index...].forEach { component in
            switch component {
            case ".":
                break
            case "..":
                accumulator.removeLast()
            default:
                accumulator.append(component)
            }
        }

        return accumulator.value
    }


    /// - Returns: A boolean value indicating whether the receiver contains entire *prefix* subpath at the beginning.
    @inlinable
    public func starts(with prefix: KvUrlPath) -> Bool {
        components.starts(with: prefix.components)
    }


    /// - Returns: A boolean value indicating whether the receiver contains entire *prefix* subpath at the beginning.
    @inlinable
    public func starts(with prefix: SubSequence) -> Bool {
        components.starts(with: prefix.components)
    }


    /// - Returns: A boolean value indicating whether the receiver contains entire *prefix* subpath at the beginning.
    @inlinable
    public func starts<P>(with prefix: P) -> Bool where P : KvUrlPathProtocol {
        components.starts(with: prefix.components)
    }


    /// - Returns: A slice of the receiver containing up to given number of components.
    @inlinable
    public func prefix(_ maxLength: Int) -> SubSequence {
        SubSequence(safeComponents: components.prefix(maxLength))
    }


    /// - Returns: A scile of the receiver with leading elements matching *predicate*
    @inlinable
    public func prefix(while predicate: (Components.Element) throws -> Bool) rethrows -> SubSequence {
        try SubSequence(safeComponents: components.prefix(while: predicate))
    }


    /// - Returns: A slice of the receiver from start index to, but not including, given index.
    @inlinable
    public func prefix(upTo end: Components.Index) -> SubSequence {
        SubSequence(safeComponents: components.prefix(upTo: end))
    }


    /// - Returns: A slice of the receiver from start index to, including, given index.
    @inlinable
    public func prefix(through position: Components.Index) -> SubSequence {
        SubSequence(safeComponents: components.prefix(through: position))
    }


    /// - Returns: A slice of the receiver containing all but given number of components.
    @inlinable
    public func dropFirst(_ count: Int = 1) -> SubSequence {
        SubSequence(safeComponents: components.dropFirst(count))
    }



    // MARK: Operators

    @inlinable
    public static func +(lhs: Self, rhs: KvUrlPath) -> KvUrlPath {
        var components = lhs._components
        components.append(contentsOf: rhs._components)
        return .init(safeComponents: components)
    }


    @inlinable
    public static func +<P>(lhs: Self, rhs: P) -> KvUrlPath where P : KvUrlPathProtocol {
        var components = lhs._components
        components.append(contentsOf: rhs.components)
        return .init(safeComponents: components)
    }


    @inlinable
    public static func +=(lhs: inout Self, rhs: KvUrlPath) { lhs.append(rhs) }


    @inlinable
    public static func +=<P>(lhs: inout Self, rhs: P) where P : KvUrlPathProtocol { lhs.append(rhs) }

}



// MARK: .SubSequence

extension KvUrlPath {

    public typealias Slice = SubSequence


    /// A continuous view on ``KvUrlPath``.
    public struct SubSequence : KvUrlPathProtocol {

        /// Path components without path separators.
        public let components: [Substring].SubSequence


        /// Initializes empty instance.
        @inlinable
        public init() { components = [ ] }


        /// Initializes an instance as a view on entire *path*.
        @inlinable
        public init<P>(_ path: P) where P : KvUrlPathProtocol { components = .init(path.components) }


        /// - Parameter safeComponents: Array of components guaranteed to be valid.
        @usableFromInline
        init(safeComponents: [Substring].SubSequence) { self.components = safeComponents }


        /// - Parameter safeComponents: Array of components guaranteed to be valid.
        @usableFromInline
        init(safeComponents: [Substring]) { self.components = .init(safeComponents) }


        /// - Parameter safeComponents: Sequence of components guaranteed to be valid.
        @usableFromInline
        init<C>(safeComponents: C) where C : Sequence, C.Element == Substring
        { self.components = .init(Array(safeComponents)) }


        /// - Parameter safeComponents: Collection of components guaranteed to be valid.
        @usableFromInline
        init<C>(safeComponents: C) where C : Collection, C.Element : StringProtocol
        { self.components = .init(safeComponents.map { .init($0) }) }


        /// Splits any of *components* containing path separators. The resulting components are used to initialize an instance.
        @inlinable
        public init(with components: [Substring]) {
            self.init(KvUrlPath(with: components))
        }


        /// Splits any of *components* containing path separators. The resulting components are used to initialize an instance.
        @inlinable
        public init<C>(with components: C) where C : Sequence, C.Element == Substring
        { self.init(KvUrlPath(with: components)) }


        /// Splits any of *components* containing path separators. The resulting components are used to initialize an instance.
        @inlinable
        public init<C>(with components: C) where C : Sequence, C.Element : StringProtocol
        { self.init(KvUrlPath(with: components)) }


        /// Splits given *path* to path components and initializes an instance with the result.
        @inlinable
        public init(path: String) { self.init(KvUrlPath(path: path)) }


        /// Splits given *path* to path components and initializes an instance with the result.
        @inlinable
        public init<S>(path: S) where S : StringProtocol { self.init(KvUrlPath(path: path)) }



        // MARK: : ExpressibleByStringLiteral

        /// Initializes from path as a astring literal.
        @inlinable
        public init(stringLiteral value: StringLiteralType) { self.init(path: value) }



        // MARK: : ExpressibleByArrayLiteral

        /// Processes elements of given array literal and initializes an instance with the resulting components.
        @inlinable
        public init(arrayLiteral elements: Substring...) { self.init(with: elements) }



        // MARK: Subscripts

        /// - Returns: Slice of the receiver matching given index *range*.
        @inlinable
        public subscript<R>(range: R) -> SubSequence
        where R : RangeExpression, R.Bound == Components.Index
        {
            SubSequence(safeComponents: components[range])
        }



        // MARK: Operations

        /// A copy where occurrences of "." and ".." special components are resolved.
        /// If there is no "." and ".." special components then the receiver is just returned.
        ///
        /// - Note: Empty subpath is the root. So standardized "a/../../b" is "b".
        ///
        /// - SeeAlso: ``joinedStandardized``.
        @inlinable
        public var standardized: Self {
            guard let index = components.firstIndex(where: {
                switch $0 {
                case ".", "..":
                    return true
                default:
                    return false
                }
            })
            else { return self } /* The is nothing to change */

            var accumulator = Array(components.prefix(upTo: index))

            components[index...].forEach { component in
                switch component {
                case ".":
                    break
                case "..":
                    guard !accumulator.isEmpty else { break }
                    accumulator.removeLast()
                default:
                    accumulator.append(component)
                }
            }

            return .init(safeComponents: accumulator)
        }

        /// The result of `self.standardized.joined`.
        ///
        /// - Important: It's faster then consequent calls to ``standardized`` and ``joined``.
        @inlinable
        public var joinedStandardized: String {
            guard let index = components.firstIndex(where: {
                switch $0 {
                case ".", "..":
                    return true
                default:
                    return false
                }
            })
            else { return joined }

            var accumulator = Accumulator(initial: components[..<index])

            components[index...].forEach { component in
                switch component {
                case ".":
                    break
                case "..":
                    accumulator.removeLast()
                default:
                    accumulator.append(component)
                }
            }

            return accumulator.value
        }


        /// - Returns: A boolean value indicating whether the receiver contains entire *prefix* subpath at the beginning.
        @inlinable
        public func starts(with prefix: KvUrlPath) -> Bool {
            components.starts(with: prefix.components)
        }


        /// - Returns: A boolean value indicating whether the receiver contains entire *prefix* subpath at the beginning.
        @inlinable
        public func starts(with prefix: SubSequence) -> Bool {
            components.starts(with: prefix.components)
        }


        /// - Returns: A boolean value indicating whether the receiver contains entire *prefix* subpath at the beginning.
        @inlinable
        public func starts<P>(with prefix: P) -> Bool where P : KvUrlPathProtocol {
            components.starts(with: prefix.components)
        }


        /// - Returns: A slice of the receiver containing up to given number of components.
        @inlinable
        public func prefix(_ maxLength: Int) -> SubSequence {
            SubSequence(safeComponents: components.prefix(maxLength))
        }


        /// - Returns: A scile of the receiver with leading elements matching *predicate*
        @inlinable
        public func prefix(while predicate: (Components.Element) throws -> Bool) rethrows -> SubSequence {
            try SubSequence(safeComponents: components.prefix(while: predicate))
        }


        /// - Returns: A slice of the receiver from start index to, but not including, given index.
        @inlinable
        public func prefix(upTo end: Components.Index) -> SubSequence {
            SubSequence(safeComponents: components.prefix(upTo: end))
        }


        /// - Returns: A slice of the receiver from start index to, including, given index.
        @inlinable
        public func prefix(through position: Components.Index) -> SubSequence {
            SubSequence(safeComponents: components.prefix(through: position))
        }


        /// - Returns: A slice of the receiver containing all but given number of components.
        @inlinable
        public func dropFirst(_ count: Int = 1) -> SubSequence {
            SubSequence(safeComponents: components.dropFirst(count))
        }



        // MARK: Operators

        @inlinable
        public static func +(lhs: Self, rhs: KvUrlPath.Slice) -> KvUrlPath {
            var components = Array(lhs.components)
            components.append(contentsOf: rhs.components)
            return .init(safeComponents: components)
        }


        @inlinable
        public static func +<P>(lhs: Self, rhs: P) -> KvUrlPath where P : KvUrlPathProtocol {
            var components = Array(lhs.components)
            components.append(contentsOf: rhs.components)
            return .init(safeComponents: components)
        }

    }

}



// MARK: .Accumulator

extension KvUrlPath {

    public struct Accumulator {

        @inlinable
        public var value: String { _value }


        @usableFromInline
        var _value: String


        @inlinable
        public init() { _value = "" }


        @inlinable
        public init(initial: String) { _value = initial }


        @inlinable
        public init<Components>(initial: Components) where Components : Sequence, Components.Element : StringProtocol {
            _value = initial.joined(separator: .init(KvUrlPath.separator))
        }


        // MARK: Operations

        @inlinable
        public mutating func append(_ component: Substring) {
            if !_value.isEmpty {
                _value.append(KvUrlPath.separator)
            }
            _value.append(contentsOf: component)
        }


        @inlinable
        public mutating func append<C : StringProtocol>(_ component: C) {
            if !_value.isEmpty {
                _value.append(KvUrlPath.separator)
            }
            _value.append(contentsOf: component)
        }


        @inlinable
        public mutating func removeLast() {
            guard let lastIndex = _value.lastIndex(of: KvUrlPath.separator),
                  lastIndex != _value.startIndex
            else { return _value.removeAll() }

            _value.removeLast(_value.distance(from: lastIndex, to: _value.endIndex))
        }

    }

}
