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
//  KvHttpResponseDispatcher.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 30.06.2023.
//

import Foundation

import kvHttpKit

import kvKit



class KvHttpResponseDispatcher {

    init?(from scheme: Scheme) {
        guard let rootNode = scheme.build() else { return nil }

        self.rootNode = rootNode
    }



    private let rootNode: RootNode



    // MARK: .Attributes

    /// Conatiner for all dispach node attributes. They are designed to contain additions and to be accumulated while dispath tree is traversed.
    ///
    /// It's a class to minimize consumption of memory when a node has no attributes provided.
    class Attributes {

        var clientCallbacks: KvClientCallbacks?


        /// - Important: Use ``from(_:)`` and ``merge(addition:into:)``.
        private init() { }


        /// - Important: Use ``from(_:)`` and ``merge(addition:into:)``.
        private init(clientCallbacks: KvClientCallbacks?) {
            self.clientCallbacks = clientCallbacks
        }


        // MARK: Fabrics

        static func from(_ responseGroupConfiguration: KvResponseGroupConfiguration) -> Attributes? {
            var _context: Attributes? = nil

            let context: () -> Attributes = {
                _context ?? {
                    _context = .init()
                    return _context!
                }()
            }

            if let clientCallbacks = responseGroupConfiguration.clientCallbacks {
                context().clientCallbacks = clientCallbacks
            }

            return _context
        }


        // MARK: Operations

        static func merge(addition: Attributes?, into base: inout Attributes?) {
            guard let addition = addition else { return }

            merge(addition: addition, into: &base)
        }


        static func merge(addition: Attributes, into base: inout Attributes?) {
            switch base {
            case .some(let base):
                base.clientCallbacks = .accumulate(addition.clientCallbacks, into: base.clientCallbacks)

            case .none:
                base = .init(clientCallbacks: addition.clientCallbacks)
            }
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



    // MARK: .RequestProcessorResult

    class RequestProcessorResult {

        typealias Match = KvHttpResponseDispatcher.Match<KvHttpRequestProcessorProtocol>


        private(set) var match: Match = .notFound
        /// This property holds attributes resolved between all dispatch subtrees.
        private(set) var resolvedAttributes: Attributes?


        fileprivate init() { }


        /// Attributes in currect dispatch tree.
        fileprivate private(set) var groupAttributes: Attributes?

        private var resolvedAttributePathLevel: Int = 0
        /// It's used to collect attributes on different path nodes. E.g. on GET and generic method dispatch trees.
        private var groupAttributePathLevel: Int = 0


        // MARK: Operations

        fileprivate func finalize() {
            commitGroupAttributes()
        }


        fileprivate func collect(_ match: Match) {
            self.match = self.match.union(with: match)
        }


        fileprivate func collect(_ attributes: Attributes, pathLevel: Int) {
            switch pathLevel >= groupAttributePathLevel {
            case true:
                Attributes.merge(addition: attributes, into: &self.groupAttributes)
                groupAttributePathLevel = pathLevel

            case false:
                commitGroupAttributes()

                self.groupAttributes = attributes
                groupAttributePathLevel = pathLevel
            }
        }


        private func commitGroupAttributes() {
            guard resolvedAttributes == nil || groupAttributePathLevel > resolvedAttributePathLevel else { return }

            resolvedAttributes = groupAttributes
            resolvedAttributePathLevel = groupAttributePathLevel
        }

    }



    // MARK: Searching for Request Processors

    /// - Returns: A request implementation, error or `nil`. `Nil` is returned when none or multiple candidates are matching given *context*.
    func requestProcessor(in reqeustContext: KvHttpRequestContext) -> RequestProcessorResult {
        let result = RequestProcessorResult()

        rootNode.accumulateRequestProcessors(for: reqeustContext, into: result)

        result.finalize()

        return result
    }

}



// MARK: .Scheme.Container

fileprivate protocol KvHttpResponseDispatcherSchemeContainer {

    func build() -> KvHttpResponseDispatcherNode?

}


extension KvHttpResponseDispatcher.Scheme {

    fileprivate typealias Container = KvHttpResponseDispatcherSchemeContainer

}



// MARK: .Scheme

extension KvHttpResponseDispatcher {

