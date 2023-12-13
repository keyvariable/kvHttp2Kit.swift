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
//  KvDirectory.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 15.10.2023.
//

import Foundation

import kvHttpKit



/// A type representing directory response.
///
/// Directories are considered as a hierarchical structure of files relative to the root URL.
///
/// *KvDirectory* provides configurable access control to it's contents.
/// For example, if directory is provided via HTTP then:
/// - files and directories having dot-prefixed names except "/.well-known" are ignored;
/// - contents of status directory (if provided) can't be accessed directly;
/// - if a directory is requested then "index.html" or "index" file is directory is responded if available.
/// See modifiers for details on index file name lists, black and white lists, status directories.
///
/// When directory content is requested via HTTP, server responds on *GET* and *HEAD* methods only.
///
/// Paths to directory contents are constrained to the root URL.
/// *KvDirectory* handles "." and ".." special path components.
/// Path having ".." special path components will never point out of the root.
/// For example "a/../../" is equivalent to the root, "a/../../b.html" is equivalent to "b.html".
///
/// URLs having `hasDirectoryPath` property equal to `true`  can be declared as directory directly:
///
/// ```swift
/// KvGroup("movies") {
///     URL(string: "file:///url/to/movies/")
/// }
/// KvGroup("images") {
///     Bundle.module.resourceURL!.appendingPathComponent("images", isDirectory: true)
/// }
/// ```
///
/// - Note: If a directory response is declared via an URL directly,
///         then "Status" or "status" directory at the url is automatically selected as the HTTP status directory.
///
/// By default content type of files in directory and status files is infered using all avilable methods.
/// Use ``contentType(by:)`` modifier to select particular inference methods or disable the inference.
///
/// - SeeAlso: ``KvFiles``.
public struct KvDirectory : KvResponse {

    @usableFromInline
    var configuration: Configuration



    @usableFromInline
    init(configuration: Configuration) {
        self.configuration = configuration
    }


    /// Initializes a directory response having root at given URL. See ``KvDirectory`` for details.
    @inlinable
    public init(at rootURL: URL) {
        self.init(configuration: .init(rootURL: rootURL))
    }


    /// Initializes a directory response having root at given path. See ``KvDirectory`` for details.
    @inlinable
    public init?(atPath rootPath: String) {
        self.init(at: URL(fileURLWithPath: rootPath, isDirectory: true))
    }



    // MARK: Modifiers

    /// This modifier appends common list of index file names.
    ///
    /// When a directory file system item is requested, protocol-specific and common lists of index file names are used to select a file in requested directory.
    /// So content of index file is responded if available.
    ///
    /// Initially common index file list is ``Defaults/indexNames-swift.type.property``.
    /// First application of this modifier clears the default value even if modifier's argument list is empty.
    @inlinable
    public func indexFileNames(_ fileNames: String...) -> Self { modified {
        $0.insert(indexFileNames: fileNames)
    } }

    /// This modifier appends common list of index file names.
    ///
    /// See ``indexFileNames(_:)-1m07g`` for details.
    @inlinable
    public func indexFileNames<S>(_ fileNames: S) -> Self
    where S : Sequence, S.Element == String
    { modified {
        $0.insert(indexFileNames: fileNames)
    } }


    /// This modifier appends directory's black list.
    ///
    /// If a path is in black list then it and it's contents are recursively ignored.
    ///
    /// Black list contains paths relative to the root of the directory.
    /// Paths containing ".." special component are constrained to the directory's root URL.
    /// For example "a/../../" is equivalent to the root, "a/../../b.html" is equivalent to "b.html".
    ///
    /// Initially black list is ``Defaults/blackList-swift.type.property``.
    /// First application of this modifier clears the default value even if modifier's argument list is empty.
    ///
    /// - SeeAlso: ``whiteList(_:)-43l0i``.
    @inlinable
    public func blackList(_ paths: String...) -> Self { blackList(paths.lazy.map(KvUrlPath.init(path:))) }

    /// This modifier appends directory's black list.
    ///
    /// See ``blackList(_:)-5xwjb`` for details.
    @inlinable
    public func blackList<S>(_ paths: S) -> Self
    where S : Sequence, S.Element == String
    { blackList(paths.lazy.map(KvUrlPath.init(stringLiteral:))) }

