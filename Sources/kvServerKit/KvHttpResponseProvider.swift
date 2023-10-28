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



// TODO: Apply consuming, borrowing, consume, copy keywords in Swift 5.9.

/// Representation of HTTP responses.
/// It's implemented in declarative way.
/// It provides deferred access to body providers so, for example, the same declaration can be effectively used for both GET and HEAD methods.
///
/// Examples:
///
/// ```swift
/// // Plain text response.
/// .string { "Test response" }
///
/// // Raw byte response.
/// .binary { data }
///     .contentLength(data.count)
///
/// // JSON response.
/// .json { Date() }
///
/// // Status 404 response with content of an HTML file.
/// try .notFound
///     .file(at: htmlFileURL)
///     .contentType(.text(.html))
///
/// // PNG image from bundle.
/// try .file(resource: "logo", extension: "png", subdirectory: "images", bundle: .module)
///     .contentType(.image(.png))
/// ```
public struct KvHttpResponseProvider {

    public typealias HeaderCallback = (inout HTTPHeaders) -> Void

    /// Body callback is used to write body fragments to provided client's buffer.
    /// Body callback returns number of actually written bytes or an error as a standard *Result*.
    public typealias BodyCallback = (UnsafeMutableRawBufferPointer) -> Result<Int, Error>
    /// A block providing an optional ``BodyCallback`` or an error.
    public typealias BodyCallbackProvider = () -> Result<BodyCallback, Error>


    /// HTTP response status code.
    @usableFromInline
    var status: KvHttpStatus

    /// An optional callback providing custom headers.
    @usableFromInline
    var customHeaderCallback: HeaderCallback?

    /// This property is called just before response body is sent to a client.
    /// Also it can be ignored, for example when HTTP method is *HEAD*.
    ///
    /// `Nil` value means that response has no body.
    ///
    /// See ``BodyCallbackProvider`` and ``BodyCallback`` for details.
    @usableFromInline
    var bodyCallbackProvider: BodyCallbackProvider?

    /// Optional value for `Content-Type` HTTP header in response. If `nil` then the header is not provided in response.
    @usableFromInline
    var contentType: ContentType?
    /// Optional value for `Content-Length` HTTP header in response. If `nil` then the header is not provided in response.
    @usableFromInline
    var contentLength: UInt64?

    /// Value for `ETag` response header.
    @usableFromInline
    var entityTag: EntityTag?
    /// Value for `Last-Modified` response header.
    @usableFromInline
    var modificationDate: Date?

    /// Value for `Location` response header.
    @usableFromInline
    var location: URL?

    /// Response options. E.g. disconnection flag.
    @usableFromInline
    var options: Options


    /// Memberwise initializer.
    @usableFromInline
    init(status: KvHttpStatus = .ok,
         customHeaderCallback: HeaderCallback? = nil,
         contentType: ContentType? = nil,
         contentLength: UInt64? = nil,
         entityTag: EntityTag? = nil,
         modificationDate: Date? = nil,
         location: URL? = nil,
         options: Options = [ ],
         bodyCallbackProvider: BodyCallbackProvider? = nil
    ) {
        self.status = status
        self.customHeaderCallback = customHeaderCallback
        self.contentType = contentType
        self.contentLength = contentLength
        self.entityTag = entityTag
        self.modificationDate = modificationDate
        self.location = location
        self.options = options
        self.bodyCallbackProvider = bodyCallbackProvider
    }


    // MARK: .ContentType

    /// Enumeration of some auxiliary content types and case for arbitrary values.
    public enum ContentType {

        case application(Application)

        case image(Image)

        /// Explicitly provided MIME-type and semicolon-separated options.
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


    // MARK: .EntityTag

    /// Representation of HTTP entity tags.
    public struct EntityTag {

        /// Value of entity tag.
        public let value: String
        /// Options of entity tag. E.g. weak state.
        public let options: Options


        @usableFromInline
        init(safeValue: String, options: Options = [ ]) {
            self.value = safeValue
            self.options = options
        }


        /// Initializes entity tag from a raw string.
        ///
        /// - Warning: It's recommended to avoid this initializer due to performance penalty. Initializer validates passed *value*. Use fabrics.
        @inlinable
        public init?(_ value: String, options: Options = [ ]) {
            guard value.allSatisfy({ $0 != "\"" && $0 != "\0" }) else { return nil }

            self.init(safeValue: value, options: options)
        }


