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
//  KvFiles.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 20.10.2023.
//

import Foundation

import kvHttpKit



// MARK: - KvFile

/// Equivalent of `KvFiles(at: url)`.
///
/// - SeeAlso: ``KvFiles``.
@inlinable
public func KvFile(at url: URL) -> KvFiles { .init(at: url) }


/// Equivalent of `KvFiles(atPaths: path)`.
///
/// - SeeAlso: ``KvFiles``.
@inlinable
public func KvFile(atPath path: String) -> KvFiles? { .init(atPaths: path) }


/// Equivalent of `KvFiles(resource:extension:subdirectory:bundle:)`.
///
/// - SeeAlso: ``KvFiles``.
@inlinable
public func KvFile(resource: String, withExtension extension: String? = nil, subdirectory: String? = nil, bundle: Bundle? = nil) -> KvFiles? {
    .init(resource: resource, withExtension: `extension`, subdirectory: subdirectory)
}



// MARK: - KvFiles

/// A type representing response selecting files by last path component.
///
/// When *KvFiles* is declared at some path in the response hierarchy then contents of the files are responded on requests to the path appended with last path components of the file URLs.
/// In example below files located at "/path/to/text.txt" and "/other/path/to/image.png" are responded on requests to "/a/b/text.txt", "/a/b/image.png" respectively:
///
/// ``` swift
/// KvGroup("a/b") {
///     KvFiles(at: URL(string: "file:///path/to/text.txt")!,
///                 URL(string: "file:///other/path/to/image.png")!)
/// }
/// ```
///
/// - Important: Once the files are identified by last path component of URLs then the components should be unique.
///              Otherwise only last entry is responded.
///
/// URLs having `hasDirectoryPath` property equal to `false`  can be declared as files directly:
///
/// ```swift
/// KvGroup("files") {
///     URL(string: "file:///url/to/test.txt")
///     Bundle.urls(forResourcesWithExtension: "png", subdirectory: "images")
/// }
/// ```
///
/// - SeeAlso: ``KvFile(at:)``, ``KvDirectory``.
public struct KvFiles : KvResponse {

    @usableFromInline
    var configuration: Configuration



    @usableFromInline
    init(configuration: Configuration) {
        self.configuration = configuration
    }


    /// Initializes a file response with contents at given URLs. See ``KvFiles`` for details.
    @inlinable
    public init(at urls: URL...) { self.init(at: urls) }


    /// Initializes a file response with contents at given URLs. See ``KvFiles`` for details.
    @inlinable
    public init<URLs>(at urls: URLs) where URLs : Sequence, URLs.Element == URL {
        self.init(configuration: .init(urls: urls))
    }


    /// Initializes a file response with contents at given paths. See ``KvFiles`` for details.
    @inlinable
    public init?(atPaths paths: String...) { self.init(atPaths: paths) }


    /// Initializes a file response with contents at given paths. See ``KvFiles`` for details.
    @inlinable
    public init?<Paths>(atPaths paths: Paths) where Paths : Sequence, Paths.Element == String {
        self.init(at: paths.lazy.map { URL(fileURLWithPath: $0, isDirectory: false) })
    }


    /// Initializes a file response with content of a resource in given bundle. See ``KvFiles`` for details.
    ///
    /// - Parameter bundle: If `nil` is passed then `Bundle.main` is used.
    ///
    /// - SeeAlso: ``KvFiles/init(resourcesWithExtension:subdirectory:bundle:)``
    @inlinable
    public init?(resource: String, withExtension extension: String? = nil, subdirectory: String? = nil, bundle: Bundle? = nil) {
        // - Note: Explicit cast to URL? prevents error on Linux.
        guard let url = ((bundle ?? .main).url(forResource: resource, withExtension: `extension`, subdirectory: subdirectory) as URL?) else { return nil }

        self.init(at: url)
    }


    /// Initializes a file response with resources in given bundle. See ``KvFiles`` for details.
    ///
    /// - Parameter bundle: If `nil` is passed then `Bundle.main` is used.
    ///
    /// - SeeAlso: ``KvFiles/init(resource:withExtension:subdirectory:bundle:)``.
    @inlinable
    public init?(resourcesWithExtension extension: String?, subdirectory: String? = nil, bundle: Bundle? = nil) {
        // - Note: Explicit cast to [URL]? prevents error on Linux.
        guard let urls = ((bundle ?? .main).urls(forResourcesWithExtension: `extension`, subdirectory: subdirectory) as [URL]?) else { return nil }

        self.init(at: urls)
    }



    // MARK: .Configuration

    @usableFromInline
    struct Configuration {

        @usableFromInline
        var urls: [KvUrlPath.Components.Element : URL]


        @usableFromInline
        init<URLs>(urls: URLs) where URLs : Sequence, URLs.Element == URL {
            self.urls = .init(urls.lazy.map { (Substring($0.lastPathComponent), $0) }, uniquingKeysWith: { lhs, rhs in rhs })
        }

    }



    // MARK: : KvResponse

    public var body: KvNeverResponse { Body() }

}


// MARK: : KvResponseInternalProtocol

extension KvFiles : KvResponseInternalProtocol {

    func insert<A>(to accumulator: A) where A : KvHttpResponseAccumulator {
        let urls = configuration.urls

        guard !urls.isEmpty else { return }

        let httpRepresentation =
        KvGroup {
            KvHttpResponse.with
                .subpathFlatMap { subpath -> KvFilterResult<URL> in
                    guard subpath.components.count == 1,
                          let url = urls[subpath.components.first!]
                    else { return .rejected }

                    return .accepted(url)
                }
                .content { input in try .file(at: input.subpath) }
        }
        .httpMethods(.get)

        httpRepresentation.resolvedGroup.insertResponses(to: accumulator)
    }

}