    /// This modifier appends directory's black list.
    ///
    /// See ``blackList(_:)-5xwjb`` for details.
    @inlinable
    public func blackList(_ paths: KvUrlPath...) -> Self { modified {
        $0.insert(blackListItems: paths.lazy.map(KvUrlSubpath.init(_:)))
    } }

    /// This modifier appends directory's black list.
    ///
    /// See ``blackList(_:)-5xwjb`` for details.
    @inlinable
    public func blackList<S>(_ paths: S) -> Self
    where S : Sequence, S.Element == KvUrlPath
    { modified {
        $0.insert(blackListItems: paths.lazy.map(KvUrlSubpath.init(_:)))
    } }


    /// This modifier appends directory's white list.
    ///
    /// By default an item in directory is ignored it it's name starts with dot character.
    /// All subitems of ignored item are also rejected by default.
    /// If an item is in white list then it is visible.
    ///
    /// If an item or it's ancestor item is in black list then the item is ignored anyway.
    ///
    /// For example let white list contains single path ".a/b".
    /// Then ".a", ".a/a", ".a/b/.c" are ignored, but ".a/b", ".a/b/c" are responded.
    ///
    /// White list contains paths relative to the root of the directory.
    /// Paths containing ".." special component are constrained to the directory's root URL.
    /// For example "a/../../" is equivalent to the root, "a/../../b.html" is equivalent to "b.html".
    ///
    /// Initially white list is ``Defaults/whiteList-swift.type.property``.
    /// First application of this modifier clears the default value even if modifier's argument list is empty.
    ///
    /// - SeeAlso: ``blackList(_:)-5xwjb``.
    @inlinable
    public func whiteList(_ paths: String...) -> Self { whiteList(paths.lazy.map(KvUrlPath.init(path:))) }

    /// This modifier appends directory's white list.
    ///
    /// See ``whiteList(_:)-6y9nd`` for details.
    @inlinable
    public func whiteList<S>(_ paths: S) -> Self
    where S : Sequence, S.Element == String
    { whiteList(paths.lazy.map(KvUrlPath.init(stringLiteral:))) }

    /// This modifier appends directory's white list.
    ///
    /// See ``whiteList(_:)-6y9nd`` for details.
    @inlinable
    public func whiteList(_ paths: KvUrlPath...) -> Self { modified {
        $0.insert(whiteListItems: paths.lazy.map(KvUrlSubpath.init(_:)))
    } }

    /// This modifier appends directory's white list.
    ///
    /// See ``whiteList(_:)-6y9nd`` for details.
    @inlinable
    public func whiteList<S>(_ paths: S) -> Self
    where S : Sequence, S.Element == KvUrlPath
    { modified {
        $0.insert(whiteListItems: paths.lazy.map(KvUrlSubpath.init(_:)))
    } }


    /// This modifier changes the way content type of files in the directory and status files is infered.
    ///
    /// Default value is `.allMethods`.
    @inlinable
    public func contentType(by contentTypeInference: KvHttpResponseContent.ContentTypeInference) -> Self { modified {
        $0.contentTypeInference = contentTypeInference
    } }


    /// This modifier appends HTTP protocol-specific list of index file names.
    ///
    /// When a directory file system item is requested, protocol-specific and common lists of index file names are used to select a file in requested directory.
    /// So content of index file is responded if available.
    /// Otherwise an HTTP incident with 404 status is thrown.
    ///
    /// Initially HTTP protocol-specific index file list is ``Defaults/httpIndexNames-swift.type.property``.
    /// First application of this modifier clears the default value even if modifier's argument list is empty.
    @inlinable
    public func httpIndexFileNames(_ fileNames: String...) -> Self { modified {
        $0.insert(httpIndexFileNames: fileNames)
    } }

    /// This modifier appends HTTP protocol-specific list of index file names.
    ///
    /// See ``httpIndexFileNames(_:)-8bf80`` for details.
    @inlinable
    public func httpIndexFileNames<S>(_ fileNames: S) -> Self
    where S : Sequence, S.Element == String
    { modified {
        $0.insert(httpIndexFileNames: fileNames)
    } }