        // MARK: Fabrics

        /// - Returns: An instance where value is the result of `data.base64EncodedString()`.
        ///
        /// - SeeAlso: ``base64(withBytesOf:options:)``.
        @inlinable
        public static func base64(_ data: Data, options: Options = [ ]) -> Self {
            .init(safeValue: data.base64EncodedString(), options: options)
        }


        /// - Returns: An instance where value is a Base64 representation of bytes of *x*.
        ///
        /// - Note: `Data.base64EncodedString()` method with default encoding options is used.
        ///
        /// - SeeAlso: ``base64(_:options:)``.
        @inlinable
        public static func base64<T>(withBytesOf x: T, options: Options = [ ]) -> Self {
            .init(safeValue: KvStringKit.base64(withBytesOf: x), options: options)
        }


        /// - Returns: An instance where value is a hexadecimal representation of bytes from *data*.
        @inlinable
        public static func hex<D>(_ data: D, options: Options = [ ]) -> Self
        where D : DataProtocol
        {
            .init(safeValue: KvBase16.encodeAsString(data), options: options)
        }


        /// - Returns: An instance where value is a hexadecimal representation of bytes of *x*.
        @inlinable
        public static func hex<T>(withBytesOf x: T, options: Options = [ ]) -> Self {
            withUnsafeBytes(of: x) {
                .hex($0, options: options)
            }
        }


        /// - Returns: An instance where value is a standard string representation of given UUID.
        @inlinable
        public static func uuid(_ value: UUID, options: Options = [ ]) -> Self {
            .init(safeValue: value.uuidString, options: options)
        }


        // MARK: .Options

        /// Options of entity tags. E.g. weak state.
        public struct Options : OptionSet {

            /// Weak state option constant.
            public static let weak: Self = .init(rawValue: 1 << 0)


            // MARK: : OptionSet

            public let rawValue: UInt

            @inlinable public init(rawValue: UInt) { self.rawValue = rawValue }
        }


        // MARK: Operations

        /// HTTP representation of the receiver.
        var httpRepresentation: String {
            !options.contains(.weak) ? "\"\(value)\"" : "W/\"\(value)\""
        }
    }


    // MARK: .Options

    /// Response options. E.g. disconnection flag.
    public struct Options : OptionSet {

        /// This flag causes connection to be closed just after the response is submitted.
        public static let needsDisconnect = Self(rawValue: 1 << 0)


        // MARK: : OptionSet

        public var rawValue: UInt

        @inlinable public init(rawValue: UInt) { self.rawValue = rawValue }
    }


    // MARK: Auxiliaries

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
    static func streamBodyCallbackProvider(_ url: URL) -> BodyCallbackProvider {
        return {
            guard let stream = InputStream(url: url) else { return .failure(KvHttpResponseError.unableToCreateInputStream(url)) }
            return .success(Self.streamBodyCallback(stream))
        }
    }


    @inline(__always)
    @usableFromInline
    func modified(_ transform: (inout Self) -> Void) -> Self {
        var copy = self
        transform(&copy)
        return copy
    }


    @inline(__always)
    @usableFromInline
    func modified(_ transform: (inout Self) throws -> Void) rethrows -> Self {
        var copy = self
        try transform(&copy)
        return copy
    }


    @inline(__always)
    @usableFromInline
    mutating func appendHeaderCallback(_ callback: @escaping HeaderCallback) {
        switch customHeaderCallback {
        case .none:
            self.customHeaderCallback = callback
        case .some(let customHeaderCallback):
            self.customHeaderCallback = { headers in
                customHeaderCallback(&headers)
                callback(&headers)
            }
        }
    }

}



// MARK: Fabrics

extension KvHttpResponseProvider {

    /// - Returns:  An instance where body is provided via *provider*, *status* is `.ok`.
    ///             See``BodyCallbackProvider`` for details.
    ///
    /// - Important: *Provider* block can be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public static func bodyCallbackProvider(_ provider: @escaping BodyCallbackProvider) -> Self {
        Self().bodyCallbackProvider(provider)
    }


    /// - Returns:  An instance where body is provided via *callback*, *status* is `.ok`.
    ///             See``BodyCallback`` for details.
    ///
    /// - Important: *Callback* block can be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public static func bodyCallback(_ callback: @escaping BodyCallback) -> Self {
        Self().bodyCallback(callback)
    }


    /// - Returns: An instance where *status* is equal to given value.
    @inlinable
    public static func status(_ status: KvHttpStatus) -> Self { .init(status: status) }

}