    class Scheme {

        private let methods: Methods = .init()

        /// Hosts to hosts.
        private var redirections: [String : String] = .init()


        // MARK: Operations

        func insert(_ response: KvHttpResponseImplementationProtocol, for configuration: DispatchConfiguration) {
            methods.insert(response, for: configuration)
        }


        func insert(_ attributes: Attributes, for configuration: DispatchConfiguration) {
            methods.insert(attributes, for: configuration)
        }


        func insertRedirections(for configuration: KvResponseRootGroupConfiguration.Dispatching) {
            guard let targetHost = configuration.hosts.first else { return }


            func InsertRedirection(from source: String) {
                if let replacedTarget = redirections.updateValue(targetHost, forKey: source),
                   replacedTarget != targetHost
                {
                    KvDebug.pause("Target of redirection from «\(source)» host to «\(replacedTarget)» was replaced with «\(targetHost)»")
                }
            }


            if !configuration.optionalSubdomains.isEmpty {
                configuration.hosts
                    .lazy.flatMap { host in configuration.optionalSubdomains.lazy.map { subdomain in "\(host).\(subdomain)" } }
                    .forEach(InsertRedirection(from:))
            }

            configuration.hostAliases.forEach { host in
                InsertRedirection(from: host)

                configuration.optionalSubdomains.forEach { subdomain in
                    InsertRedirection(from: "\(host).\(subdomain)")
                }
            }
        }


        fileprivate func build() -> RootNode? {
            RootNode(subnode: methods.build(),
                     redirections: .init(hosts: redirections))
        }


        // MARK: Auxiliaries

