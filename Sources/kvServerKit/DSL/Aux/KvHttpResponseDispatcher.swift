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
//  KvHttpResponseDispatcher.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 30.06.2023.
//

import Foundation

import kvKit



class KvHttpResponseDispatcher {

    typealias RequestProcessorResult = Match<KvHttpRequestProcessorProtocol>



    init?(from schema: Schema) {
        guard let rootNode = schema.build() else { return nil }

        self.rootNode = rootNode
    }



    private let rootNode: Node



    // MARK: .Context

    /// It's used to identify responses in a dispatcher.
    class Context {

        let method: String
        let url: URL
        let urlComponents: URLComponents
        /// Path components are not part of *URLComponents* so it's a stand-alone property.
        let pathComponents: [String]


        init?(from head: KvHttpServer.RequestHead) {
            guard let url = URL(string: head.uri),
                  let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return nil }

            method = head.method.rawValue
            self.url = url
            self.urlComponents = urlComponents
            pathComponents = url.pathComponents
        }

    }



    // MARK: .Match

    enum Match<T> {

        /// There are several matches.
        case ambiguous
        /// There are no matches.
        case notFound
        /// There is an unambiguous match.
        case unambiguous(T)


        // MARK: Operations

        @inline(__always)
        func map<R>(_ transform: (T) -> R) -> Match<R> {
            switch self {
            case .unambiguous(let payload):
                return .unambiguous(transform(payload))
            case .notFound:
                return .notFound
            case .ambiguous:
                return .ambiguous
            }
        }


        @inline(__always)
        func flatMap<R>(_ transform: (T) -> Match<R>) -> Match<R> {
            switch self {
            case .unambiguous(let payload):
                return transform(payload)
            case .notFound:
                return .notFound
            case .ambiguous:
                return .ambiguous
            }
        }


        /// - Returns: Result as if the receiver and *rhs* matches have been both encountered.
        @inline(__always)
        func union(with rhs: Self) -> Self {
            switch (self, rhs) {
            case (.unambiguous(let payload), .notFound), (.notFound, .unambiguous(let payload)):
                return .unambiguous(payload)
            case (.notFound, .notFound):
                return .notFound
            case (.ambiguous, .notFound), (.ambiguous, .unambiguous), (.ambiguous, .ambiguous), (.notFound, .ambiguous), (.unambiguous, .unambiguous), (.unambiguous, .ambiguous):
                return .ambiguous
            }
        }

    }



    // MARK: Operations

    /// - Returns: A request implementation, error or `nil`. `Nil` is returned when none or multiple candidates are matching given *context*.
    func requestProcessor(in context: Context) -> RequestProcessorResult {
        rootNode.requestProcessor(in: context)
    }

}



// MARK: .Schema.Container

fileprivate protocol KvHttpResponseDispatcherSchemaContainer {

    init()


    func build() -> KvHttpResponseDispatcherNode?

}


extension KvHttpResponseDispatcher.Schema {

    fileprivate typealias Container = KvHttpResponseDispatcherSchemaContainer

}



// MARK: .Schema

extension KvHttpResponseDispatcher {

    struct Schema {

        private let methods: Methods = .init()


        // MARK: Operations

        func insert(_ response: KvHttpResponseImplementationProtocol, for configuration: KvResponseGroupConfiguration.Dispatching) {
            methods.insert(response, for: configuration)
        }


        fileprivate func build() -> Node? {
            methods.build()
        }


        // MARK: .DictionaryContainer