    /// This modifier changes URL to status directory with files to respond when HTTP incident occurs.
    ///
    /// When status directory is provided and an HTTP incident occurs, then HTTP server responds with contents of file in the status directory.
    /// By default *KvDirectory* responds with content of file named "\(statusCode).html".
    /// Custom status file name callback can be provided via ``httpStatusFileName(_:)`` modifier.
    ///
    /// Status directory can be at any URL inside or outside of the directory's root.
    /// If the status URL is inside the directory then it is automatically added to the directory's black list and status files can't be requested directly.
    ///
    /// By default status directory is not set.
    @inlinable
    public func httpStatusDirectory(url: URL) -> Self { modified {
        $0.httpStatusDirectoryURL = url
    } }

    /// This modifier changes URL to status directory with files to respond when HTTP incident occurs.
    ///
    /// It's an overload of ``httpStatusDirectory(url:)`` taking string argument with path relative to the directory's root.
    @inlinable
    public func httpStatusDirectory(pathComponent: String) -> Self { modified {
        $0.httpStatusDirectoryURL = $0.rootURL.appendingPathComponent(pathComponent)
    } }


    /// This modifier provides custom mapping from HTTP statuses to file names.
    ///
    /// See ``httpStatusDirectory(url:)`` for details.
    @inlinable
    public func httpStatusFileName(_ block: @escaping (KvHttpStatus) -> String?) -> Self { modified {
        $0.httpStatusFileNameBlock = block
    } }



    // MARK: .Defaults

    public struct Defaults {

        /// Default content of common index file list.
        /// See ``KvDirectory/indexFileNames(_:)-1m07g`` for details.
        public static let indexNames: [String]? = [ "index" ]

        /// Default content of black list.
        /// See ``KvDirectory/blackList(_:)-5xwjb`` for details.
        public static let blackList: Set<KvUrlSubpath>? = nil
        /// Default content of white list.
        /// See ``KvDirectory/whiteList(_:)-6y9nd`` for details.
        public static let whiteList: Set<KvUrlSubpath>? = [ ".well-known" ]

        /// Default content of HTTP protocol-specific index file list.
        /// See ``KvDirectory/httpIndexFileNames(_:)-8bf80`` for details.
        public static let httpIndexNames: [String]? = [ "index.html" ]


        private init() { }

    }



    // MARK: .Configuration

    @usableFromInline
    struct Configuration {

        @usableFromInline
        var rootURL: URL

        @usableFromInline
        var indexFileNames: [String]?

        @usableFromInline
        var blackList: Set<KvUrlSubpath>?
        @usableFromInline
        var whiteList: Set<KvUrlSubpath>?

        @usableFromInline
        var contentTypeInference: KvHttpResponseContent.ContentTypeInference = .allMethods

        @usableFromInline
        var httpIndexFileNames: [String]?

        @usableFromInline
        var httpStatusDirectoryURL: URL?
        @usableFromInline
        var httpStatusFileNameBlock: ((KvHttpStatus) -> String?)?


        @usableFromInline
        init(rootURL: URL,
             indexFileNames: [String]? = nil,
             blackList: Set<KvUrlSubpath>? = nil,
             whiteList: Set<KvUrlSubpath>? = nil,
             httpIndexFileNames: [String]? = nil,
             httpStatusDirectoryURL: URL? = nil,
             httpStatusFileNameBlock: ((KvHttpStatus) -> String?)? = nil
        ) {
            self.rootURL = rootURL
            self.indexFileNames = indexFileNames
            self.httpIndexFileNames = httpIndexFileNames
            self.httpStatusDirectoryURL = httpStatusDirectoryURL
            self.httpStatusFileNameBlock = httpStatusFileNameBlock
            self.blackList = blackList
            self.whiteList = whiteList
        }


        // MARK: Operations

        @usableFromInline
        mutating func insert<S>(indexFileNames fileNames: S) where S : Sequence, S.Element == String {
            self.indexFileNames?.append(contentsOf: fileNames) ?? (self.indexFileNames = .init(fileNames))
        }


        @usableFromInline
        mutating func insert<S>(blackListItems: S) where S : Sequence, S.Element == KvUrlSubpath {
            self.blackList?.formUnion(blackListItems) ?? (self.blackList = .init(blackListItems))
        }


