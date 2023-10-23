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
//  KvHttpResponseError.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 06.10.2023.
//

import Foundation



/// Errors related to processing of HTTP responses.
public enum KvHttpResponseError : LocalizedError, Equatable {

    /// File at URL doesn't exist.
    case fileDoesNotExist(URL)

    /// Unable to compose target location for a redirection.
    case invalidRedirectionTarget(URLComponents)

    /// Scheme of URL is "file:" but resource at URL is not a file.
    case isNotAFile(URL)

    /// Unable to create input stream for URL.
    case unableToCreateInputStream(URL)

    /// Unable to get URL of a resource in bundle.
    case unableToFindBundleResource(name: String, extension: String?, subdirectory: String?, bundle: Bundle)

    /// Unable to find index file in directory at *directoryURL*.
    case unableToFindIndexFile(directoryURL: URL)

}
