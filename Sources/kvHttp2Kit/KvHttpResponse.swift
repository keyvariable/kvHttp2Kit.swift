//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2021 Svyatoslav Popov.
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
//  KvHttpResponse.swift
//  kvHttp2Kit
//
//  Created by Svyatoslav Popov on 30.05.2023.
//

import Foundation

import kvKit
import NIOHTTP1



public struct KvHttpResponse {

    public typealias Status = HTTPResponseStatus


    /// HTTP responce status code.
    public var status: Status
    /// Optional responce content.
    public var content: Content?


    /// Memberwise initializer.
    @inlinable
    public init(status: Status = .ok, content: Content? = nil) {
        self.status = status
        self.content = content
    }


    // MARK: .Content

    public struct Content {

        public typealias HeaderCallback = (inout HTTPHeaders) -> Void

        public typealias BodyCallback = (UnsafeMutableRawBufferPointer) -> Result<Int, Error>


        /// Optional value for `Content-Type` HTTP header in responce. If `nil` then the header is not provided in responce.
        public var type: ContentType?
        /// Optional value for `Content-Length` HTTP header in responce. If `nil` then the header is not provided in responce.
        public var length: UInt64?

        /// An optional callback providing custom headers.
        public var customHeaderCallback: HeaderCallback?

        /// It's used to write body fragments to the clients buffer.
        ///
        /// The callback is passed with pointer to the buffer and the buffer size in bytes.
        ///
        /// The callback returns number of actually writtedn bytes or an error as a standard *Result*.
        public var bodyCallback: BodyCallback


        /// Memberwise initializer.
        ///
        /// - Parameter type: Optional value for `Content-Type` HTTP header in responce. If `nil` then the header is not provided in responce. Default value is `.binary`.
        /// - Parameter length: Optional value for `Content-Length` HTTP header in responce. If `nil` then the header is not provided in responce.
        /// - Parameter customHeaderCallback: An optional callback providing custom headers.
        /// - Parameter bodyCallback: Callback writting next segment of the body to given buffer. See ``bodyCallback`` property.
        @inlinable
        public init(type: ContentType? = .binary, length: UInt64? = nil, customHeaderCallback: HeaderCallback? = nil, bodyCallback: @escaping BodyCallback) {
            self.type = type
            self.length = length
            self.customHeaderCallback = customHeaderCallback
            self.bodyCallback = bodyCallback
        }


        /// Memberwise initializer.
        ///
        /// - Parameter type: Optional value for `Content-Type` HTTP header in responce. If `nil` then the header is not provided in responce. Default value is `.binary`.
        /// - Parameter length: Optional value for `Content-Length` HTTP header in responce. If `nil` then the header is not provided in responce.
        /// - Parameter bodyStream: Sream the HTTP responce body data is taken from. Note that `contentLength` is used as read limit if provided.
        /// - Parameter customHeaderCallback: An optional callback providing custom headers.
        @inlinable
        public init(type: ContentType? = .binary, length: UInt64? = nil, bodyStream: InputStream, customHeaderCallback: HeaderCallback? = nil) {
            if bodyStream.streamStatus == .notOpen {
                bodyStream.open()
            }

            self.init(type: type, length: length, customHeaderCallback: customHeaderCallback) { buffer in
                let bytesRead = bodyStream.read(buffer.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: buffer.count)

                guard bytesRead >= 0 else { return .failure(KvError("Failed to read from response body stream: code = \(bytesRead), streamError = nil")) }

                return .success(bytesRead)
            }
        }


        /// Initializes an instance where *.bodyStream* takes bytes from given *data* object and *.length* is equal to number of bytes in *data*.
        ///
        /// - Parameter type: Default value is `.binary`.
        /// - Parameter customHeaderCallback: An optional callback providing custom headers.
        @inlinable
        public init<D>(type: ContentType? = .binary, data: D, customHeaderCallback: HeaderCallback? = nil)
        where D : DataProtocol, D.Index == Int
        {
            var offset = data.startIndex

            self.init(type: type, length: numericCast(data.count), customHeaderCallback: customHeaderCallback) { buffer in
                let bytesToCopy = min(data.endIndex - offset, buffer.count)
                let range = offset ..< (offset + bytesToCopy)

                data.copyBytes(to: buffer, from: range)

                offset = range.upperBound
                return .success(bytesToCopy)
            }
        }


        /// Initializes an instance where *.bodyStream* takes bytes from UTF8 representation of given *string* and *.length* is equal to number of bytes in the representation.
        ///
        /// - Parameter type: Default value is `.plainText`.
        /// - Parameter customHeaderCallback: An optional callback providing custom headers.
        @inlinable
        public init(type: ContentType? = .plainText, string: String, customHeaderCallback: HeaderCallback? = nil) {
            self.init(type: type, data: string.data(using: .utf8)!, customHeaderCallback: customHeaderCallback)
        }


        /// Initializes an instance with appropriate *.type* where *.bodyStream* takes bytes from JSON representation of given *payload* object and *.length* is equal to number of bytes in the representation.
        ///
        /// - Parameter type: Default value is `.json`.
        /// - Parameter customHeaderCallback: An optional callback providing custom headers.
        @inlinable
        public init<T : Encodable>(type: ContentType? = .json, jsonPayload: T, customHeaderCallback: HeaderCallback? = nil) throws {
            self.init(type: .json, data: try JSONEncoder().encode(jsonPayload), customHeaderCallback: customHeaderCallback)
        }

    }


    // MARK: .ContentType

    /// Enumeration of some auxiliary content types and case for arbitrary values.
    public enum ContentType {

        case binary
        case json
        case html
        case plainText
        /// Explicitely provided MIME-type and semicolon-separated options.
        case raw(String, options: String?)


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
        public var components: (mimeType: String, options: String?) {
            switch self {
            case .binary:
                return ("application/octet-stream", options: nil)
            case .json:
                return ("application/json", options: "charset=utf-8")
            case .html:
                return ("text/html", options: nil)
            case .plainText:
                return ("text/plain", options: "charset=utf-8")
            case let .raw(value, options):
                return (value, options)
            }
        }

    }

}