        static func encodedHost(_ value: String) -> String? {
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


        // MARK: .DispatchConfiguration

        struct DispatchConfiguration {

            init(_ rootConfiguration: KvResponseRootGroupConfiguration.Dispatching?,
                 _ configuration: KvResponseGroupConfiguration.Dispatching?
            ) {
                self.hosts = rootConfiguration?.hosts
                self.group = configuration
            }


            /// Hosts from the root group.
            private let hosts: Set<String>?

            /// Dispatching configuratoin of a non-root response group.
            private let group: KvResponseGroupConfiguration.Dispatching?


            // MARK: Operations

            /// Invokes *body* callback with each HTTP method in the configuration.
            /// `nil` means wildcard method.
            func forEachHttpMethod(_ body: (KvHttpMethod?) -> Void) {
                guard let methods = group?.httpMethods else { return body(nil) }

                methods.elements.forEach(body)
            }


            /// Invokes *body* callback with each user in the configuration.
            /// `nil` means wildcard user.
            func forEachUser(_ body: (String?) -> Void) {
                guard let users = group?.users else { return body(nil) }

                users.elements.forEach(body)
            }


            /// Invokes *body* callback with each encoded host in the configuration.
            /// `nil` means wildcard user.
            func forEachHost(_ body: (String?) -> Void) {
                guard let hosts = hosts else { return body(nil) }

                hosts
                    .lazy.compactMap(Scheme.encodedHost(_:))
                    .forEach(body)
            }


            var path: KvUrlPath { group?.path ?? .empty }

        }


        // MARK: .DictionaryContainer

        /// Holds dictionary of child containers for specific keys and a child container matching any key.
        private class DictionaryContainer<Child, SpecificNode> : Container
        where Child : Container, SpecificNode : DictionaryNode
        {

            typealias Key = SpecificNode.Key
            typealias Child = Child


            private var wildcardChild: Child?
            private var specificChildren: [Key : Child] = .init()


            // MARK: Operations

            /// Correctly enumerates keys in optional sequences. Body is called with wildcard key (`nil`) when *keys* are missing or empty.
            static func forEachKey<S>(in keys: S?, body: (Key?) -> Void) where S : Sequence, S.Element == Key {
                /// `nil` means wildcard key.
                guard var iterator = keys?.makeIterator() else { return body(nil) }

                do {
                    /// Empty means no key.
                    guard let first = iterator.next() else { return }

                    body(first)
                }

                while let next = iterator.next() {
                    body(next)
                }
            }


            func child(for key: Key?, fabric: () -> Child) -> Child {

                func GetOrCreate(_ value: inout Child?) -> Child {
                    switch value {
                    case .none:
                        let child = fabric()
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
        private class HierarchyContainer<Child, DispatcherNode> : Container
        where Child : Container, DispatcherNode : HierarchyNode
        {

            typealias Key = DispatcherNode.Key
            typealias Child = Child


            private var root: Element = .init()


            // MARK: .Element

            class Element {
                var subcontainers: [Key : Element] = .init()
                var child: Child?
            }


            // MARK: Operations

            func child<Keys>(for keys: Keys, fabric: (_ level: Int) -> Child) -> Child
            where Keys : Collection, Keys.Element == Key
            {
                var iterator = keys.makeIterator()

                var element = root
                var level = 0

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
                    level += 1
                }

                switch element.child {
                case .none:
                    let child = fabric(keys.count)
                    element.child = child
                    return child

                case .some(let child):
                    return child
                }
            }


            // MARK: : Container

            func build() -> Node? {

                func Build(_ element: Element) -> DispatcherNode? {
                    let queryNode = element.child?.build()
                    let childNodes = element.subcontainers.compactMapValues(Build(_:))

                    guard !childNodes.isEmpty || queryNode != nil else { return nil }

                    return DispatcherNode(childNodes: childNodes, subnode: queryNode.map { $0 as! DispatcherNode.Subnode })
                }

                return Build(root)
            }

        }


        // MARK: .Methods

        private class Methods : DictionaryContainer<Users, MethodNode> {

            func insert(_ response: KvHttpResponseImplementationProtocol, for configuration: DispatchConfiguration) {
                configuration.forEachHttpMethod { method in
                    child(for: method).insert(response, for: configuration)
                }
            }


            func insert(_ attributes: Attributes, for configuration: DispatchConfiguration) {
                configuration.forEachHttpMethod { method in
                    child(for: method).insert(attributes, for: configuration)
                }
            }


            private func child(for key: Key?) -> Child { child(for: key, fabric: Child.init) }

        }


        // MARK: .Users

        private class Users : DictionaryContainer<Hosts, UserNode> {

            func insert(_ response: KvHttpResponseImplementationProtocol, for configuration: DispatchConfiguration) {
                configuration.forEachUser { user in
                    child(for: user).insert(response, for: configuration)
                }
            }


            func insert(_ attributes: Attributes, for configuration: DispatchConfiguration) {
                configuration.forEachUser { user in
                    child(for: user).insert(attributes, for: configuration)
                }
            }


            private func child(for key: Key?) -> Child { child(for: key, fabric: Child.init) }

        }


        // MARK: .Hosts

        private class Hosts : DictionaryContainer<Paths, HostDictionaryNode> {

            func insert(_ response: KvHttpResponseImplementationProtocol, for configuration: DispatchConfiguration) {
                configuration.forEachHost { host in
                    child(for: host).insert(response, for: configuration)
                }
            }


            func insert(_ attributes: Attributes, for configuration: DispatchConfiguration) {
                configuration.forEachHost { host in
                    child(for: host).insert(attributes, for: configuration)
                }
            }


            private func child(for key: Key?) -> Child { child(for: key, fabric: Child.init) }

        }


        // MARK: .Paths

        private class Paths : HierarchyContainer<Responses, PathNode> {

            func insert(_ response: KvHttpResponseImplementationProtocol, for configuration: DispatchConfiguration) {
                child(for: configuration.path.components).insert(response)
            }


            func insert(_ attributes: Attributes, for configuration: DispatchConfiguration) {
                child(for: configuration.path.components).insert(attributes)
            }


            private func child<Keys>(for keys: Keys) -> Child
            where Keys : Collection, Keys.Element == Key
            {
                child(for: keys, fabric: Child.init(pathLevel:))
            }

        }


        // MARK: .Responses

        private class Responses : Container {

            init(pathLevel: Int) {
                self.pathLevel = pathLevel
            }


            private let pathLevel: Int

            private var responses: [KvHttpResponseImplementationProtocol] = .init()

            private var attributes: Attributes?


            // MARK: Operations

            func insert<R>(_ response: R) where R : KvHttpResponseImplementationProtocol {
                responses.append(response)
            }


            func insert(_ attributes: Attributes) {
                Attributes.merge(addition: attributes, into: &self.attributes)
            }


            func build() -> Node? {
                ResponseNode(with: responses, pathLevel: pathLevel, attributes: attributes)
            }

        }

    }

}



// MARK: .Node

fileprivate protocol KvHttpResponseDispatcherNode {

    func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: KvHttpResponseDispatcher.RequestProcessorResult)

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


    static func key(from requestContext: KvHttpRequestContext) -> Key?

    /// - Returns: Array of secondary keys. It's used when no response is provided for the primary key.
    ///
    /// E.g. GET HTTP method is secondary for HEAD method due to server should return the same headers for HEAD and GET methods.
    /// So it's good to use the same pesponse for both methods.
    static func secondaryKeys(for primaryKey: Key) -> [Key]

}


extension KvHttpResponseDispatcherDictionaryNode {

    func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: KvHttpResponseDispatcher.RequestProcessorResult) {
        guard let primaryKey = Self.key(from: requestContext) else { return }

        let subnode = (self.subnode(for: primaryKey)
                       ?? Self.secondaryKeys(for: primaryKey).lazy.compactMap({ secondaryKey in self.subnode(for: secondaryKey) }).first)

        subnode?.accumulateRequestProcessors(for: requestContext, into: accumulator)
    }

}


extension KvHttpResponseDispatcher {

