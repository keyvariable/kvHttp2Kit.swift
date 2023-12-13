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

import Foundation



/// Enumeration of some auxiliary content types and case for arbitrary values.
public enum KvHttpContentType : Hashable {

    case application(Application)
    case font(Font)
    case image(Image)
    case text(Text)

    /// Explicitly provided MIME-type and semicolon-separated options.
    case raw(String, options: String?)


    // MARK: .Application

    public enum Application : Hashable {

        case gzip
        // TODO: Delete in 0.11.0.
        @available(*, deprecated, message: "Use KvHttpContentType/Text/javascript")
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
        case zlib


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
            case .zlib:
                return ("application/zlib", options: nil)
            }
        }

    }


    // MARK: .Font

    public enum Font : Hashable {

        case collection
        case otf
        case sfnt
        case ttf
        case woff
        case woff2


        @inlinable
        public var components: Components {
            switch self {
            case .collection:
                return ("font/collection", options: nil)
            case .otf: 
                return ("font/otf", options: nil)
            case .sfnt: 
                return ("font/sfnt", options: nil)
            case .ttf: 
                return ("font/ttf", options: nil)
            case .woff: 
                return ("font/woff", options: nil)
            case .woff2: 
                return ("font/woff2", options: nil)
            }
        }

    }


    // MARK: .Image

    public enum Image : Hashable {

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

    public enum Text : Hashable {

        case css
        case csv
        case html
        case javascript
        case markdown
        case plain
        case vCard


        @inlinable
        public var components: Components {
            switch self {
            case .css:
                return ("text/css", options: nil)
            case .csv:
                return ("text/csv", options: nil)
            case .html:
                return ("text/html", options: "charset=UTF-8")
            case .javascript:
                return ("text/javascript", options: nil)
            case .markdown:
                return ("text/markdown", options: nil)
            case .plain:
                return ("text/plain", options: "charset=UTF-8")
            case .vCard:
                return ("text/vcard", options: "charset=UTF-8")
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
        case .font(let font):
            return font.components
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



    // MARK: Inference

    // TODO: Add inference by leading bytes (magic numbers) of files.
    /// Infers some types by file extension of given URL.
    ///
    /// - SeeAlso: ``from(fileExtension:)``.
    public static func from(_ url: URL) -> KvHttpContentType? {
        from(fileExtension: url.pathExtension)
    }


    /// Infers some types by given file extension.
    ///
    /// - SeeAlso: ``from(_:)``.
    public static func from(fileExtension: String) -> KvHttpContentType? {
        switch fileExtension.lowercased() {
        case "css": .text(.css)
        case "csv": .text(.csv)
        case "dtd": .application(.xmlDTD)
        case "gif": .image(.gif)
        case "gz": .application(.gzip)
        case "htm": .text(.html)
        case "html": .text(.html)
        case "jpeg": .image(.jpeg)
        case "jpg": .image(.jpeg)
        case "js": .text(.javascript)
        case "json": .application(.json)
        case "mjs": .text(.javascript)
        case "markdown": .text(.markdown)
        case "md": .text(.markdown)
        case "mod": .application(.xmlDTD)
        case "otf": .font(.otf)
        case "pdf": .application(.pdf)
        case "png": .image(.png)
        case "tcc": .font(.collection)
        case "tex": .application(.tex)
        case "tiff": .image(.tiff)
        case "ttf": .font(.ttf)
        case "txt": .text(.plain)
        case "svg": .image(.svg_xml)
        case "svgz": .image(.svg_xml)
        case "vcard": .text(.vCard)
        case "vcf": .text(.vCard)
        case "webp": .image(.webp)
        case "woff": .font(.woff)
        case "woff2": .font(.woff2)
        case "xml": .application(.xml)
        case "zip": .application(.zip)
        default: nil
        }
    }

}