        /// Holds dictionary of child containers for specific keys and a child container matching any key.
        private class DictionaryContainer<Child, SpecificNode> : Container
        where Child : Container, SpecificNode : DictionaryNode
        {

            typealias Key = SpecificNode.Key
            typealias Child = Child


            required init() { }


            private var wildcardChild: Child?
            private var specificChildren: [Key : Child] = .init()


            // MARK: Operations

            /// Correctry enumerates keys in optional sequences. Body is called with whildcard key (`nil`) when *keys* are missing or empty.
            static func forEachKey<S>(in keys: S?, body: (Key?) -> Void) where S : Sequence, S.Element == Key {
                guard var iterator = keys?.makeIterator() else { return body(nil) }

                do {
                    guard let first = iterator.next() else { return body(nil) }

                    body(first)
                }

                while let next = iterator.next() {
                    body(next)
                }
            }


            func child(for key: Key?) -> Child {

                func GetOrCreate(_ value: inout Child?) -> Child {
                    switch value {
                    case .none:
                        let child = Child()
                        value = child
                        return child

                    case .some(let child):
                        return child
                    }
                }


                switch key {
                case .some(let key):
                    return GetOrCreate(&specificChildren[key])
                case .none:
                    return GetOrCreate(&wildcardChild)
                }
            }


            // MARK: : Container

            func build() -> Node? {
                let wildcardNode = wildcardChild?.build()

                let specificNode: SpecificNode?
                do {
                    let specific = specificChildren.compactMapValues { $0.build() }

                    specificNode = !specific.isEmpty ? .init(subnodes: specific) : nil
                }

                switch (specificNode, wildcardNode) {
                case (.some(let specificNode), .some(let wildcardNode)):
                    return MixedNode(specific: specificNode, wildcard: wildcardNode)
                case (.some(let specificNode), .none):
                    return specificNode
                case (.none, .some(let wildcardNode)):
                    return wildcardNode
                case (.none, .none):
                    return nil
                }
            }

        }


        // MARK: .HierarchyContainer

        /// Holds hiararchy of child containers identified by sequence of keys.
        private class HierarchyContainer<Child, SpecificNode> : Container
        where Child : Container, SpecificNode : HierarchyNode
        {

            typealias Key = SpecificNode.Key
            typealias Child = Child


            required init() { }


            private var root: Element = .init()


            // MARK: .Element

            class Element {
                var subcontainers: [Key : Element] = .init()
                var child: Child?
            }


            // MARK: Operations

            func child<S>(for keys: S) -> Child
            where S : Sequence, S.Element == Key
            {
                var iterator = keys.makeIterator()

                var element = root

                while let component = iterator.next() {
                    element = {
                        switch $0 {
                        case .none:
                            let content = Element()
                            $0 = content
                            return content

                        case .some(let content):
                            return content
                        }
                    }(&element.subcontainers[component])
                }

                switch element.child {
                case .none:
                    let child = Child()
                    element.child = child
                    return child

                case .some(let child):
                    return child
                }
            }


            // MARK: : Container

            func build() -> Node? {

                func Build(_ element: Element) -> SpecificNode? {
                    let queryNode = element.child?.build()
                    let childNodes = element.subcontainers.compactMapValues(Build(_:))

                    guard !childNodes.isEmpty || queryNode != nil else { return nil }

                    return SpecificNode(childNodes: childNodes, subnode: queryNode)
                }

                return Build(root)
            }

        }


        // MARK: .Methods

        private class Methods : DictionaryContainer<Users, MethodNode> {

            func insert(_ response: KvHttpResponseImplementationProtocol, for configuration: KvResponseGroupConfiguration.Dispatching) {
                Self.forEachKey(in: configuration.httpMethods) { method in
                    child(for: method).insert(response, for: configuration)
                }
            }

        }


        // MARK: .Users

        private class Users : DictionaryContainer<Hosts, UserNode> {

            func insert(_ response: KvHttpResponseImplementationProtocol, for configuration: KvResponseGroupConfiguration.Dispatching) {
                Self.forEachKey(in: configuration.users) { user in
                    child(for: user).insert(response, for: configuration)
                }
            }

        }


        // MARK: .Hosts

        private class Hosts : DictionaryContainer<Paths, HostDictionaryNode> {

            func insert(_ response: KvHttpResponseImplementationProtocol, for configuration: KvResponseGroupConfiguration.Dispatching) {
                Self.forEachHost(in: configuration) { host in
                    child(for: host).insert(response, for: configuration)
                }
            }


            // MARK: Auxiliaries