// MARK: Dedicated Body Fabrics

extension KvHttpResponseProvider {

    /// - Returns: An instance where body is taken from provided *bytes* callback, `contentType` is `.application(.octetStream)`, *status* is `.ok`.
    ///
    /// - Important: *Bytes* block may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public static func binary<D>(_ bytes: @escaping () throws -> D) -> Self
    where D : DataProtocol, D.Index == Int
    {
        Self().binary(bytes)
    }


    /// - Returns: An instance where body is taken from provided *stream*, `contentType` is `.application(.octetStream)`, *status* is `.ok`.
    ///
    /// - Important: *Stream* can may ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public static func binary(_ stream: InputStream) -> Self { Self().binary(stream) }


    /// - Returns: An instance initialized with contents at given *url*.
    ///
    /// Contents of the resulting instance:
    /// - body is content at *url*;
    /// - content length, entity tag and modification date are provided when the scheme is "file:" and the attributes are available.
    ///
    /// - Note: Entity tag is initialized as hexadecimal representation of precise modification date including fractional seconds.
    ///         This implementation prevents double access to file system and monitoring of changes at URL.
    ///
    /// - Important: Contents of file may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public static func file(at url: URL) throws -> Self {
        let resolvedURL = try KvDirectory.ResolvedURL(for: url)

        return try Self().file(at: resolvedURL)
    }


    @inline(__always)
    @usableFromInline
    static func file(at url: KvDirectory.ResolvedURL) throws -> Self { try Self().file(at: url) }


    /// Invokes ``file(at:)-swift.type.method`` fabric with URL of a resource file with given parameters.
    ///``KvHttpResponseError/unableToFindBundleResource(name:extension:subdirectory:bundle:)`` is thrown for missing resources.
    ///
    /// - Parameter bundle: If `nil` is passed then `Bundle.main` is used.
    @inlinable
    public static func file(resource: String, extension: String? = nil, subdirectory: String? = nil, bundle: Bundle? = nil) throws -> Self {
        let bundle = bundle ?? .main

        guard let url = bundle.url(forResource: resource, withExtension: `extension`, subdirectory: subdirectory)
        else { throw KvHttpResponseError.unableToFindBundleResource(name: resource, extension: `extension`, subdirectory: subdirectory, bundle: bundle) }

        return try .file(at: url)
    }


    /// - Returns: An instance where body is JSON representation of given *payload*, `contentType` is `.application(.json)`, *status* is `.ok`.
    ///
    /// - Important: *Payload* block may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public static func json<T : Encodable>(_ payload: @escaping () throws -> T) -> Self { Self().json(payload) }


    /// - Returns: An instance where body is UTF8 representation of given *string*, `contentType` is `.text(.plain)`, *status* is `.ok`.
    ///
    /// - Important: *String* block may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public static func string<S: StringProtocol>(_ string: @escaping () throws -> S) -> Self { Self().string(string) }

}



// MARK: Dedicated Status Fabrics

extension KvHttpResponseProvider {

    // MARK: 2xx

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

    // MARK: 3xx

    /// - Returns: An instance where *status* is `.multipleChoices`.
    @inlinable public static func multipleChoices(preferredLocation: URL? = nil) -> Self { .init(status: .multipleChoices, location: preferredLocation) }
    /// - Returns: An instance where *status* is `.movedPermanently`.
    @inlinable public static func movedPermanently(location: URL?) -> Self { .init(status: .movedPermanently, location: location) }
    /// - Returns: An instance where *status* is `.found`.
    @inlinable public static func found(location: URL?) -> Self { .init(status: .found, location: location) }
    /// - Returns: An instance where *status* is `.seeOther`.
    @inlinable public static func seeOther(location: URL) -> Self { .init(status: .seeOther, location: location) }
    /// - Returns: An instance where *status* is `.notModified`.
    @inlinable public static var notModified: Self { .init(status: .notModified) }
    /// - Returns: An instance where *status* is `.useProxy`.
    @available(*, deprecated, message: "The 305 (Use Proxy) status code has been deprecated due to security concerns. See https://www.rfc-editor.org/rfc/rfc7231.html#appendix-B")
    @inlinable public static var useProxy: Self { .init(status: .useProxy) }
    /// - Returns: An instance where *status* is `.temporaryRedirect`.
    @inlinable public static func temporaryRedirect(location: URL?) -> Self { .init(status: .temporaryRedirect, location: location) }
    /// - Returns: An instance where *status* is `.permanentRedirect`.
    @inlinable public static func permanentRedirect(location: URL?) -> Self { .init(status: .permanentRedirect, location: location) }

