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
//  KvResolvedFileUrlTests.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 31.10.2023.
//

import XCTest

@testable import kvHttpKit



final class KvResolvedFileUrlTests : XCTestCase {

    // MARK: - testUrlResolvation()

    func testUrlResolvation() {
        typealias ResolvedURL = KvResolvedFileURL
        typealias FileError = ResolvedURL.FileError

        func Assert(bundlePath: String,
                    onSuccess: (ResolvedURL, URL) -> Void = { XCTFail("URL: \($1), result: \($0)") },
                    onFailure: (Error, URL) -> Void = { XCTFail("URL: \($1), error: \($0)") }
        ) {
            let url = Bundle.module.resourceURL!.appendingPathComponent(bundlePath)

            do { onSuccess(try ResolvedURL(for: url, indexNames: [ "index.html", "index" ]), url) }
            catch { onFailure(error, url) }
        }

        func Assert(bundlePath: String, expecting: (URL) -> ResolvedURL) {
            Assert(bundlePath: bundlePath, onSuccess: { XCTAssertEqual($0, expecting($1), "URL: \($1)") })
        }

        Assert(bundlePath: "sample.txt", expecting: { .init(resolved: $0, isLocal: true) })
        Assert(bundlePath: "missing_file", onFailure: { error, url in
            guard case FileError.fileDoesNotExist(url) = error
            else { return XCTFail("URL: \(url), result \(error) is not equal to expected \(FileError.fileDoesNotExist(url))") }
        })

        Assert(bundlePath: "html", expecting: { .init(resolved: $0.appendingPathComponent("index.html"), isLocal: true) })
        Assert(bundlePath: "html/a", expecting: { .init(resolved: $0.appendingPathComponent("index"), isLocal: true) })
        Assert(bundlePath: "html/a/b", onFailure: { error, url in
            guard case FileError.unableToFindIndexFile(directoryURL: url) = error
            else { return XCTFail("URL: \(url), result \(error) is not equal to expected \(FileError.unableToFindIndexFile(directoryURL: url))") }
        })
    }

}
