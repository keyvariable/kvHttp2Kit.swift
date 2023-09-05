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
//  KvHttpResponseProvider.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 30.05.2023.
//

import Foundation

import kvKit
import NIOHTTP1



public struct KvHttpResponseProvider {

    public typealias Status = HTTPResponseStatus

    public typealias HeaderCallback = (inout HTTPHeaders) -> Void

    public typealias BodyCallback = (UnsafeMutableRawBufferPointer) -> Result<Int, Error>


    /// HTTP response status code.
    @usableFromInline
    var status: Status

    /// An optional callback providing custom headers.
    @usableFromInline
    var customHeaderCallback: HeaderCallback?

    /// It's used to write body fragments to the clients buffer.
    ///
    /// The callback is passed with pointer to the buffer and the buffer size in bytes.
    ///
    /// The callback returns number of actually written bytes or an error as a standard *Result*.
    @usableFromInline
    var bodyCallback: BodyCallback?

    /// Optional value for `Content-Type` HTTP header in response. If `nil` then the header is not provided in response.
    @usableFromInline
    var contentType: ContentType?
    /// Optional value for `Content-Length` HTTP header in response. If `nil` then the header is not provided in response.
    @usableFromInline
    var contentLength: UInt64?


    /// Memberwise initializer.
    @usableFromInline
    init(status: Status = .ok,
         customHeaderCallback: HeaderCallback? = nil,
         contentType: ContentType? = nil,
         contentLength: UInt64? = nil,
         bodyCallback: BodyCallback? = nil
    ) {
        self.status = status
        self.customHeaderCallback = customHeaderCallback
        self.contentType = contentType
        self.contentLength = contentLength
        self.bodyCallback = bodyCallback
    }


    // MARK: .ContentType

    /// Enumeration of some auxiliary content types and case for arbitrary values.
    public enum ContentType {

        case application(Application)

        case image(Image)

        /// Explicitely provided MIME-type and semicolon-separated options.
        case raw(String, options: String?)