    // MARK: 4xx

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

    // MARK: 5xx

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

    /// - Returns: A copy where body is provided via *provider*. See``BodyCallbackProvider`` for details.
    ///
    /// - Note: `contentType`, `contentLength` and other properties are not changed.
    ///
    /// - Important: *Provider* block can be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func bodyCallbackProvider(_ provider: @escaping BodyCallbackProvider) -> Self { modified {
        $0.bodyCallbackProvider = provider
    } }


    /// - Returns: A copy where body is provided via *callback*. See``BodyCallback`` for details.
    ///
    /// - Note: `contentType`, `contentLength` and other properties are not changed.
    ///
    /// - Important: *Callback* block can be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func bodyCallback(_ callback: @escaping BodyCallback) -> Self { bodyCallbackProvider { .success(callback) } }


    /// - Returns: A copy where *status* is changed to given value.
    @inlinable
    public func status(_ status: KvHttpStatus) -> Self { modified { $0.status = status } }


    /// - Returns:A copy where given block is appended to chain of callbacks to be invoked before HTTP headers are sent to client.
    @inlinable
    public func headers(_ callback: @escaping HeaderCallback) -> Self { modified { $0.appendHeaderCallback(callback) } }


    /// - Returns: A copy where `contentType` is changed to given *value*.
    @inlinable
    public func contentType(_ value: ContentType) -> Self { modified { $0.contentType = value } }


    /// - Returns: A copy where `contentLength` is changed to given *value*.
    @inlinable
    public func contentLength(_ value: UInt64) -> Self { modified { $0.contentLength = value } }


    /// Convenient method converting given *value* from any *BinaryInteger* value to *UInt64*.
    ///
    /// - Returns: A copy where `contentLength` is changed to given *value*.
    @inlinable
    public func contentLength<T>(_ value: T) -> Self where T : BinaryInteger { contentLength(numericCast(value) as UInt64) }


    /// - Returns: A copy where entity tag is changed to given *value*.
    ///
    /// Provided value is used as value of `ETag` response header and to process `If-Match` and `If-None-Match` request headers.
    /// For example, response is automatically replaced with 304 (Not Modified) when request contains `If-None-Match` header with the matching value.
    @inlinable
    public func entityTag(_ value: EntityTag) -> Self { modified { $0.entityTag = value } }

    /// - Returns: A copy where modification date is changed to given *value*.
    ///
    /// - Note: It's recommended to prefer ``entityTag(_:)`` instead if possible.
    ///
    /// Provided value is used as value of `Last-Modified` response header and to process `If-Modified-Since` and `If-Unmodified-Since` request headers.
    /// For example, response is automatically replaced with 304 (Not Modified) when request contains `If-Modified-Since` header with a later date.
    @inlinable
    public func modificationDate(_ value: Date) -> Self { modified { $0.modificationDate = value } }


    /// - Returns: A copy where value of `Location` header is changed to given *value*.
    @inlinable
    public func location(_ value: URL) -> Self { modified { $0.location = value } }

}



// MARK: Dedicated Body Modifiers

extension KvHttpResponseProvider {

    /// - Returns: A copy where body is taken from provided *bytes* callback, missing `contentType` is changed to `.application(.octetStream)`.
    ///
    /// - Important: *Bytes* block may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func binary<D>(_ bytes: @escaping () throws -> D) -> Self
    where D : DataProtocol, D.Index == Int
    {
        modified {
            $0.bodyCallbackProvider = { Result {
                let data = try bytes()

                return Self.dataBodyCallback(data)
            } }
            $0.contentType = $0.contentType ?? .application(.octetStream)
        }
    }