        @usableFromInline
        mutating func insert<S>(whiteListItems: S) where S : Sequence, S.Element == KvUrlSubpath {
            self.whiteList?.formUnion(whiteListItems) ?? (self.whiteList = .init(whiteListItems))
        }


        @usableFromInline
        mutating func insert<S>(httpIndexFileNames fileNames: S) where S : Sequence, S.Element == String {
            self.httpIndexFileNames?.append(contentsOf: fileNames) ?? (self.httpIndexFileNames = .init(fileNames))
        }

    }



    // MARK: : KvResponse

    public var body: KvNeverResponse { Body() }

}


// MARK: : KvResponseInternalProtocol

extension KvDirectory : KvResponseInternalProtocol {

    func insert<A>(to accumulator: A) where A : KvHttpResponseAccumulator {
        let rootURL = configuration.rootURL.absoluteURL
        let isRootLocal = rootURL.isFileURL

        let contentTypeInference = configuration.contentTypeInference

        let indexFileNames: [String] = Array([
            configuration.httpIndexFileNames ?? Defaults.httpIndexNames,
            configuration.indexFileNames ?? Defaults.indexNames
        ].lazy.compactMap({ $0 }).joined())

        let httpStatusDirectoryURL = configuration.httpStatusDirectoryURL?.standardized
        let httpStatusFileNameBlock = configuration.httpStatusFileNameBlock ?? { "\($0.rawValue).html" }

        let accessList: AccessList = {
            var accessList = AccessList(black: configuration.blackList ?? Defaults.blackList,
                                        white: configuration.whiteList ?? Defaults.whiteList)

            // Insertion of the status directory when it's inside the root directory.
            if let statusDirectoryURL = httpStatusDirectoryURL?.absoluteURL,
               statusDirectoryURL.scheme == rootURL.scheme
            {
                let rootComponents = KvUrlPath(path: rootURL.path).standardized
                let statusComponents = KvUrlPath(path: statusDirectoryURL.path).standardized

                if statusComponents.starts(with: rootComponents) {
                    accessList.insertBlackSubpath(.init(statusComponents.dropFirst(rootComponents.components.count)))
                }
            }

            return accessList
        }()

        let httpRepresentation =
        KvGroup(httpMethods: .get) {
            KvHttpResponse.with
                .subpathFlatMap { subpath in
                    guard let url = KvDirectory.resolvedSubpath(subpath, rootURL: rootURL, accessList: accessList)
                    else { return .rejected }

                    return (try? KvResolvedFileURL(for: url, isLocal: isRootLocal, indexNames: indexFileNames)).map { .accepted($0) } ?? .rejected
                }
                .content { input in try .file(at: input.subpath, contentTypeBy: contentTypeInference) }
        }
        .onHttpIncident { incident, _ in
            let status = incident.defaultStatus

            return httpStatusFileNameBlock(status)
                .flatMap { fileName in httpStatusDirectoryURL?.appendingPathComponent(fileName) }
                .flatMap { fileURL in
                    try? .status(status).file(at: fileURL, contentTypeBy: contentTypeInference)
                }
        }

        httpRepresentation.resolvedGroup.insertResponses(to: accumulator)
    }

}


// MARK: Auxiliaries

extension KvDirectory {

    // TODO: Apply consuming, borrowing, consume, copy keywords in Swift 5.9.
    @inline(__always)
    @usableFromInline
    internal func modified(_ block: (inout Configuration) -> Void) -> Self {
        var copy = self
        block(&copy.configuration)
        return copy
    }


    /// - Note: It's internal to be visible for unit-tests.
    internal static func resolvedSubpath(_ subpath: KvUrlSubpath, rootURL: URL, accessList: AccessList) -> URL? {
        let subpath = subpath.standardized

        guard let permission = accessList.permission(for: subpath) else { return nil }

        var url = rootURL

        if let prefix = permission.whitePrefix {
            url.appendPathComponent(prefix.joined)
        }

        for component in permission.rest.components {
            guard component.first != "." else { return nil }

            url.appendPathComponent(.init(component))
        }

        return url
    }


    // MARK: .AccessList

    /// - Note: It's internal due to unit-test requirements.
    struct AccessList {