        case text(Text)


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
            public var components: (mimeType: String, options: String?) {
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
            public var components: (mimeType: String, options: String?) {
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
            public var components: (mimeType: String, options: String?) {
                switch self {
                case .css:
                    return ("text/css", options: nil)
                case .csv:
                    return ("text/csv", options: nil)
                case .html:
                    return ("text/html", options: nil)
                case .markdown:
                    return ("text/markdown", options: nil)
                case .plain:
                    return ("text/plain", options: nil)
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
        public var components: (mimeType: String, options: String?) {
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

    }


    // MARK: Auxiliaries

    @usableFromInline
    static func streamBodyCallback(_ stream: InputStream) -> BodyCallback {
        if stream.streamStatus == .notOpen {
            stream.open()
        }

        return { buffer in
            let bytesRead = stream.read(buffer.baseAddress!.assumingMemoryBound(to: UInt8.self), maxLength: buffer.count)

            guard bytesRead >= 0 else { return .failure(KvError("Failed to read from response body stream: code = \(bytesRead), streamError = nil")) }

            return .success(bytesRead)
        }
    }


    @usableFromInline
    static func dataBodyCallback<D>(_ data: D) -> BodyCallback
    where D : DataProtocol, D.Index == Int
    {
        var offset = data.startIndex

        return { buffer in
            let bytesToCopy = min(data.endIndex - offset, buffer.count)
            let range = offset ..< (offset + bytesToCopy)

            data.copyBytes(to: buffer, from: range)

            offset = range.upperBound
            return .success(bytesToCopy)
        }
    }


    @inline(__always)
    @usableFromInline
    func map(_ transform: (inout Self) -> Void) -> Self {
        var copy = self
        transform(&copy)
        return copy
    }

}



// MARK: Fabrics

extension KvHttpResponseProvider {

    /// - Returns: An instance where body is provided via *callback*, `contentType` is `.application(.octetStream)`, *status* is `.ok`.
    @inlinable
    public static func bodyCallback(_ callback: @escaping BodyCallback) -> Self {
        Self(contentType: .application(.octetStream))
            .bodyCallback(callback)
    }


    /// - Returns: An instance where *status* is equal to given value.
    @inlinable
    public static func status(_ status: Status) -> Self { .init(status: status) }

}



// MARK: Dedicated Body Fabrics

extension KvHttpResponseProvider {

    /// - Returns: An instance where body is taken from provided *bytes*, `contentType` is `.application(.octetStream)`, `contentLength` is equal to number of bytes in *data*, *status* is `.ok`.
    @inlinable
    public static func binary<D>(_ bytes: D) -> Self
    where D : DataProtocol, D.Index == Int
    {
        Self().binary(bytes)
    }


    /// - Returns: An instance where body is taken from provided *stream*, `contentType` is `.application(.octetStream)`, *status* is `.ok`.
    ///
    /// - Note: Note that `contentLength` is used as read limit if provided.
    @inlinable
    public static func binary(_ stream: InputStream) -> Self { Self().binary(stream) }


    /// - Returns: An instance where body is JSON representation of given *payload*, `contentType` is `.application(.json)`, `contentLength` is equal to number of bytes in the representation, *status* is `.ok`.
    @inlinable
    public static func json<T : Encodable>(_ payload: T) throws -> Self { try Self().json(payload) }


    /// - Returns: An instance where body is UTF8 representation of given *string*, `contentType` is `.text(.plain)`, `contentLength` is equal to number of bytes in the representation, *status* is `.ok`.
    @inlinable
    public static func string<S: StringProtocol>(_ string: S) -> Self { Self().string(string) }

}



// MARK: Dedicated Status Fabrics

extension KvHttpResponseProvider {

    /// - Returns: An instance where *status* is `.ok`.
    @inlinable public static var ok: Self { .init(status: .ok) }
    /// - Returns: An instance where *status* is `.created`.
    @inlinable public static var created: Self { .init(status: .created) }
    /// - Returns: An instance where *status* is `.accepted`.
    @inlinable public static var accepted: Self { .init(status: .accepted) }
    /// - Returns: An instance where *status* is `.nonAuthoritativeInformation`.
    @inlinable public static var nonAuthoritativeInformation: Self { .init(status: .nonAuthoritativeInformation) }
    /// - Returns: An instance where *status* is `.noContent`.
    @inlinable public static var noContent: Self { .init(status: .noContent) }
    /// - Returns: An instance where *status* is `.resetContent`.
    @inlinable public static var resetContent: Self { .init(status: .resetContent) }
    /// - Returns: An instance where *status* is `.partialContent`.
    @inlinable public static var partialContent: Self { .init(status: .partialContent) }
    /// - Returns: An instance where *status* is `.multiStatus`.
    @inlinable public static var multiStatus: Self { .init(status: .multiStatus) }
    /// - Returns: An instance where *status* is `.alreadyReported`.
    @inlinable public static var alreadyReported: Self { .init(status: .alreadyReported) }
    /// - Returns: An instance where *status* is `.imUsed`.
    @inlinable public static var imUsed: Self { .init(status: .imUsed) }
    /// - Returns: An instance where *status* is `.multipleChoices`.
    @inlinable public static var multipleChoices: Self { .init(status: .multipleChoices) }
    /// - Returns: An instance where *status* is `.movedPermanently`.
    @inlinable public static var movedPermanently: Self { .init(status: .movedPermanently) }
    /// - Returns: An instance where *status* is `.found`.
    @inlinable public static var found: Self { .init(status: .found) }
    /// - Returns: An instance where *status* is `.seeOther`.
    @inlinable public static var seeOther: Self { .init(status: .seeOther) }
    /// - Returns: An instance where *status* is `.notModified`.
    @inlinable public static var notModified: Self { .init(status: .notModified) }
    /// - Returns: An instance where *status* is `.useProxy`.
    @inlinable public static var useProxy: Self { .init(status: .useProxy) }
    /// - Returns: An instance where *status* is `.temporaryRedirect`.
    @inlinable public static var temporaryRedirect: Self { .init(status: .temporaryRedirect) }
    /// - Returns: An instance where *status* is `.permanentRedirect`.
    @inlinable public static var permanentRedirect: Self { .init(status: .permanentRedirect) }
    /// - Returns: An instance where *status* is `.badRequest`.
    @inlinable public static var badRequest: Self { .init(status: .badRequest) }
    /// - Returns: An instance where *status* is `.unauthorized`.
    @inlinable public static var unauthorized: Self { .init(status: .unauthorized) }
    /// - Returns: An instance where *status* is `.paymentRequired`.
    @inlinable public static var paymentRequired: Self { .init(status: .paymentRequired) }
    /// - Returns: An instance where *status* is `.forbidden`.
    @inlinable public static var forbidden: Self { .init(status: .forbidden) }
    /// - Returns: An instance where *status* is `.notFound`.
    @inlinable public static var notFound: Self { .init(status: .notFound) }
    /// - Returns: An instance where *status* is `.methodNotAllowed`.
    @inlinable public static var methodNotAllowed: Self { .init(status: .methodNotAllowed) }
    /// - Returns: An instance where *status* is `.notAcceptable`.
    @inlinable public static var notAcceptable: Self { .init(status: .notAcceptable) }
    /// - Returns: An instance where *status* is `.proxyAuthenticationRequired`.
    @inlinable public static var proxyAuthenticationRequired: Self { .init(status: .proxyAuthenticationRequired) }
    /// - Returns: An instance where *status* is `.requestTimeout`.
    @inlinable public static var requestTimeout: Self { .init(status: .requestTimeout) }
    /// - Returns: An instance where *status* is `.conflict`.
    @inlinable public static var conflict: Self { .init(status: .conflict) }
    /// - Returns: An instance where *status* is `.gone`.
    @inlinable public static var gone: Self { .init(status: .gone) }
    /// - Returns: An instance where *status* is `.lengthRequired`.
    @inlinable public static var lengthRequired: Self { .init(status: .lengthRequired) }
    /// - Returns: An instance where *status* is `.preconditionFailed`.
    @inlinable public static var preconditionFailed: Self { .init(status: .preconditionFailed) }
    /// - Returns: An instance where *status* is `.payloadTooLarge`.
    @inlinable public static var payloadTooLarge: Self { .init(status: .payloadTooLarge) }
    /// - Returns: An instance where *status* is `.uriTooLong`.
    @inlinable public static var uriTooLong: Self { .init(status: .uriTooLong) }
    /// - Returns: An instance where *status* is `.unsupportedMediaType`.
    @inlinable public static var unsupportedMediaType: Self { .init(status: .unsupportedMediaType) }
    /// - Returns: An instance where *status* is `.rangeNotSatisfiable`.
    @inlinable public static var rangeNotSatisfiable: Self { .init(status: .rangeNotSatisfiable) }
    /// - Returns: An instance where *status* is `.expectationFailed`.
    @inlinable public static var expectationFailed: Self { .init(status: .expectationFailed) }
    /// - Returns: An instance where *status* is `.imATeapot`.
    @inlinable public static var imATeapot: Self { .init(status: .imATeapot) }
    /// - Returns: An instance where *status* is `.misdirectedRequest`.
    @inlinable public static var misdirectedRequest: Self { .init(status: .misdirectedRequest) }
    /// - Returns: An instance where *status* is `.unprocessableEntity`.
    @inlinable public static var unprocessableEntity: Self { .init(status: .unprocessableEntity) }
    /// - Returns: An instance where *status* is `.locked`.
    @inlinable public static var locked: Self { .init(status: .locked) }
    /// - Returns: An instance where *status* is `.failedDependency`.
    @inlinable public static var failedDependency: Self { .init(status: .failedDependency) }
    /// - Returns: An instance where *status* is `.upgradeRequired`.
    @inlinable public static var upgradeRequired: Self { .init(status: .upgradeRequired) }
    /// - Returns: An instance where *status* is `.preconditionRequired`.
    @inlinable public static var preconditionRequired: Self { .init(status: .preconditionRequired) }
    /// - Returns: An instance where *status* is `.tooManyRequests`.
    @inlinable public static var tooManyRequests: Self { .init(status: .tooManyRequests) }
    /// - Returns: An instance where *status* is `.requestHeaderFieldsTooLarge`.
    @inlinable public static var requestHeaderFieldsTooLarge: Self { .init(status: .requestHeaderFieldsTooLarge) }
    /// - Returns: An instance where *status* is `.unavailableForLegalReasons`.
    @inlinable public static var unavailableForLegalReasons: Self { .init(status: .unavailableForLegalReasons) }
    /// - Returns: An instance where *status* is `.internalServerError`.
    @inlinable public static var internalServerError: Self { .init(status: .internalServerError) }
    /// - Returns: An instance where *status* is `.notImplemented`.
    @inlinable public static var notImplemented: Self { .init(status: .notImplemented) }
    /// - Returns: An instance where *status* is `.badGateway`.
    @inlinable public static var badGateway: Self { .init(status: .badGateway) }
    /// - Returns: An instance where *status* is `.serviceUnavailable`.
    @inlinable public static var serviceUnavailable: Self { .init(status: .serviceUnavailable) }
    /// - Returns: An instance where *status* is `.gatewayTimeout`.
    @inlinable public static var gatewayTimeout: Self { .init(status: .gatewayTimeout) }
    /// - Returns: An instance where *status* is `.httpVersionNotSupported`.
    @inlinable public static var httpVersionNotSupported: Self { .init(status: .httpVersionNotSupported) }
    /// - Returns: An instance where *status* is `.variantAlsoNegotiates`.
    @inlinable public static var variantAlsoNegotiates: Self { .init(status: .variantAlsoNegotiates) }
    /// - Returns: An instance where *status* is `.insufficientStorage`.
    @inlinable public static var insufficientStorage: Self { .init(status: .insufficientStorage) }
    /// - Returns: An instance where *status* is `.loopDetected`.
    @inlinable public static var loopDetected: Self { .init(status: .loopDetected) }
    /// - Returns: An instance where *status* is `.notExtended`.
    @inlinable public static var notExtended: Self { .init(status: .notExtended) }
    /// - Returns: An instance where *status* is `.networkAuthenticationRequired`.
    @inlinable public static var networkAuthenticationRequired: Self { .init(status: .networkAuthenticationRequired) }

}



// MARK: Modifiers

extension KvHttpResponseProvider {

    /// - Returns: A copy where body is provided via *callback*.
    ///
    /// - Note: `contentType`, `contentLength` and other properties are not changed.
    @inlinable
    public func bodyCallback(_ callback: @escaping BodyCallback) -> Self { map { $0.bodyCallback = callback } }


    /// - Returns: A copy where *status* is changed to given value.
    @inlinable
    public func status(_ status: Status) -> Self { map { $0.status = status } }


    /// - Returns:A copy where given block is appended to chain of callbacks to be invoked before HTTP headers are sent to client.
    @inlinable
    public func headers(_ callback: @escaping HeaderCallback) -> Self { map {
        switch $0.customHeaderCallback {
        case .none:
            $0.customHeaderCallback = callback
        case .some(let customHeaderCallback):
            $0.customHeaderCallback = { headers in
                customHeaderCallback(&headers)
                callback(&headers)
            }
        }
    } }


    /// - Returns: A copy where `contentType` is changed to given *value*.
    @inlinable
    public func contentType(_ value: ContentType) -> Self { map { $0.contentType = value } }


    /// - Returns: A copy where `contentLength` is changed to given *value*.
    @inlinable
    public func contentLength(_ value: UInt64) -> Self { map { $0.contentLength = value } }


    /// Convenient method converting given *value* from any *BinaryInteger* value to *UInt64*.
    ///
    /// - Returns: A copy where `contentLength` is changed to given *value*.
    @inlinable
    public func contentLength<T>(_ value: T) -> Self where T : BinaryInteger { contentLength(numericCast(value) as UInt64) }

}



// MARK: Dedicated Body Modifiers

extension KvHttpResponseProvider {

    /// - Returns: A copy where body is taken from provided *bytes*, missing `contentType` is changed to `.application(.octetStream)`, missing `contentLength` is changed to number of bytes in *data*.
    @inlinable
    public func binary<D>(_ bytes: D) -> Self
    where D : DataProtocol, D.Index == Int
    {
        map {
            $0.bodyCallback = Self.dataBodyCallback(bytes)
            $0.contentType = $0.contentType ?? .application(.octetStream)
            $0.contentLength = $0.contentLength ?? numericCast(bytes.count)
        }
    }


    /// - Returns: A copy where body is taken from provided *stream*, missing `contentType` is changed to `.application(.octetStream)`.
    ///
    /// - Note: Note that `contentLength` is used as read limit if provided.
    ///
    /// - Note: `contentLength` and other properties are not changed.
    @inlinable
    public func binary(_ stream: InputStream) -> Self {
        map {
            $0.bodyCallback = Self.streamBodyCallback(stream)
            $0.contentType = $0.contentType ?? .application(.octetStream)
        }
    }


    /// - Returns: A copy where body is JSON representation of given *payload*, missing `contentType` is changed to `.application(.json)`, missing `contentLength` is changed to number of bytes in the representation.
    @inlinable
    public func json<T : Encodable>(_ payload: T) throws -> Self {
        let data = try JSONEncoder().encode(payload)

        return map {
            $0.bodyCallback = Self.dataBodyCallback(data)
            $0.contentType = $0.contentType ?? .application(.json)
            $0.contentLength = $0.contentLength ?? numericCast(data.count)
        }
    }


    /// - Returns: A copy where body is UTF8 representation of given *string*, missing`contentType` is changed to `.text(.plain)`, missing `contentLength` is equal to number of bytes in the representation.
    @inlinable
    public func string<S: StringProtocol>(_ string: S) -> Self {
        let data = string.data(using: .utf8)!

        return map {
            $0.bodyCallback = Self.dataBodyCallback(data)
            $0.contentType = $0.contentType ?? .text(.plain)
            $0.contentLength = $0.contentLength ?? numericCast(data.count)
        }
    }

}



// MARK: Dedicated Status Modifiers

extension KvHttpResponseProvider {

    /// - Returns: A copy where *status* is chaned to`.ok`.
    @inlinable public var ok: Self { map { $0.status = .ok } }
    /// - Returns: A copy where *status* is chaned to`.created`.
    @inlinable public var created: Self { map { $0.status = .created } }
    /// - Returns: A copy where *status* is chaned to`.accepted`.
    @inlinable public var accepted: Self { map { $0.status = .accepted } }
    /// - Returns: A copy where *status* is chaned to`.nonAuthoritativeInformation`.
    @inlinable public var nonAuthoritativeInformation: Self { map { $0.status = .nonAuthoritativeInformation } }
    /// - Returns: A copy where *status* is chaned to`.noContent`.
    @inlinable public var noContent: Self { map { $0.status = .noContent } }
    /// - Returns: A copy where *status* is chaned to`.resetContent`.
    @inlinable public var resetContent: Self { map { $0.status = .resetContent } }
    /// - Returns: A copy where *status* is chaned to`.partialContent`.
    @inlinable public var partialContent: Self { map { $0.status = .partialContent } }
    /// - Returns: A copy where *status* is chaned to`.multiStatus`.
    @inlinable public var multiStatus: Self { map { $0.status = .multiStatus } }
    /// - Returns: A copy where *status* is chaned to`.alreadyReported`.
    @inlinable public var alreadyReported: Self { map { $0.status = .alreadyReported } }
    /// - Returns: A copy where *status* is chaned to`.imUsed`.
    @inlinable public var imUsed: Self { map { $0.status = .imUsed } }
    /// - Returns: A copy where *status* is chaned to`.multipleChoices`.
    @inlinable public var multipleChoices: Self { map { $0.status = .multipleChoices } }
    /// - Returns: A copy where *status* is chaned to`.movedPermanently`.
    @inlinable public var movedPermanently: Self { map { $0.status = .movedPermanently } }
    /// - Returns: A copy where *status* is chaned to`.found`.
    @inlinable public var found: Self { map { $0.status = .found } }
    /// - Returns: A copy where *status* is chaned to`.seeOther`.
    @inlinable public var seeOther: Self { map { $0.status = .seeOther } }
    /// - Returns: A copy where *status* is chaned to`.notModified`.
    @inlinable public var notModified: Self { map { $0.status = .notModified } }
    /// - Returns: A copy where *status* is chaned to`.useProxy`.
    @inlinable public var useProxy: Self { map { $0.status = .useProxy } }
    /// - Returns: A copy where *status* is chaned to`.temporaryRedirect`.
    @inlinable public var temporaryRedirect: Self { map { $0.status = .temporaryRedirect } }
    /// - Returns: A copy where *status* is chaned to`.permanentRedirect`.
    @inlinable public var permanentRedirect: Self { map { $0.status = .permanentRedirect } }
    /// - Returns: A copy where *status* is chaned to`.badRequest`.
    @inlinable public var badRequest: Self { map { $0.status = .badRequest } }
    /// - Returns: A copy where *status* is chaned to`.unauthorized`.
    @inlinable public var unauthorized: Self { map { $0.status = .unauthorized } }
    /// - Returns: A copy where *status* is chaned to`.paymentRequired`.
    @inlinable public var paymentRequired: Self { map { $0.status = .paymentRequired } }
    /// - Returns: A copy where *status* is chaned to`.forbidden`.
    @inlinable public var forbidden: Self { map { $0.status = .forbidden } }
    /// - Returns: A copy where *status* is chaned to`.notFound`.
    @inlinable public var notFound: Self { map { $0.status = .notFound } }
    /// - Returns: A copy where *status* is chaned to`.methodNotAllowed`.
    @inlinable public var methodNotAllowed: Self { map { $0.status = .methodNotAllowed } }
    /// - Returns: A copy where *status* is chaned to`.notAcceptable`.
    @inlinable public var notAcceptable: Self { map { $0.status = .notAcceptable } }
    /// - Returns: A copy where *status* is chaned to`.proxyAuthenticationRequired`.
    @inlinable public var proxyAuthenticationRequired: Self { map { $0.status = .proxyAuthenticationRequired } }
    /// - Returns: A copy where *status* is chaned to`.requestTimeout`.
    @inlinable public var requestTimeout: Self { map { $0.status = .requestTimeout } }
    /// - Returns: A copy where *status* is chaned to`.conflict`.
    @inlinable public var conflict: Self { map { $0.status = .conflict } }
    /// - Returns: A copy where *status* is chaned to`.gone`.
    @inlinable public var gone: Self { map { $0.status = .gone } }
    /// - Returns: A copy where *status* is chaned to`.lengthRequired`.
    @inlinable public var lengthRequired: Self { map { $0.status = .lengthRequired } }
    /// - Returns: A copy where *status* is chaned to`.preconditionFailed`.
    @inlinable public var preconditionFailed: Self { map { $0.status = .preconditionFailed } }
    /// - Returns: A copy where *status* is chaned to`.payloadTooLarge`.
    @inlinable public var payloadTooLarge: Self { map { $0.status = .payloadTooLarge } }
    /// - Returns: A copy where *status* is chaned to`.uriTooLong`.
    @inlinable public var uriTooLong: Self { map { $0.status = .uriTooLong } }
    /// - Returns: A copy where *status* is chaned to`.unsupportedMediaType`.
    @inlinable public var unsupportedMediaType: Self { map { $0.status = .unsupportedMediaType } }
    /// - Returns: A copy where *status* is chaned to`.rangeNotSatisfiable`.
    @inlinable public var rangeNotSatisfiable: Self { map { $0.status = .rangeNotSatisfiable } }
    /// - Returns: A copy where *status* is chaned to`.expectationFailed`.
    @inlinable public var expectationFailed: Self { map { $0.status = .expectationFailed } }
    /// - Returns: A copy where *status* is chaned to`.imATeapot`.
    @inlinable public var imATeapot: Self { map { $0.status = .imATeapot } }
    /// - Returns: A copy where *status* is chaned to`.misdirectedRequest`.
    @inlinable public var misdirectedRequest: Self { map { $0.status = .misdirectedRequest } }
    /// - Returns: A copy where *status* is chaned to`.unprocessableEntity`.
    @inlinable public var unprocessableEntity: Self { map { $0.status = .unprocessableEntity } }
    /// - Returns: A copy where *status* is chaned to`.locked`.
    @inlinable public var locked: Self { map { $0.status = .locked } }
    /// - Returns: A copy where *status* is chaned to`.failedDependency`.
    @inlinable public var failedDependency: Self { map { $0.status = .failedDependency } }
    /// - Returns: A copy where *status* is chaned to`.upgradeRequired`.
    @inlinable public var upgradeRequired: Self { map { $0.status = .upgradeRequired } }
    /// - Returns: A copy where *status* is chaned to`.preconditionRequired`.
    @inlinable public var preconditionRequired: Self { map { $0.status = .preconditionRequired } }
    /// - Returns: A copy where *status* is chaned to`.tooManyRequests`.
    @inlinable public var tooManyRequests: Self { map { $0.status = .tooManyRequests } }
    /// - Returns: A copy where *status* is chaned to`.requestHeaderFieldsTooLarge`.
    @inlinable public var requestHeaderFieldsTooLarge: Self { map { $0.status = .requestHeaderFieldsTooLarge } }
    /// - Returns: A copy where *status* is chaned to`.unavailableForLegalReasons`.
    @inlinable public var unavailableForLegalReasons: Self { map { $0.status = .unavailableForLegalReasons } }
    /// - Returns: A copy where *status* is chaned to`.internalServerError`.
    @inlinable public var internalServerError: Self { map { $0.status = .internalServerError } }
    /// - Returns: A copy where *status* is chaned to`.notImplemented`.
    @inlinable public var notImplemented: Self { map { $0.status = .notImplemented } }
    /// - Returns: A copy where *status* is chaned to`.badGateway`.
    @inlinable public var badGateway: Self { map { $0.status = .badGateway } }
    /// - Returns: A copy where *status* is chaned to`.serviceUnavailable`.
    @inlinable public var serviceUnavailable: Self { map { $0.status = .serviceUnavailable } }
    /// - Returns: A copy where *status* is chaned to`.gatewayTimeout`.
    @inlinable public var gatewayTimeout: Self { map { $0.status = .gatewayTimeout } }
    /// - Returns: A copy where *status* is chaned to`.httpVersionNotSupported`.
    @inlinable public var httpVersionNotSupported: Self { map { $0.status = .httpVersionNotSupported } }
    /// - Returns: A copy where *status* is chaned to`.variantAlsoNegotiates`.
    @inlinable public var variantAlsoNegotiates: Self { map { $0.status = .variantAlsoNegotiates } }
    /// - Returns: A copy where *status* is chaned to`.insufficientStorage`.
    @inlinable public var insufficientStorage: Self { map { $0.status = .insufficientStorage } }
    /// - Returns: A copy where *status* is chaned to`.loopDetected`.
    @inlinable public var loopDetected: Self { map { $0.status = .loopDetected } }
    /// - Returns: A copy where *status* is chaned to`.notExtended`.
    @inlinable public var notExtended: Self { map { $0.status = .notExtended } }
    /// - Returns: A copy where *status* is chaned to`.networkAuthenticationRequired`.
    @inlinable public var networkAuthenticationRequired: Self { map { $0.status = .networkAuthenticationRequired } }

}