    /// - Returns: A copy where body is taken from provided *stream*, missing `contentType` is changed to `.application(.octetStream)`.
    ///
    /// - Important: *Stream* may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func binary(_ stream: InputStream) -> Self {
        modified {
            $0.bodyCallbackProvider = { .success(Self.streamBodyCallback(stream)) }
            $0.contentType = $0.contentType ?? .application(.octetStream)
        }
    }


    /// - Returns: A copy where contents are taken from file at given *url*.
    ///
    /// Following changes are applied:
    /// - body is content at *url*;
    /// - content length, entity tag and modification date are updated when the scheme is "file:" and the attributes are available.
    ///
    /// - Note: Entity tag is initialized as hexadecimal representation of precise modification date including fractional seconds.
    ///         This implementation prevents double access to file system and monitoring of changes at URL.
    ///
    /// - Important: Contents of file may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func file(at url: URL) throws -> Self {
        let resolvedURL = try KvDirectory.ResolvedURL(for: url)

        return try self.file(at: resolvedURL)
    }


    @inline(__always)
    @usableFromInline
    func file(at url: KvDirectory.ResolvedURL) throws -> Self { try modified {
        let (url, isLocal) = (url.value, url.isLocal)

        if isLocal {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

            if let modificationDate = attributes[.modificationDate] as? Date {
                $0.modificationDate = modificationDate
                $0.entityTag = .hex(withBytesOf: modificationDate.timeIntervalSince1970)
            }
            if let size = attributes[.size] as? UInt64 {
                $0.contentLength = size
            }
        }

        $0.bodyCallbackProvider = Self.streamBodyCallbackProvider(url)
    } }


    /// Invokes ``file(at:)-swift.method`` modifier with URL of a resource file with given parameters.
    ///``KvHttpResponseError/unableToFindBundleResource(name:extension:subdirectory:bundle:)`` is thrown for missing resources.
    ///
    /// - Parameter bundle: If `nil` is passed then `Bundle.main` is used.
    @inlinable
    public func file(resource: String, extension: String? = nil, subdirectory: String? = nil, bundle: Bundle? = nil) throws -> Self {
        let bundle = bundle ?? .main

        guard let url = bundle.url(forResource: resource, withExtension: `extension`, subdirectory: subdirectory)
        else { throw KvHttpResponseError.unableToFindBundleResource(name: resource, extension: `extension`, subdirectory: subdirectory, bundle: bundle) }

        return try self.file(at: url)
    }


    /// - Returns: A copy where body is JSON representation of given *payload*, missing `contentType` is changed to `.application(.json)`.
    ///
    /// - Important: *Payload* block may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func json<T : Encodable>(_ payload: @escaping () throws -> T) -> Self {
        modified {
            $0.bodyCallbackProvider = { Result {
                let payload = try payload()
                let data = try JSONEncoder().encode(payload)

                return Self.dataBodyCallback(data)
            } }
            $0.contentType = $0.contentType ?? .application(.json)
        }
    }


    /// - Returns: A copy where body is UTF8 representation of given *string*, missing `contentType` is changed to `.text(.plain)`.
    ///
    /// - Important: *String* block may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func string<S: StringProtocol>(_ string: @escaping () throws -> S) -> Self {
        modified {
            $0.bodyCallbackProvider = { Result {
                let string = try string()
                let data = string.data(using: .utf8)!

                return Self.dataBodyCallback(data)
            } }
            $0.contentType = $0.contentType ?? .text(.plain)
        }
    }

}



// MARK: Dedicated Status Modifiers

extension KvHttpResponseProvider {

    // MARK: 2xx

    /// - Returns: A copy where *status* is changed to`.ok`.
    @inlinable public var ok: Self { modified { $0.status = .ok } }
    /// - Returns: A copy where *status* is changed to`.created`.
    @inlinable public var created: Self { modified { $0.status = .created } }
    /// - Returns: A copy where *status* is changed to`.accepted`.
    @inlinable public var accepted: Self { modified { $0.status = .accepted } }
    /// - Returns: A copy where *status* is changed to`.nonAuthoritativeInformation`.
    @inlinable public var nonAuthoritativeInformation: Self { modified { $0.status = .nonAuthoritativeInformation } }
    /// - Returns: A copy where *status* is changed to`.noContent`.
    @inlinable public var noContent: Self { modified { $0.status = .noContent } }
    /// - Returns: A copy where *status* is changed to`.resetContent`.
    @inlinable public var resetContent: Self { modified { $0.status = .resetContent } }
    /// - Returns: A copy where *status* is changed to`.partialContent`.
    @inlinable public var partialContent: Self { modified { $0.status = .partialContent } }
    /// - Returns: A copy where *status* is changed to`.multiStatus`.
    @inlinable public var multiStatus: Self { modified { $0.status = .multiStatus } }
    /// - Returns: A copy where *status* is changed to`.alreadyReported`.
    @inlinable public var alreadyReported: Self { modified { $0.status = .alreadyReported } }
    /// - Returns: A copy where *status* is changed to`.imUsed`.
    @inlinable public var imUsed: Self { modified { $0.status = .imUsed } }