            private static func forEachHost(in configuration: KvResponseGroupConfiguration.Dispatching, _ body: (Key?) -> Void) {
                guard !configuration.hosts.isEmpty
                else { return body(nil) }


                func Body(_ host: String) {

                    func EncodedHost(_ value: String) -> String? {
                        var urlComponents = URLComponents()

                        urlComponents.host = value

                        // TODO: Review if URLComponents.encodedHost is available on non-Apple platforms.
#if canImport(Darwin)
                        // TODO: Review when target minimum OS versions are changed.
                        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
                            return urlComponents.encodedHost
                        } else {
                            return urlComponents.url?.host
                        }
#else // !canImport(Darwin)
                        return urlComponents.url?.host
#endif // !canImport(Darwin)
                    }


                    guard let host = EncodedHost(host) else { return }

                    body(host)
                }


                switch configuration.optionalSubdomains.isEmpty {
                case true:
                    configuration.hosts.forEach(Body(_:))

                case false:
                    configuration.optionalSubdomains.forEach { optionalSubdomain in
                        configuration.hosts.forEach { host in
                            Body("\(optionalSubdomain).\(host)")
                        }
                    }
                }
            }

        }


        // MARK: .Paths

        private class Paths : HierarchyContainer<Responses, PathNode> {

            func insert(_ response: KvHttpResponseImplementationProtocol, for configuration: KvResponseGroupConfiguration.Dispatching) {
                let keys = PathNode.safePathComponens(Self.pathComponents(from: configuration))

                child(for: keys).insert(response)
            }


            // MARK: Auxiliaries

            private static func pathComponents(from configuration: KvResponseGroupConfiguration.Dispatching) -> [String] {
                let path = configuration.path

                return URL(fileURLWithPath: path.starts(with: "/") ? path : ("/" + path)).pathComponents
            }

        }


        // MARK: .Responses

        private class Responses : Container {

            required init() { }


            private var responses: [KvHttpResponseImplementationProtocol] = .init()


            // MARK: Operations

            func insert<R>(_ response: R) where R : KvHttpResponseImplementationProtocol {
                responses.append(response)
            }


            func build() -> Node? {
                guard !responses.isEmpty else { return nil }

                return QueryNode.with(responses)
            }

        }

    }

}



// MARK: .Node

fileprivate protocol KvHttpResponseDispatcherNode {

    func requestProcessor(in context: KvHttpResponseDispatcher.Context) -> KvHttpResponseDispatcher.RequestProcessorResult

}


extension KvHttpResponseDispatcher {

    fileprivate typealias Node = KvHttpResponseDispatcherNode

}



// MARK: .DictionaryContainerProtocol

fileprivate protocol KvHttpResponseDispatcherDictionaryContainerProtocol {

    associatedtype Key : Hashable


    func subnode(for key: Key) -> KvHttpResponseDispatcherNode?

}


extension KvHttpResponseDispatcher {

    fileprivate typealias DictionaryContainerProtocol = KvHttpResponseDispatcherDictionaryContainerProtocol

}



// MARK: .DictionaryNode

fileprivate protocol KvHttpResponseDispatcherDictionaryNode : KvHttpResponseDispatcherDictionaryContainerProtocol, KvHttpResponseDispatcherNode {

    init(subnodes: [Key : KvHttpResponseDispatcherNode])


    static func key(from context: KvHttpResponseDispatcher.Context) -> Key?

}


extension KvHttpResponseDispatcherDictionaryNode {

    func requestProcessor(in context: KvHttpResponseDispatcher.Context) -> KvHttpResponseDispatcher.RequestProcessorResult {
        guard let key = Self.key(from: context),
              let subnode = subnode(for: key)
        else { return .notFound }

        return subnode.requestProcessor(in: context)
    }

}


extension KvHttpResponseDispatcher {

    fileprivate typealias DictionaryNode = KvHttpResponseDispatcherDictionaryNode

}



// MARK: .HierarchyNode

