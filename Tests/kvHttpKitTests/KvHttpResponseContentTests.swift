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
//  KvHttpResponseContentTests.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 13.12.2023.
//

import XCTest

@testable import kvHttpKit



final class KvHttpResponseContentTests : XCTestCase {

    // MARK: - testFileContentTypeInference()

    func testFileContentTypeInference() throws {

        func Assert(_ response: KvHttpResponseContent, expectedContentType: KvHttpContentType?) {
            XCTAssertEqual(response.contentType, expectedContentType)
        }

        Assert(try .file(at: Bundle.module.resourceURL!.appendingPathComponent("sample.txt"), contentTypeBy: .allMethods),
               expectedContentType: .text(.plain))
        Assert(try .file(resource: "index", extension: "html", subdirectory: "html", bundle: .module, contentTypeBy: .allMethods),
               expectedContentType: .text(.html))
        Assert(try .file(resource: "index", subdirectory: "html/a", bundle: .module, contentTypeBy: .allMethods),
               expectedContentType: nil)

        Assert(try .ok.file(at: Bundle.module.resourceURL!.appendingPathComponent("sample.txt"), contentTypeBy: .allMethods),
               expectedContentType: .text(.plain))
        Assert(try .ok.file(resource: "index", extension: "html", subdirectory: "html", bundle: .module, contentTypeBy: .allMethods),
               expectedContentType: .text(.html))
    }

}