    // MARK: 3xx

    /// - Returns: A copy where *status* is changed to`.multipleChoices`.
    @inlinable public var multipleChoices: Self { modified { $0.status = .multipleChoices } }
    /// - Returns: A copy where *status* is changed to`.movedPermanently`.
    @inlinable public var movedPermanently: Self { modified { $0.status = .movedPermanently } }
    /// - Returns: A copy where *status* is changed to`.found`.
    @inlinable public var found: Self { modified { $0.status = .found } }
    /// - Returns: A copy where *status* is changed to`.seeOther`.
    @inlinable public var seeOther: Self { modified { $0.status = .seeOther } }
    /// - Returns: A copy where *status* is changed to`.notModified`.
    @inlinable public var notModified: Self { modified { $0.status = .notModified } }
    /// - Returns: A copy where *status* is changed to`.useProxy`.
    @available(*, deprecated, message: "The 305 (Use Proxy) status code has been deprecated due to security concerns. See https://www.rfc-editor.org/rfc/rfc7231.html#appendix-B")
    @inlinable public var useProxy: Self { modified { $0.status = .useProxy } }
    /// - Returns: A copy where *status* is changed to`.temporaryRedirect`.
    @inlinable public var temporaryRedirect: Self { modified { $0.status = .temporaryRedirect } }
    /// - Returns: A copy where *status* is changed to`.permanentRedirect`.
    @inlinable public var permanentRedirect: Self { modified { $0.status = .permanentRedirect } }

    // MARK: 4xx

    /// - Returns: A copy where *status* is changed to`.badRequest`.
    @inlinable public var badRequest: Self { modified { $0.status = .badRequest } }
    /// - Returns: A copy where *status* is changed to`.unauthorized`.
    @inlinable public var unauthorized: Self { modified { $0.status = .unauthorized } }
    /// - Returns: A copy where *status* is changed to`.paymentRequired`.
    @inlinable public var paymentRequired: Self { modified { $0.status = .paymentRequired } }
    /// - Returns: A copy where *status* is changed to`.forbidden`.
    @inlinable public var forbidden: Self { modified { $0.status = .forbidden } }
    /// - Returns: A copy where *status* is changed to`.notFound`.
    @inlinable public var notFound: Self { modified { $0.status = .notFound } }
    /// - Returns: A copy where *status* is changed to`.methodNotAllowed`.
    @inlinable public var methodNotAllowed: Self { modified { $0.status = .methodNotAllowed } }
    /// - Returns: A copy where *status* is changed to`.notAcceptable`.
    @inlinable public var notAcceptable: Self { modified { $0.status = .notAcceptable } }
    /// - Returns: A copy where *status* is changed to`.proxyAuthenticationRequired`.
    @inlinable public var proxyAuthenticationRequired: Self { modified { $0.status = .proxyAuthenticationRequired } }
    /// - Returns: A copy where *status* is changed to`.requestTimeout`.
    @inlinable public var requestTimeout: Self { modified { $0.status = .requestTimeout } }
    /// - Returns: A copy where *status* is changed to`.conflict`.
    @inlinable public var conflict: Self { modified { $0.status = .conflict } }
    /// - Returns: A copy where *status* is changed to`.gone`.
    @inlinable public var gone: Self { modified { $0.status = .gone } }
    /// - Returns: A copy where *status* is changed to`.lengthRequired`.
    @inlinable public var lengthRequired: Self { modified { $0.status = .lengthRequired } }
    /// - Returns: A copy where *status* is changed to`.preconditionFailed`.
    @inlinable public var preconditionFailed: Self { modified { $0.status = .preconditionFailed } }
    /// - Returns: A copy where *status* is changed to`.payloadTooLarge`.
    @inlinable public var payloadTooLarge: Self { modified { $0.status = .payloadTooLarge } }
    /// - Returns: A copy where *status* is changed to`.uriTooLong`.
    @inlinable public var uriTooLong: Self { modified { $0.status = .uriTooLong } }
    /// - Returns: A copy where *status* is changed to`.unsupportedMediaType`.
    @inlinable public var unsupportedMediaType: Self { modified { $0.status = .unsupportedMediaType } }
    /// - Returns: A copy where *status* is changed to`.rangeNotSatisfiable`.
    @inlinable public var rangeNotSatisfiable: Self { modified { $0.status = .rangeNotSatisfiable } }
    /// - Returns: A copy where *status* is changed to`.expectationFailed`.
    @inlinable public var expectationFailed: Self { modified { $0.status = .expectationFailed } }
    /// - Returns: A copy where *status* is changed to`.imATeapot`.
    @inlinable public var imATeapot: Self { modified { $0.status = .imATeapot } }
    /// - Returns: A copy where *status* is changed to`.misdirectedRequest`.
    @inlinable public var misdirectedRequest: Self { modified { $0.status = .misdirectedRequest } }
    /// - Returns: A copy where *status* is changed to`.unprocessableEntity`.
    @inlinable public var unprocessableEntity: Self { modified { $0.status = .unprocessableEntity } }
    /// - Returns: A copy where *status* is changed to`.locked`.
    @inlinable public var locked: Self { modified { $0.status = .locked } }
    /// - Returns: A copy where *status* is changed to`.failedDependency`.
    @inlinable public var failedDependency: Self { modified { $0.status = .failedDependency } }
    /// - Returns: A copy where *status* is changed to`.upgradeRequired`.
    @inlinable public var upgradeRequired: Self { modified { $0.status = .upgradeRequired } }
    /// - Returns: A copy where *status* is changed to`.preconditionRequired`.
    @inlinable public var preconditionRequired: Self { modified { $0.status = .preconditionRequired } }
    /// - Returns: A copy where *status* is changed to`.tooManyRequests`.
    @inlinable public var tooManyRequests: Self { modified { $0.status = .tooManyRequests } }
    /// - Returns: A copy where *status* is changed to`.requestHeaderFieldsTooLarge`.
    @inlinable public var requestHeaderFieldsTooLarge: Self { modified { $0.status = .requestHeaderFieldsTooLarge } }
    /// - Returns: A copy where *status* is changed to`.unavailableForLegalReasons`.
    @inlinable public var unavailableForLegalReasons: Self { modified { $0.status = .unavailableForLegalReasons } }