fileprivate protocol KvHttpResponseDispatcherHierarchyNode : KvHttpResponseDispatcherNode {

    associatedtype Key : Hashable
    associatedtype Keys : Sequence where Keys.Element == Key


    init(childNodes: [Key : Self], subnode: KvHttpResponseDispatcherNode?)


    static func keys(from context: KvHttpResponseDispatcher.Context) -> Keys


    func subnode<S>(for keys: S) -> KvHttpResponseDispatcherNode? where S : Sequence, S.Element == Key

}


extension KvHttpResponseDispatcherHierarchyNode {

    func requestProcessor(in context: KvHttpResponseDispatcher.Context) -> KvHttpResponseDispatcher.RequestProcessorResult {
        guard let subnode = subnode(for: Self.keys(from: context))
        else { return .notFound }

        return subnode.requestProcessor(in: context)
    }

}


extension KvHttpResponseDispatcher {

    fileprivate typealias HierarchyNode = KvHttpResponseDispatcherHierarchyNode

}



// MARK: Nodes

extension KvHttpResponseDispatcher {

    // MARK: .DictionaryContainer

    fileprivate class DictionaryContainer<Key : Hashable> : KvHttpResponseDispatcherDictionaryContainerProtocol {

        typealias Key = Key


        required init(subnodes: [Key : Node]) {
            self.subnodes = subnodes
        }


        private let subnodes: [Key : Node]


        // MARK: : KvHttpResponseDispatcherDictionaryContainerProtocol

        func subnode(for key: Key) -> Node? {
            subnodes[key]
        }

    }



    // MARK: .MixedContainer

    fileprivate class MixedNode<DictionaryContainer : DictionaryNode> : Node {

        init(specific: DictionaryContainer, wildcard: Node) {
            specificSubnodes = specific
            wildcardSubnode = wildcard
        }


        private let specificSubnodes: DictionaryContainer
        private let wildcardSubnode: Node


        // MARK: : Node

        func requestProcessor(in context: KvHttpResponseDispatcher.Context) -> RequestProcessorResult {
            wildcardSubnode.requestProcessor(in: context)
                .union(with: specificSubnodes.requestProcessor(in: context))
        }

    }



    // MARK: .MethodNode

    fileprivate class MethodNode : DictionaryContainer<String>, DictionaryNode {

        static func key(from context: KvHttpResponseDispatcher.Context) -> String? {
            context.method
        }

    }



    // MARK: .UserNode

    fileprivate class UserNode : DictionaryContainer<String>, DictionaryNode {

        static func key(from context: KvHttpResponseDispatcher.Context) -> String? {
            context.url.user
        }

    }



    // MARK: .HostNode

    fileprivate class HostDictionaryNode : DictionaryContainer<String>, DictionaryNode {

        static func key(from context: KvHttpResponseDispatcher.Context) -> String? {
            context.url.host
        }

    }



    // MARK: .PathNode

    /// - Note: There is no placeholder paths.
    fileprivate class PathNode : HierarchyNode {

        typealias Key = String


        required init(childNodes: [Key : PathNode], subnode: Node?) {
            self.childNodes = childNodes
            self.subnode = subnode
        }


        private let childNodes: [Key : PathNode]

        private let subnode: Node?


        // MARK: : HierarchyNode

        static func keys(from context: KvHttpResponseDispatcher.Context) -> [Key] {
            context.pathComponents
        }


        func subnode<S>(for keys: S) -> Node? where S : Sequence, S.Element == Key {
            var iterator = Self.safePathComponens(keys).makeIterator()
            var node: PathNode = self

            while let component = iterator.next() {
                guard let child = node.childNodes[component]
                else { return nil }

                node = child
            }

            return node.subnode
        }


        // MARK: Auxiliaries

        static func safePathComponens<S>(_ components: S) -> LazyFilterSequence<S>
        where S : Sequence, S.Element == String
        {
            components.lazy.filter { $0 != "/" }
        }

    }



    // MARK: .QueryNode