    fileprivate typealias DictionaryNode = KvHttpResponseDispatcherDictionaryNode

}



// MARK: .HierarchyNode

fileprivate protocol KvHttpResponseDispatcherHierarchyNode : KvHttpResponseDispatcherNode {

    associatedtype Key : Hashable
    associatedtype Keys : Sequence where Keys.Element == Key

    associatedtype Subnode : KvHttpResponseDispatcherNode


    init(childNodes: [Key : Self], subnode: Subnode?)


    static func keys(from requestContext: KvHttpRequestContext) -> Keys

}


extension KvHttpResponseDispatcher {

    fileprivate typealias HierarchyNode = KvHttpResponseDispatcherHierarchyNode

}



// MARK: Nodes

extension KvHttpResponseDispatcher {

    // MARK: .DictionaryContainer

    fileprivate class DictionaryContainer<Key : Hashable> : DictionaryContainerProtocol {

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

        func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: RequestProcessorResult) {
            wildcardSubnode.accumulateRequestProcessors(for: requestContext, into: accumulator)
            specificSubnodes.accumulateRequestProcessors(for: requestContext, into: accumulator)
        }

    }



    // MARK: .RootNode

    fileprivate class RootNode : Node {

        init?(subnode: Node?, redirections: RedirectionNode?) {
            guard subnode != nil || redirections != nil else { return nil }

            self.subnode = subnode
            self.redirections = redirections
        }


        private let subnode: Node?
        private let redirections: RedirectionNode?


        // MARK: : Node

        func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: KvHttpResponseDispatcher.RequestProcessorResult) {
            subnode?.accumulateRequestProcessors(for: requestContext, into: accumulator)

            if case .notFound = accumulator.match {
                redirections?.accumulateRequestProcessors(for: requestContext, into: accumulator)
            }
        }
    }



    // MARK: .RedirectionNode

    class RedirectionNode : Node {

        init?(hosts: [String : String]) {
            self.requestProcessors = hosts.reduce(into: .init(), { partialResult, redirection in
                guard let encodedSource = Scheme.encodedHost(redirection.key)
                else { return KvDebug.pause("Warning: unable to encode source of redirection «\(redirection.key)» to «\(redirection.value)»") }

                partialResult[encodedSource] = RedirectionRequestProcessor(targetHost: redirection.value)
            })

            guard !requestProcessors.isEmpty else { return nil }
        }


        /// Keys are encoded host names.
        private let requestProcessors: [String : KvHttpRequestProcessorProtocol]


        // MARK: : Node

        func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: KvHttpResponseDispatcher.RequestProcessorResult) {
            guard let requestProcessor = requestContext.urlComponents.host.flatMap({ requestProcessors[$0] }) else { return }

            accumulator.collect(.unambiguous(requestProcessor))
        }