    // MARK: 5xx

    /// - Returns: A copy where *status* is changed to`.internalServerError`.
    @inlinable public var internalServerError: Self { modified { $0.status = .internalServerError } }
    /// - Returns: A copy where *status* is changed to`.notImplemented`.
    @inlinable public var notImplemented: Self { modified { $0.status = .notImplemented } }
    /// - Returns: A copy where *status* is changed to`.badGateway`.
    @inlinable public var badGateway: Self { modified { $0.status = .badGateway } }
    /// - Returns: A copy where *status* is changed to`.serviceUnavailable`.
    @inlinable public var serviceUnavailable: Self { modified { $0.status = .serviceUnavailable } }
    /// - Returns: A copy where *status* is changed to`.gatewayTimeout`.
    @inlinable public var gatewayTimeout: Self { modified { $0.status = .gatewayTimeout } }
    /// - Returns: A copy where *status* is changed to`.httpVersionNotSupported`.
    @inlinable public var httpVersionNotSupported: Self { modified { $0.status = .httpVersionNotSupported } }
    /// - Returns: A copy where *status* is changed to`.variantAlsoNegotiates`.
    @inlinable public var variantAlsoNegotiates: Self { modified { $0.status = .variantAlsoNegotiates } }
    /// - Returns: A copy where *status* is changed to`.insufficientStorage`.
    @inlinable public var insufficientStorage: Self { modified { $0.status = .insufficientStorage } }
    /// - Returns: A copy where *status* is changed to`.loopDetected`.
    @inlinable public var loopDetected: Self { modified { $0.status = .loopDetected } }
    /// - Returns: A copy where *status* is changed to`.notExtended`.
    @inlinable public var notExtended: Self { modified { $0.status = .notExtended } }
    /// - Returns: A copy where *status* is changed to`.networkAuthenticationRequired`.
    @inlinable public var networkAuthenticationRequired: Self { modified { $0.status = .networkAuthenticationRequired } }

}



// MARK: Dedicated Option Modifiers

extension KvHttpResponseProvider {

    /// Sets or clears ``KvHttpResponseProvider/Options/needsDisconnect`` option.
    @inlinable public func needsDisconnect(_ value: Bool = true) -> Self {
        modified { value ? $0.options.formUnion(.needsDisconnect) : $0.options.subtract(.needsDisconnect) }
    }

}
