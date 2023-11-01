//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2021 Svyatoslav Popov (info@keyvar.com).
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
//  KvUrlResolver.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 31.10.2023.
//

import Foundation



public struct KvResolvedFileURL : Equatable {

    public typealias FileError = KvHttpKitError.File



    public let value: URL
    
    public let isLocal: Bool

    

    @usableFromInline
    init(resolved value: URL, isLocal: Bool) {
        self.value = value
        self.isLocal = isLocal
    }


    @inlinable
    public init<IndexNames>(for url: URL, isLocal: Bool? = nil, indexNames: IndexNames = EmptyCollection<String>()) throws
    where IndexNames : Sequence, IndexNames.Element == String
    {
        let isLocal = isLocal ?? url.isFileURL

        self.isLocal = isLocal
        self.value = try {
            guard isLocal else { return url }

            var isDirectory: ObjCBool = false

            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { throw FileError.fileDoesNotExist(url) }
            guard isDirectory.boolValue else { return url }

            do {

                func MakeExistingIndexURL(_ indexName: String) -> URL? {
                    let indexURL = url.appendingPathComponent(indexName)

                    guard FileManager.default.fileExists(atPath: indexURL.path, isDirectory: &isDirectory),
                          !isDirectory.boolValue
                    else { return nil }

                    return indexURL
                }


                var iterator = indexNames.makeIterator()

                do {
                    guard let first = iterator.next() else { throw FileError.isNotAFile(url) }

                    if let indexURL = MakeExistingIndexURL(first) { return indexURL }
                }
                while let next = iterator.next() {
                    if let indexURL = MakeExistingIndexURL(next) { return indexURL }
                }

                throw FileError.unableToFindIndexFile(directoryURL: url)
            }
        }()
    }

}