        // MARK: .RedirectionRequestProcessor

        private class RedirectionRequestProcessor : KvHttpRequestProcessorProtocol {

            init(targetHost: String) {
                self.targetHost = targetHost
            }


            private let targetHost: String


            // MARK: : KvHttpRequestProcessorProtocol

            func process(_ requestHeaders: KvHttpServer.RequestHeaders) -> Result<Void, Error> { .success(()) }


            func makeRequestHandler(_ requestContext: KvHttpRequestContext) -> Result<KvHttpRequestHandler, Error> {
                let targetURL: URL
                do {
                    var targetComponents = requestContext.urlComponents
                    targetComponents.host = targetHost

                    guard let url = targetComponents.url else { return .failure(KvHttpResponseError.invalidRedirectionTarget(targetComponents)) }

                    targetURL = url
                }

                return .success(KvHttpHeadOnlyRequestHandler(response: .found(location: targetURL)))
            }


            func onIncident(_ incident: KvHttpIncident, _ context: KvHttpRequestContext) -> KvHttpResponseContent? { nil }

        }

    }



    // MARK: .MethodNode

    fileprivate class MethodNode : DictionaryContainer<KvHttpMethod>, DictionaryNode {

        static func key(from requestContext: KvHttpRequestContext) -> Key? {
            requestContext.method
        }


        static func secondaryKeys(for primaryKey: Key) -> [Key] {
            switch primaryKey {
            case .head:
                return [ .get ]

            default:
                return [ ]
            }
        }

    }



    // MARK: .UserNode

    fileprivate class UserNode : DictionaryContainer<String>, DictionaryNode {

        static func key(from requestContext: KvHttpRequestContext) -> String? {
            requestContext.urlComponents.user
        }


        static func secondaryKeys(for primaryKey: Key) -> [Key] { [ ] }

    }



    // MARK: .HostNode

    fileprivate class HostDictionaryNode : DictionaryContainer<String>, DictionaryNode {

        static func key(from requestContext: KvHttpRequestContext) -> String? {
            requestContext.urlComponents.host
        }


        static func secondaryKeys(for primaryKey: Key) -> [Key] { [ ] }

    }



    // MARK: .PathNode

    /// - Note: There is no placeholder paths.
    fileprivate class PathNode : HierarchyNode {

        typealias Key = KvUrlPath.Components.Element
        typealias Subnode = ResponseNode


        required init(childNodes: [Key : PathNode], subnode: Subnode?) {
            self.childNodes = childNodes
            self.subnode = subnode
        }


        private let childNodes: [Key : PathNode]

        private let subnode: Subnode?


        // MARK: : HierarchyNode

        static func keys(from requestContext: KvHttpRequestContext) -> [Key] {
            requestContext.path.components
        }


        // MARK: : Node

        func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: KvHttpResponseDispatcher.RequestProcessorResult) {

            func Process(_ node: PathNode, pathLevel: Int) {
                guard let subnode = node.subnode else { return }

                if let attributes = subnode.attributes {
                    accumulator.collect(attributes, pathLevel: pathLevel)
                }

                subnode.accumulateSubpathRequestProcessors(for: requestContext, into: accumulator)
            }


            var iterator = requestContext.path.components.enumerated().makeIterator()
            var node: PathNode = self

            Process(node, pathLevel: 0)

            while let (pathLevel, component) = iterator.next() {
                guard let child = node.childNodes[component]
                else { return }

                node = child

                Process(node, pathLevel: pathLevel + 1)
            }

            node.subnode?.accumulateRequestProcessors(for: requestContext, into: accumulator)
        }

    }



    // MARK: .ResponseNode

