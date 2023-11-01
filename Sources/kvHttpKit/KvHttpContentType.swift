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
//  KvHttpContentType.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 31.10.2023.
//

/// Enumeration of some auxiliary content types and case for arbitrary values.
public enum KvHttpContentType {

    case application(Application)
    case image(Image)
    case text(Text)

    /// Explicitly provided MIME-type and semicolon-separated options.
    case raw(String, options: String?)


    // MARK: .Application

    public enum Application {

        case gzip
        case javascript
        case json
        case octetStream
        case pdf
        case postscript
        /// [TeX](https://wikipedia.org/wiki/TeX)
        case tex
        case xml
        case xmlDTD
        case zip


        @inlinable
        public var components: Components {
            switch self {
            case .gzip:
                return ("application/gzip", options: nil)
            case .javascript:
                return ("application/javascript", options: nil)
            case .json:
                return ("application/json", options: nil)
            case .octetStream:
                return ("application/octet-stream", options: nil)
            case .pdf:
                return ("application/pdf", options: nil)
            case .postscript:
                return ("application/postscript", options: nil)
            case .tex:
                return ("application/x-tex", options: nil)
            case .xml:
                return ("application/xml", options: nil)
            case .xmlDTD:
                return ("application/xml-dtd", options: nil)
            case .zip:
                return ("application/zip", options: nil)
            }
        }

    }


    // MARK: .Image

    public enum Image {

        case gif
        case jpeg
        case png
        case svg_xml
        case tiff
        case webp


        @inlinable
        public var components: Components {
            switch self {
            case .gif:
                return ("image/gif", options: nil)
            case .jpeg:
                return ("image/jpeg", options: nil)
            case .png:
                return ("image/png", options: nil)
            case .svg_xml:
                return ("image/svg+xml", options: nil)
            case .tiff:
                return ("image/tiff", options: nil)
            case .webp:
                return ("image/webp", options: nil)
            }
        }

    }


    // MARK: .Text

    public enum Text {

        case css
        case csv
        case html
        case markdown
        case plain


        @inlinable
        public var components: Components {
            switch self {
            case .css:
                return ("text/css", options: nil)
            case .csv:
                return ("text/csv", options: nil)
            case .html:
                return ("text/html", options: "charset=UTF-8")
            case .markdown:
                return ("text/markdown", options: nil)
            case .plain:
                return ("text/plain", options: "charset=UTF-8")
            }
        }

    }


    @inlinable
    public var value: String {
        switch components {
        case (let mimeType, .none):
            return mimeType
        case (let mimeType, .some(let options)):
            return "\(mimeType);\(options)"
        }
    }

    @inlinable
    public var components: Components {
        switch self {
        case .application(let subtype):
            return subtype.components
        case .image(let subtype):
            return subtype.components
        case .text(let subtype):
            return subtype.components
        case let .raw(value, options):
            return (value, options)
        }
    }



    // MARK: .Components

    public typealias Components = (mimeType: String, options: String?)

}