        typealias PathComponent = KvUrlPath.Components.Element


        init<B, W>(black: B?, white: W?)
        where B : Sequence, B.Element == KvUrlSubpath,
              W : Sequence, W.Element == KvUrlSubpath
        {
            black?.forEach { insertBlackSubpath($0) }
            white?.forEach { insertWhiteSubpath($0) }
        }


        private var root: Node?


        // MARK: .Level

        private class Level {

            private var nodes: [PathComponent : Node] = .init()


            // MARK: Operations

            subscript(component: PathComponent) -> Node? { nodes[component] }


            func withNode<T>(for component: PathComponent, _ body: (inout Node?) -> T) -> T {
                body(&nodes[component])
            }

        }


        // MARK: .Node

        private enum Node {

            /// Black nodes block anything inside so they don't need hierarchy.
            case black
            case white(Level)
            /// Container for a level of the tree.
            case container(Level)

        }


        // MARK: Access

        /// - Returns: White prefix and the rest when given *subpath* is permitted. Otherwise `nil` is returned.
        func permission(for subpath: KvUrlSubpath) -> Permission? {
            guard let root = root else { return .init(subpath) }

            var iterator = subpath.components.enumerated().makeIterator()

            var node = root
            var nodeLevel = 0

            var whiteCount: Int?

            while let (levelIndex, component) = iterator.next() {
                let level: Level

                switch node {
                case .black:
                    return nil
                case .container(let nodeLevel):
                    level = nodeLevel
                case .white(let nodeLevel):
                    whiteCount = levelIndex
                    level = nodeLevel
                }

                guard let next = level[component] else { return .init(subpath, whiteCount: whiteCount) }

                node = next
                nodeLevel += 1
            }

            switch node {
            case .black:
                return nil
            case .container(_):
                return .init(subpath, whiteCount: whiteCount)
            case .white(_):
                return .init(subpath, whiteCount: nodeLevel)
            }
        }


        // MARK: .Permission

        struct Permission {

            /// Prefix of the subpath matching a white subpath.
            let whitePrefix: KvUrlSubpath?
            /// The white prefix joined with *rest* match the subpath.
            let rest: KvUrlSubpath


            init(whitePrefix: KvUrlSubpath?, rest: KvUrlSubpath) {
                self.whitePrefix = whitePrefix
                self.rest = rest
            }


            init(_ subpath: KvUrlSubpath) { self.init(whitePrefix: nil, rest: subpath) }


            init(_ subpath: KvUrlSubpath, whiteCount: Int?) {
                if let whiteCount = whiteCount, whiteCount > 0 {
                    self.init(whitePrefix: subpath.prefix(whiteCount), rest: subpath.dropFirst(whiteCount))
                }
                else {
                    self.init(subpath)
                }
            }

        }


        // MARK: Mutation

        mutating func insertBlackSubpath(_ subpath: KvUrlSubpath) {
            withNode(at: subpath.standardized) {
                // Priority of black state precedes priority of white state.
                $0 = .black
            }
        }


        mutating func insertWhiteSubpath(_ subpath: KvUrlSubpath) {
            withNode(at: subpath.standardized) {
                switch $0 {
                case .none:
                    $0 = .white(.init())
                case .black:
                    break   // Priority of black state precedes priority of white state.
                case .container(let level):
                    $0 = .white(level)
                case .white(_):
                    break   // Nothing to do
                }
            }
        }


        private mutating func withNode(at subpath: KvUrlSubpath, _ body: (inout Node?) -> Void) {
            var iterator = subpath.components.makeIterator()

            guard var prev = iterator.next() else { return body(&root) }

            var node: Node
            switch root {
            case .some(let root):
                node = root
            case .none:
                node = .container(.init())
                root = node
            }

            while let next = iterator.next() {
                switch node {
                case .black:
                    return
                case .container(let level), .white(let level):
                    node = level.withNode(for: prev) {
                        guard $0 == nil else { return $0! }

                        let node = Node.container(.init())
                        $0 = node
                        return node
                    }
                }

                prev = next
            }

            switch node {
            case .black:
                return
            case .container(let level), .white(let level):
                level.withNode(for: prev, body)
            }
        }

    }

}