    /// Selects matching response by query.
    fileprivate class ResponseNode : Node {

        let attributes: Attributes?


        init?<S>(with responses: S, pathLevel: Int, attributes: Attributes?)
        where S : Sequence, S.Element == KvHttpResponseImplementationProtocol
        {
            do {
                var finalAccumulator = ElementAccumulator(pathLevel: pathLevel)
                var subpathAccumulator = ElementAccumulator(pathLevel: pathLevel)

                responses.forEach { response in
                    switch response is KvHttpSubpathResponseImplementation {
                    case false:
                        finalAccumulator.insert(response)
                    case true:
                        subpathAccumulator.insert(response)
                    }
                }

                finalSubnode = finalAccumulator.makeSubnode()
                subpathSubnode = subpathAccumulator.makeSubnode()
            }

            guard !(finalSubnode == nil && subpathSubnode == nil && attributes == nil) else { return nil }

            self.attributes = attributes
        }


        let finalSubnode: Node?
        let subpathSubnode: Node?


        // MARK: Operations

        func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: KvHttpResponseDispatcher.RequestProcessorResult) {
            finalSubnode?.accumulateRequestProcessors(for: requestContext, into: accumulator)
        }


        func accumulateSubpathRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: KvHttpResponseDispatcher.RequestProcessorResult) {
            subpathSubnode?.accumulateRequestProcessors(for: requestContext, into: accumulator)
        }


        // MARK: .Element

        private struct Element<QueryParser> {

            typealias ProcessorBlock = (KvHttpResponseContext) -> KvHttpRequestProcessorProtocol?


            let queryParser: QueryParser
            let pathLevel: Int
            let processorBlock: ProcessorBlock


            // MARK: Operations

            func makeProcessor(_ requestContext: KvHttpRequestContext, _ clientCallbacks: KvClientCallbacks?) -> RequestProcessorResult.Match {
                let responseContext = KvHttpResponseContext(
                    subpath: requestContext.path.dropFirst(pathLevel),
                    clientCallbacks: clientCallbacks
                )

                switch processorBlock(responseContext) {
                case .some(let processor):
                    return .unambiguous(processor)
                case .none:
                    return .notFound
                }
            }

        }


        // MARK: .ElementAccumulator

        private struct ElementAccumulator {

            let pathLevel: Int


            init(pathLevel: Int) {
                self.pathLevel = pathLevel
            }


            private var emptyQueryElement: Element<KvEmptyUrlQueryParser>?
            private var entireQueryElements: [Element<KvEntireUrlQueryParser>]?
            private var serialQueryElements: [Element<KvSerialUrlQueryParser>]?


            // MARK: Operations

            mutating func insert(_ response: KvHttpResponseImplementationProtocol) {

                func Append<T>(_ element: T, to array: inout [T]?) {
                    array?.append(element)
                    ?? (array = [ element ])
                }


                let queryParser = response.urlQueryParser

                defer { queryParser.reset() }

                switch queryParser {
                case let queryParser as KvEmptyUrlQueryParser:
                    if emptyQueryElement != nil {
                        KvDebug.pause("Warning: HTTP response for empty URL query was replaced")
                    }
                    emptyQueryElement = .init(queryParser: queryParser, pathLevel: pathLevel, processorBlock: response.makeProcessor)

                case let queryParser as KvEntireUrlQueryParser:
                    Append(.init(queryParser: queryParser, pathLevel: pathLevel, processorBlock: response.makeProcessor), to: &entireQueryElements)

                case let queryParser as KvSerialUrlQueryParser:
                    Append(.init(queryParser: queryParser, pathLevel: pathLevel, processorBlock: response.makeProcessor), to: &serialQueryElements)

                default:
                    KvDebug.pause("Warning: HTTP response for unexpected URL query type was ignored")
                }
            }


            func makeSubnode() -> Node? {

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
                    .init(queryParser: element.queryParser as KvSerialUrlQueryParser, pathLevel: pathLevel, processorBlock: element.processorBlock)
                }


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

                case (.none, .none, .none):
                    return nil

                default:
                    return MixedQueries(serial: Joined(serialQueryElements, emptyQueryElement.map(AsSerial(_:))),
                                        entire: entireQueryElements ?? [ ])
                }
            }

        }


        // MARK: .EmptyQuery

        /// Dedicated node optimized to handle single empty query parser.
        private class EmptyQuery : Node {

            typealias Element = ResponseNode.Element<KvEmptyUrlQueryParser>


            init(_ queryElement: Element) {
                self.queryElement = queryElement
            }


            private let queryElement: Element


            // MARK: : Node

            func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: RequestProcessorResult) {
                guard requestContext.urlComponents.queryItems?.isEmpty != false
                else { return }

                accumulator.collect(queryElement.makeProcessor(requestContext, accumulator.groupAttributes?.clientCallbacks))
            }

        }


        // MARK: .EntireQuery

        /// Dedicated node optimized to handle single custom query parser.
        private class EntireQuery : Node {

            typealias Element = ResponseNode.Element<KvEntireUrlQueryParser>


            init(_ queryElement: Element) {
                self.queryElement = queryElement
            }


            private let queryElement: Element


            // MARK: : Node

            func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: RequestProcessorResult) {
                defer { queryElement.queryParser.reset() }

                guard queryElement.queryParser.parse(requestContext.urlComponents.queryItems) == .complete
                else { return }

                accumulator.collect(queryElement.makeProcessor(requestContext, accumulator.groupAttributes?.clientCallbacks))
            }

        }


        // MARK: .SerialQuery

        /// Dedicated node optimized to handle single serial query parser.
        private class SerialQuery : Node {

            typealias Element = ResponseNode.Element<KvSerialUrlQueryParser>


            init(_ queryElement: Element) {
                self.queryElement = queryElement
            }


            private let queryElement: Element


            // MARK: : Node

            func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: RequestProcessorResult) {

                func Completion() {
                    guard queryParser.status == .complete
                    else { return }

                    accumulator.collect(queryElement.makeProcessor(requestContext, accumulator.groupAttributes?.clientCallbacks))
                }


                let queryParser = queryElement.queryParser

                guard let query = requestContext.urlComponents.queryItems,
                      !query.isEmpty
                else { return Completion() }

                defer { queryParser.reset() }

                for queryItem in query {
                    guard queryParser.parse(queryItem) != .failure
                    else { return }
                }

                Completion()
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

            func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: RequestProcessorResult) {
                let match = Self.withMatchResult(queryElements, in: requestContext) { match in
                    match.flatMap { processorBlock in
                        processorBlock(requestContext, accumulator.groupAttributes?.clientCallbacks)
                    }
                }

                accumulator.collect(match)
            }


            // MARK: Auxiliaries

            /// - Parameter body: It's called with the result anyway, even if there are no candidates or several candidates.
            @inline(__always)
            static func withMatchResult(
                _ elements: [Element],
                in requestContext: KvHttpRequestContext,
                body: (Match<(KvHttpRequestContext, KvClientCallbacks?) -> RequestProcessorResult.Match>) -> RequestProcessorResult.Match
            ) -> RequestProcessorResult.Match {
                let query = requestContext.urlComponents.queryItems

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

            func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: RequestProcessorResult) {
                let match = Self.withMatchResult(queryElements, in: requestContext) { match in
                    match.flatMap { processorBlock in
                        processorBlock(requestContext, accumulator.groupAttributes?.clientCallbacks)
                    }
                }

                accumulator.collect(match)
            }


            // MARK: : Auxiliaries

            /// - Parameter body: It's called with the result anyway, even if there are no candidates or several candidates.
            @inline(__always)
            static func withMatchResult(_ elements: [Element],
                                        in requestContext: KvHttpRequestContext,
                                        body: (Match<(KvHttpRequestContext, KvClientCallbacks?) -> RequestProcessorResult.Match>) -> RequestProcessorResult.Match
            ) -> RequestProcessorResult.Match {
                guard let query = requestContext.urlComponents.queryItems,
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


                func Finalize() -> RequestProcessorResult.Match {
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


        // MARK: .MixedQueries

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

            func accumulateRequestProcessors(for requestContext: KvHttpRequestContext, into accumulator: RequestProcessorResult) {
                let match = SerialQueries.withMatchResult(serialQueryElements, in: requestContext) { match1 in
                    EntireQueries.withMatchResult(entireQueryElements, in: requestContext) { match2 in
                        match1.union(with: match2).flatMap { processorBlock in
                            processorBlock(requestContext, accumulator.groupAttributes?.clientCallbacks)
                        }
                    }
                }

                accumulator.collect(match)
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