    /// Selects matching response by query.
    fileprivate class QueryNode {

        /// - Note: Use ``with(_:)`` fabric.
        private init() { }


        // MARK: Fabrics

        static func with<S>(_ responses: S) -> Node
        where S : Sequence, S.Element == KvHttpResponseImplementationProtocol
        {

            func Append<T>(_ element: T, to array: inout [T]?) {
                array?.append(element)
                ?? (array = [ element ])
            }


            /// - Note: Array is always created.
            func Joined<T>(_ array: [T]?, _ element: T?) -> [T] {
                switch (array, element) {
                case (.some(var array), .some(let element)):
                    array.append(element)
                    return array
                case (.some(let array), .none):
                    return array
                case (.none, .some(let element)):
                    return [ element]
                case (.none, .none):
                    assertionFailure("Internal warning: review related code to prevent invocation with degenerate arguments")
                    return [ ]
                }
            }


            func AsSerial(_ element: Element<KvEmptyUrlQueryParser>) -> Element<KvSerialUrlQueryParser> {
                .init(queryParser: element.queryParser as KvSerialUrlQueryParser, processorBlock: element.processorBlock)
            }


            var emptyQueryElement: Element<KvEmptyUrlQueryParser>?
            var entireQueryElements: [Element<KvEntireUrlQueryParser>]?
            var serialQueryElements: [Element<KvSerialUrlQueryParser>]?

            responses.forEach { response in
                let queryParser = response.urlQueryParser

                defer { queryParser.reset() }

                switch queryParser {
                case let queryParser as KvEmptyUrlQueryParser:
                    if emptyQueryElement != nil {
                        KvDebug.pause("Warninig: HTTP response for empty URL query has was replaced")
                    }
                    emptyQueryElement = .init(queryParser: queryParser, processorBlock: response.makeProcessor)

                case let queryParser as KvEntireUrlQueryParser:
                    Append(.init(queryParser: queryParser, processorBlock: response.makeProcessor), to: &entireQueryElements)

                case let queryParser as KvSerialUrlQueryParser:
                    Append(.init(queryParser: queryParser, processorBlock: response.makeProcessor), to: &serialQueryElements)

                default:
                    KvDebug.pause("Warninig: HTTP response for unexpected URL query type was ignored")
                }
            }

            // - Note: all-nil case is not handled assuming it's never invoked for empty list of responses.
            switch (emptyQueryElement, entireQueryElements, serialQueryElements) {
            case (.some(let emptyQueryElement), .none, .none):
                return EmptyQuery(emptyQueryElement)

            case (.none, .none, .some(let serialQueryElements)):
                switch serialQueryElements.count == 1 {
                case true:
                    return SerialQuery(serialQueryElements[0])
                case false:
                    return SerialQueries(serialQueryElements)
                }

            case (.some(let emptyQueryElement), .none, .some(let serialQueryElements)):
                return SerialQueries(Joined(serialQueryElements, AsSerial(emptyQueryElement)))


            case (.none, .some(let entireQueryElements), .none):
                switch entireQueryElements.count == 1 {
                case true:
                    return EntireQuery(entireQueryElements[0])
                case false:
                    return EntireQueries(entireQueryElements)
                }

            default:
                return MixedQueries(serial: Joined(serialQueryElements, emptyQueryElement.map(AsSerial(_:))), entire: entireQueryElements ?? [ ])
            }
        }


        private typealias ProcessorBlock = () -> KvHttpRequestProcessorProtocol?


        // MARK: .Element

        private struct Element<QueryParser> {

            let queryParser: QueryParser
            let processorBlock: ProcessorBlock


            // MARK: Operations

            func makeProcessor() -> RequestProcessorResult {
                switch processorBlock() {
                case .some(let processor):
                    return .unambiguous(processor)
                case .none:
                    return .notFound
                }
            }

        }


        // MARK: .EmptyQuery

        /// Dedicated node optimized to handle single empty query parser.
        private class EmptyQuery : Node {

            typealias Element = QueryNode.Element<KvEmptyUrlQueryParser>


            init(_ queryElement: Element) {
                self.queryElement = queryElement
            }


            private let queryElement: Element


            // MARK: : Node

            func requestProcessor(in context: Context) -> RequestProcessorResult {
                guard context.urlComponents.queryItems?.isEmpty != false
                else { return .notFound }

                return queryElement.makeProcessor()
            }

        }


        // MARK: .EntireQuery

        /// Dedicated node optimized to handle single custom query parser.
        private class EntireQuery : Node {

            typealias Element = QueryNode.Element<KvEntireUrlQueryParser>


            init(_ queryElement: Element) {
                self.queryElement = queryElement
            }


            private let queryElement: Element


            // MARK: : Node

            func requestProcessor(in context: Context) -> RequestProcessorResult {
                defer { queryElement.queryParser.reset() }

                guard queryElement.queryParser.parse(context.urlComponents.queryItems) == .complete
                else { return .notFound }

                return queryElement.makeProcessor()
            }

        }


        // MARK: .SerialQuery

        /// Dedicated node optimized to handle single serial query parser.
        private class SerialQuery : Node {

            typealias Element = QueryNode.Element<KvSerialUrlQueryParser>


            init(_ queryElement: Element) {
                self.queryElement = queryElement
            }


            private let queryElement: Element


            // MARK: : Node

            func requestProcessor(in context: Context) -> RequestProcessorResult {
                let queryParser = queryElement.queryParser

                guard let query = context.urlComponents.queryItems,
                      !query.isEmpty
                else {
                    switch queryParser.status == .complete {
                    case true:
                        return queryElement.makeProcessor()
                    case false:
                        return .notFound
                    }
                }

                defer { queryParser.reset() }

                for queryItem in query {
                    guard queryParser.parse(queryItem) != .failure
                    else { return .notFound }
                }

                guard queryParser.status == .complete
                else { return .notFound }

                return queryElement.makeProcessor()
            }

        }


        // MARK: .EntireQueries

        /// Dedicated node optimized to handle responses with custom query parsers.
        private class EntireQueries : Node {

            typealias Element = EntireQuery.Element


            init(_ queryElements: [Element]) {
                self.queryElements = queryElements
            }


            private let queryElements: [Element]


            // MARK: : Node

            func requestProcessor(in context: Context) -> RequestProcessorResult {
                Self.withMatchResult(queryElements, in: context) { match in
                    match.flatMap { processorBlock in
                        processorBlock()
                    }
                }
            }


            // MARK: Auxiliaries

            /// - Parameter body: It's called with the result anyway, even if there are no candidates or several candidates.
            @inline(__always)
            static func withMatchResult(_ elements: [Element], in context: Context, body: (Match<() -> RequestProcessorResult>) -> RequestProcessorResult) -> RequestProcessorResult {
                let query = context.urlComponents.queryItems

                switch match(in: elements, where: { $0.parse(query) }, onDiscard: { $0.reset() }) {
                case .unambiguous(let element):
                    // - Note: Affected query parsers are reset.
                    defer { element.queryParser.reset() }

                    return body(.unambiguous(element.makeProcessor))

                case .notFound:
                    return body(.notFound)

                case .ambiguous:
                    return body(.ambiguous)
                }
            }

        }


        // MARK: .SerialQueries

        /// Dedicated node optimized to handle responses with structured query parsers.
        private class SerialQueries : Node {

            typealias Element = SerialQuery.Element


            init(_ queryElements: [Element]) {
                self.queryElements = queryElements
            }


            private let queryElements: [Element]


            // MARK: : Node

            func requestProcessor(in context: Context) -> RequestProcessorResult {
                Self.withMatchResult(queryElements, in: context) { match in
                    match.flatMap { processorBlock in
                        processorBlock()
                    }
                }
            }


            // MARK: : Auxiliaries

            /// - Parameter body: It's called with the result anyway, even if there are no candidates or several candidates.
            @inline(__always)
            static func withMatchResult(_ elements: [Element], in context: Context, body: (Match<() -> RequestProcessorResult>) -> RequestProcessorResult) -> RequestProcessorResult {
                guard let query = context.urlComponents.queryItems,
                      !query.isEmpty
                else {
                    // - Note: Empty query is not passed to query parsers so there is no need to reset the query parsers.
                    return body(match(in: elements, where: { $0.status }, onDiscard: { _ in }).map { $0.makeProcessor })
                }

                var queryIterator = query.makeIterator()
                var candidateIndices = IndexSet(elements.indices)


                func Process(_ queryItem: URLQueryItem) {
                    candidateIndices.forEach { index in
                        let queryParser = elements[index].queryParser

                        switch queryParser.parse(queryItem) {
                        case .complete, .incomplete:
                            break

                        case .failure:
                            candidateIndices.remove(index)
                            // - Note: Affected query parsers are reset.
                            queryParser.reset()
                        }
                    }
                }


                func Finalize() -> RequestProcessorResult {
                    var iterator = candidateIndices
                        .lazy.map { elements[$0] }
                        .makeIterator()


                    func Next() -> Element? {
                        while let next = iterator.next() {
                            if next.queryParser.status == .complete {
                                return next
                            }

                            // - Note: Affected query parsers are reset.
                            next.queryParser.reset()
                        }
                        return nil
                    }


                    guard let match = Next() else { return body(.notFound) }

                    // - Note: Affected query parsers are reset.
                    defer { match.queryParser.reset() }

                    switch Next() {
                    case .none:
                        return body(.unambiguous(match.makeProcessor))

                    case .some(let other):
                        // - Note: Affected query parsers are reset.
                        other.queryParser.reset()

                        while let next = iterator.next() {
                            // - Note: Affected query parsers are reset.
                            next.queryParser.reset()
                        }

                        return body(.ambiguous)
                    }
                }


                do {
                    guard let firstQueryItem = queryIterator.next()
                    else { return body(.notFound) }

                    Process(firstQueryItem)
                }

                while let queryItem = queryIterator.next() {
                    guard !candidateIndices.isEmpty
                    else { return body(.notFound) }

                    Process(queryItem)
                }

                return Finalize()
            }

        }


        /// Dedicated node optimized to handle responses with both custom and structured query parsers.
        private class MixedQueries : Node {

            typealias EntireElement = Element<KvEntireUrlQueryParser>
            typealias SerialElement = Element<KvSerialUrlQueryParser>


            init(serial serialElements: [SerialElement], entire entireElements: [EntireElement]) {
                serialQueryElements = serialElements
                entireQueryElements = entireElements
            }


            private let serialQueryElements: [SerialElement]
            private let entireQueryElements: [EntireElement]


            // MARK: : Node

            func requestProcessor(in context: Context) -> RequestProcessorResult {
                SerialQueries.withMatchResult(serialQueryElements, in: context) { match1 in
                    EntireQueries.withMatchResult(entireQueryElements, in: context) { match2 in
                        match1.union(with: match2).flatMap { processorBlock in
                            processorBlock()
                        }
                    }
                }
            }

        }


        // MARK: Auxiliaries

        /// - Returns: Up to two first elements in *elements* where *predicate* is `true`.
        @inline(__always)
        private static func prefix2<S>(_ elements: S, where predicate: (S.Element) -> Bool) -> (S.Element, S.Element?)?
        where S : Sequence
        {
            var iterator = elements.makeIterator()


            /// Iterates elements and resets unuitable query parsers until suitable element is reached.
            ///
            /// - Note: Returned candidate must be reset explicitely.
            func NextCandidate() -> S.Element? {
                while let element = iterator.next() {
                    if predicate(element) {
                        return element
                    }
                }

                return nil
            }


            return NextCandidate().map { first in
                (first, NextCandidate())
            }
        }


        @inline(__always)
        private static func match<S, P>(in elements: S, where predicate: (P) -> KvUrlQueryParserStatus, onDiscard: (P) -> Void) -> Match<Element<P>>
        where S : Sequence, S.Element == Element<P>
        {
            let candidates = prefix2(elements) {
                switch predicate($0.queryParser) {
                case .complete:
                    return true

                case .incomplete, .failure:
                    onDiscard($0.queryParser)
                    return false
                }
            }

            switch candidates {
            case .some((let first, .none)):
                return .unambiguous(first)

            case .some((let first, .some(let second))):
                onDiscard(first.queryParser)
                onDiscard(second.queryParser)
                return .ambiguous

            case .none:
                return .notFound
            }
        }

    }

}
