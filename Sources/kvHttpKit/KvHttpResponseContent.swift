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
//  KvHttpResponseContent.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 30.05.2023.
//

import Foundation



// TODO: Apply consuming, borrowing, consume, copy keywords in Swift 5.9.

/// Representation of HTTP response content.
/// *KvHttpResponseContent* is designed to be configured with fabrics and modifiers. For example:
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
///
/// *KvHttpResponseContent* provides deferred access to body providers so, for example, the same declaration can be effectively used for both GET and HEAD methods.
///
/// When a response is configured, use ``forEachHeader(_:)`` method to process headrer values and ``bodyCallbackProvider`` to process body bytes.
public struct KvHttpResponseContent {

    /// A block invoked with header name and value.
    public typealias HeaderCallback = (String, String) -> Void

    /// A block calling provided callback with tuples of custom header names and values.
    public typealias HeaderProvider = (HeaderCallback) -> Void

    /// Body callback is used to write body fragments to provided client's buffer.
    /// Body callback returns number of actually written bytes or an error as a standard *Result*.
    public typealias BodyCallback = (UnsafeMutableRawBufferPointer) -> Result<Int, Error>
    /// A block providing an optional ``BodyCallback`` or an error.
    public typealias BodyCallbackProvider = () -> Result<BodyCallback, Error>


    public typealias ContentError = KvHttpKitError.Response


    /// HTTP response status code.
    @inlinable
    public var status: KvHttpStatus {  _status }
    @usableFromInline
    var _status: KvHttpStatus

    /// An optional callback providing custom headers.
    @inlinable
    public var customHeaderProvider: HeaderProvider? { _customHeaderProvider }
    @usableFromInline
    var _customHeaderProvider: HeaderProvider?

    /// This property is called just before response body is sent to a client.
    /// Also it can be ignored, for example when HTTP method is *HEAD*.
    ///
    /// `Nil` value means that response has no body.
    ///
    /// See ``BodyCallbackProvider`` and ``BodyCallback`` for details.
    @inlinable
    public var bodyCallbackProvider: BodyCallbackProvider? { _bodyCallbackProvider }
    @usableFromInline
    var _bodyCallbackProvider: BodyCallbackProvider?

    /// Optional value for `Content-Type` HTTP header in response. If `nil` then the header is not provided in response.
    @inlinable
    public var contentType: KvHttpContentType? { _contentType }
    @usableFromInline
    var _contentType: KvHttpContentType?
    /// Optional value for `Content-Length` HTTP header in response. If `nil` then the header is not provided in response.
    @inlinable
    public var contentLength: UInt64? { _contentLength }
    @usableFromInline
    var _contentLength: UInt64?

    /// Value for `ETag` response header.
    @inlinable
    public var entityTag: KvHttpEntityTag? { _entityTag }
    @usableFromInline
    var _entityTag: KvHttpEntityTag?
    /// Value for `Last-Modified` response header.
    @inlinable
    public var modificationDate: Date? { _modificationDate }
    @usableFromInline
    var _modificationDate: Date?

    /// Value for `Location` response header.
    @inlinable
    public var location: URL? { _location }
    @usableFromInline
    var _location: URL?

    /// Response options. E.g. disconnection flag.
    @inlinable
    public var options: Options { _options }
    @usableFromInline
    var _options: Options


    /// Memberwise initializer.
    @usableFromInline
    init(status: KvHttpStatus = .ok,
         customHeaderProvider: HeaderProvider? = nil,
         contentType: KvHttpContentType? = nil,
         contentLength: UInt64? = nil,
         entityTag: KvHttpEntityTag? = nil,
         modificationDate: Date? = nil,
         location: URL? = nil,
         options: Options = [ ],
         bodyCallbackProvider: BodyCallbackProvider? = nil
    ) {
        self._status = status
        self._customHeaderProvider = customHeaderProvider
        self._contentType = contentType
        self._contentLength = contentLength
        self._entityTag = entityTag
        self._modificationDate = modificationDate
        self._location = location
        self._options = options
        self._bodyCallbackProvider = bodyCallbackProvider
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

            guard bytesRead >= 0 else { return .failure(ContentError.streamRead(code: bytesRead, error: stream.streamError)) }

            return .success(bytesRead)
        }
    }


    @usableFromInline
    static func streamBodyCallbackProvider(_ url: URL) -> BodyCallbackProvider {
        return {
            guard let stream = InputStream(url: url) else { return .failure(ContentError.unableToCreateInputStream(url)) }
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
    mutating func appendHeaderProvider(_ provider: @escaping HeaderProvider) {
        switch _customHeaderProvider {
        case .none:
            _customHeaderProvider = provider
        case .some(let customHeaderProvider):
            _customHeaderProvider = { callback in
                customHeaderProvider(callback)
                provider(callback)
            }
        }
    }

}



// MARK: Fabrics

extension KvHttpResponseContent {

    /// - Returns:  An instance where body is provided via *provider*, *status* is `.ok`.
    ///             See ``BodyCallbackProvider`` for details.
    ///
    /// - Important: *Provider* block can be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public static func bodyCallbackProvider(_ provider: @escaping BodyCallbackProvider) -> Self {
        Self().bodyCallbackProvider(provider)
    }


    /// - Returns:  An instance where body is provided via *callback*, *status* is `.ok`.
    ///             See ``BodyCallback`` for details.
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

extension KvHttpResponseContent {

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
        let resolvedURL = try KvResolvedFileURL(for: url)

        return try Self().file(at: resolvedURL)
    }


    @inlinable
    public static func file(at url: KvResolvedFileURL) throws -> Self { try Self().file(at: url) }


    /// Invokes ``file(at:)-12ly6`` fabric with URL of a resource file with given parameters.
    /// ``KvHttpKitError/Response/unableToFindBundleResource(name:extension:subdirectory:bundle:)`` is thrown for missing resources.
    ///
    /// - Parameter bundle: If `nil` is passed then `Bundle.main` is used.
    @inlinable
    public static func file(resource: String, extension: String? = nil, subdirectory: String? = nil, bundle: Bundle? = nil) throws -> Self {
        let bundle = bundle ?? .main

        guard let url = bundle.url(forResource: resource, withExtension: `extension`, subdirectory: subdirectory)
        else { throw ContentError.unableToFindBundleResource(name: resource, extension: `extension`, subdirectory: subdirectory, bundle: bundle) }

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

extension KvHttpResponseContent {

    // MARK: 2xx

    /// - Returns: An instance where *status* is  ``KvHttpStatus/ok``(`200 OK`).
    @inlinable public static var ok: Self { .init(status: .ok) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/created``(`201 Created`).
    @inlinable public static var created: Self { .init(status: .created) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/accepted``(`202 Accepted`).
    @inlinable public static var accepted: Self { .init(status: .accepted) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/nonAuthoritativeInformation``(` 203 Non-Authoritative Information`).
    @inlinable public static var nonAuthoritativeInformation: Self { .init(status: .nonAuthoritativeInformation) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/noContent``(`204 No Content`).
    @inlinable public static var noContent: Self { .init(status: .noContent) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/resetContent``(`205 Reset Content`).
    @inlinable public static var resetContent: Self { .init(status: .resetContent) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/partialContent``(`206 Partial Content`).
    @inlinable public static var partialContent: Self { .init(status: .partialContent) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/multiStatus``(`207 Multi-Status`).
    @inlinable public static var multiStatus: Self { .init(status: .multiStatus) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/alreadyReported``(`208 Already Reported`).
    @inlinable public static var alreadyReported: Self { .init(status: .alreadyReported) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/imUsed``(`226 IM Used`).
    @inlinable public static var imUsed: Self { .init(status: .imUsed) }

    // MARK: 3xx

    /// - Returns: An instance where *status* is ``KvHttpStatus/multipleChoices``(`300 Multiple Choices`).
    @inlinable public static func multipleChoices(preferredLocation: URL? = nil) -> Self { .init(status: .multipleChoices, location: preferredLocation) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/movedPermanently``(`301 Moved Permanently`).
    @inlinable public static func movedPermanently(location: URL?) -> Self { .init(status: .movedPermanently, location: location) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/found``(`302 Found`).
    @inlinable public static func found(location: URL?) -> Self { .init(status: .found, location: location) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/seeOther``(`303 See Other`).
    @inlinable public static func seeOther(location: URL) -> Self { .init(status: .seeOther, location: location) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/notModified``(`304 Not Modified`).
    @inlinable public static var notModified: Self { .init(status: .notModified) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/temporaryRedirect``(`307 Temporary Redirect`).
    @inlinable public static func temporaryRedirect(location: URL?) -> Self { .init(status: .temporaryRedirect, location: location) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/permanentRedirect``(`308 Permanent Redirect`).
    @inlinable public static func permanentRedirect(location: URL?) -> Self { .init(status: .permanentRedirect, location: location) }

    // MARK: 4xx

    /// - Returns: An instance where *status* is ``KvHttpStatus/badRequest``(`400 Bad Request`).
    @inlinable public static var badRequest: Self { .init(status: .badRequest) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/unauthorized``(`401 Unauthorized`).
    @inlinable public static var unauthorized: Self { .init(status: .unauthorized) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/paymentRequired``(`402 Payment Required`).
    @inlinable public static var paymentRequired: Self { .init(status: .paymentRequired) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/forbidden``(`403 Forbidden`).
    @inlinable public static var forbidden: Self { .init(status: .forbidden) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/notFound``(`404 Not Found`).
    @inlinable public static var notFound: Self { .init(status: .notFound) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/methodNotAllowed``(`405 Method Not Allowed`).
    @inlinable public static var methodNotAllowed: Self { .init(status: .methodNotAllowed) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/notAcceptable``(`406 Not Acceptable`).
    @inlinable public static var notAcceptable: Self { .init(status: .notAcceptable) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/proxyAuthenticationRequired``(`407 Proxy Authentication Required`).
    @inlinable public static var proxyAuthenticationRequired: Self { .init(status: .proxyAuthenticationRequired) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/requestTimeout``(`408 Request Timeout`).
    @inlinable public static var requestTimeout: Self { .init(status: .requestTimeout) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/conflict``(`409 Conflict`).
    @inlinable public static var conflict: Self { .init(status: .conflict) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/gone``(`410 Gone`).
    @inlinable public static var gone: Self { .init(status: .gone) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/lengthRequired``(`411 Length Required`).
    @inlinable public static var lengthRequired: Self { .init(status: .lengthRequired) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/preconditionFailed``(`412 Precondition Failed`).
    @inlinable public static var preconditionFailed: Self { .init(status: .preconditionFailed) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/contentTooLarge``(`413 Content Too Large`).
    @inlinable public static var contentTooLarge: Self { .init(status: .contentTooLarge) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/uriTooLong``(`414 URI Too Long`).
    @inlinable public static var uriTooLong: Self { .init(status: .uriTooLong) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/unsupportedMediaType``(`415 Unsupported Media Type`).
    @inlinable public static var unsupportedMediaType: Self { .init(status: .unsupportedMediaType) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/rangeNotSatisfiable``(`416 Range Not Satisfiable`).
    @inlinable public static var rangeNotSatisfiable: Self { .init(status: .rangeNotSatisfiable) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/expectationFailed``(`417 Expectation Failed`).
    @inlinable public static var expectationFailed: Self { .init(status: .expectationFailed) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/misdirectedRequest``(`421 Misdirected Request`).
    @inlinable public static var misdirectedRequest: Self { .init(status: .misdirectedRequest) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/unprocessableContent``(`422 Unprocessable Content`).
    @inlinable public static var unprocessableContent: Self { .init(status: .unprocessableContent) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/locked``(`423 Locked`).
    @inlinable public static var locked: Self { .init(status: .locked) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/failedDependency``(`424 Failed Dependency`).
    @inlinable public static var failedDependency: Self { .init(status: .failedDependency) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/upgradeRequired``(`426 Upgrade Required`).
    @inlinable public static var upgradeRequired: Self { .init(status: .upgradeRequired) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/preconditionRequired``(`428 Precondition Required`).
    @inlinable public static var preconditionRequired: Self { .init(status: .preconditionRequired) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/tooManyRequests``(`429 Too Many Requests`).
    @inlinable public static var tooManyRequests: Self { .init(status: .tooManyRequests) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/requestHeaderFieldsTooLarge``(`431 Request Header Fields Too Large`).
    @inlinable public static var requestHeaderFieldsTooLarge: Self { .init(status: .requestHeaderFieldsTooLarge) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/unavailableForLegalReasons``(`451 Unavailable For Legal Reasons`).
    @inlinable public static var unavailableForLegalReasons: Self { .init(status: .unavailableForLegalReasons) }

    // MARK: 5xx

    /// - Returns: An instance where *status* is ``KvHttpStatus/internalServerError``(`500 Internal Server Error`).
    @inlinable public static var internalServerError: Self { .init(status: .internalServerError) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/notImplemented``(`501 Not Implemented`).
    @inlinable public static var notImplemented: Self { .init(status: .notImplemented) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/badGateway``(`502 Bad Gateway`).
    @inlinable public static var badGateway: Self { .init(status: .badGateway) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/serviceUnavailable``(`503 Service Unavailable`).
    @inlinable public static var serviceUnavailable: Self { .init(status: .serviceUnavailable) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/gatewayTimeout``(`504 Gateway Timeout`).
    @inlinable public static var gatewayTimeout: Self { .init(status: .gatewayTimeout) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/httpVersionNotSupported``(`505 HTTP Version Not Supported`).
    @inlinable public static var httpVersionNotSupported: Self { .init(status: .httpVersionNotSupported) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/variantAlsoNegotiates``(`506 Variant Also Negotiates`).
    @inlinable public static var variantAlsoNegotiates: Self { .init(status: .variantAlsoNegotiates) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/insufficientStorage``(`507 Insufficient Storage`).
    @inlinable public static var insufficientStorage: Self { .init(status: .insufficientStorage) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/loopDetected``(`508 Not Extended`).
    @inlinable public static var loopDetected: Self { .init(status: .loopDetected) }
    /// - Returns: An instance where *status* is ``KvHttpStatus/networkAuthenticationRequired``(`511 Network Authentication Required`).
    @inlinable public static var networkAuthenticationRequired: Self { .init(status: .networkAuthenticationRequired) }

}



// MARK: Modifiers

extension KvHttpResponseContent {

    /// - Returns: A copy where body is provided via *provider*. See ``BodyCallbackProvider`` for details.
    ///
    /// - Note: `contentType`, `contentLength` and other properties are not changed.
    ///
    /// - Important: *Provider* block can be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func bodyCallbackProvider(_ provider: @escaping BodyCallbackProvider) -> Self { modified {
        $0._bodyCallbackProvider = provider
    } }


    /// - Returns: A copy where body is provided via *callback*. See ``BodyCallback`` for details.
    ///
    /// - Note: `contentType`, `contentLength` and other properties are not changed.
    ///
    /// - Important: *Callback* block can be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func bodyCallback(_ callback: @escaping BodyCallback) -> Self { bodyCallbackProvider { .success(callback) } }


    /// - Returns: A copy where *status* is changed to given value.
    @inlinable
    public func status(_ status: KvHttpStatus) -> Self { modified { $0._status = status } }


    /// - Returns: A copy where given block is appended to the receiver's chain of header providers.
    @inlinable
    public func headers(_ provider: @escaping HeaderProvider) -> Self { modified { $0.appendHeaderProvider(provider) } }


    /// - Returns: A copy where `contentType` is changed to given *value*.
    @inlinable
    public func contentType(_ value: KvHttpContentType) -> Self { modified { $0._contentType = value } }


    /// - Returns: A copy where `contentLength` is changed to given *value*.
    @inlinable
    public func contentLength(_ value: UInt64) -> Self { modified { $0._contentLength = value } }


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
    public func entityTag(_ value: KvHttpEntityTag) -> Self { modified { $0._entityTag = value } }

    /// - Returns: A copy where modification date is changed to given *value*.
    ///
    /// - Note: It's recommended to prefer ``entityTag(_:)`` instead if possible.
    ///
    /// Provided value is used as value of `Last-Modified` response header and to process `If-Modified-Since` and `If-Unmodified-Since` request headers.
    /// For example, response is automatically replaced with 304 (Not Modified) when request contains `If-Modified-Since` header with a later date.
    @inlinable
    public func modificationDate(_ value: Date) -> Self { modified { $0._modificationDate = value } }


    /// - Returns: A copy where value of `Location` header is changed to given *value*.
    @inlinable
    public func location(_ value: URL) -> Self { modified { $0._location = value } }


    /// - Returns: A copy where body and content length are reset.
    @inlinable
    public var bodiless: Self { modified {
        $0._bodyCallbackProvider = nil
        $0._contentLength = nil
    } }

}



// MARK: Dedicated Body Modifiers

extension KvHttpResponseContent {

    /// - Returns: A copy where body is taken from provided *bytes* callback, missing `contentType` is changed to `.application(.octetStream)`.
    ///
    /// - Important: *Bytes* block may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func binary<D>(_ bytes: @escaping () throws -> D) -> Self
    where D : DataProtocol, D.Index == Int
    {
        modified {
            $0._bodyCallbackProvider = { Result {
                let data = try bytes()

                return Self.dataBodyCallback(data)
            } }
            $0._contentType = $0._contentType ?? .application(.octetStream)
        }
    }


    /// - Returns: A copy where body is taken from provided *stream*, missing `contentType` is changed to `.application(.octetStream)`.
    ///
    /// - Important: *Stream* may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func binary(_ stream: InputStream) -> Self {
        modified {
            $0._bodyCallbackProvider = { .success(Self.streamBodyCallback(stream)) }
            $0._contentType = $0._contentType ?? .application(.octetStream)
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
        let resolvedURL = try KvResolvedFileURL(for: url)

        return try self.file(at: resolvedURL)
    }


    @inlinable
    public func file(at url: KvResolvedFileURL) throws -> Self { try modified {
        let (url, isLocal) = (url.value, url.isLocal)

        if isLocal {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

            if let modificationDate = attributes[.modificationDate] as? Date {
                $0._modificationDate = modificationDate
                $0._entityTag = .hex(withBytesOf: modificationDate.timeIntervalSince1970)
            }
            if let size = attributes[.size] as? UInt64 {
                $0._contentLength = size
            }
        }

        $0._bodyCallbackProvider = Self.streamBodyCallbackProvider(url)
    } }


    /// Invokes ``file(at:)-4k2d`` modifier with URL of a resource file with given parameters.
    /// ``KvHttpKitError/Response/unableToFindBundleResource(name:extension:subdirectory:bundle:)`` is thrown for missing resources.
    ///
    /// - Parameter bundle: If `nil` is passed then `Bundle.main` is used.
    @inlinable
    public func file(resource: String, extension: String? = nil, subdirectory: String? = nil, bundle: Bundle? = nil) throws -> Self {
        let bundle = bundle ?? .main

        guard let url = bundle.url(forResource: resource, withExtension: `extension`, subdirectory: subdirectory)
        else { throw ContentError.unableToFindBundleResource(name: resource, extension: `extension`, subdirectory: subdirectory, bundle: bundle) }

        return try self.file(at: url)
    }


    /// - Returns: A copy where body is JSON representation of given *payload*, missing `contentType` is changed to `.application(.json)`.
    ///
    /// - Important: *Payload* block may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func json<T : Encodable>(_ payload: @escaping () throws -> T) -> Self {
        modified {
            $0._bodyCallbackProvider = { Result {
                let payload = try payload()
                let data = try JSONEncoder().encode(payload)

                return Self.dataBodyCallback(data)
            } }
            $0._contentType = $0._contentType ?? .application(.json)
        }
    }


    /// - Returns: A copy where body is UTF8 representation of given *string*, missing `contentType` is changed to `.text(.plain)`.
    ///
    /// - Important: *String* block may be ignored, for example when HTTP method is *HEAD*.
    @inlinable
    public func string<S: StringProtocol>(_ string: @escaping () throws -> S) -> Self {
        modified {
            $0._bodyCallbackProvider = { Result {
                let string = try string()
                let data = string.data(using: .utf8)!

                return Self.dataBodyCallback(data)
            } }
            $0._contentType = $0._contentType ?? .text(.plain)
        }
    }

}



// MARK: Dedicated Option Modifiers

extension KvHttpResponseContent {

    /// Sets or clears ``KvHttpResponseContent/Options/needsDisconnect`` option.
    @inlinable
    public func needsDisconnect(_ value: Bool = true) -> Self {
        modified { value ? $0._options.formUnion(.needsDisconnect) : $0._options.subtract(.needsDisconnect) }
    }

}



// MARK: Processing

extension KvHttpResponseContent {

    /// Invokes given *callback* with tuples of all the receriver's header names and values.
    ///
    /// - Note: All the headers are enumerated. So there is no need process the receiver's properties.
    ///
    /// - SeeAlso: ``reduceHeaders(into:_:)``.
    @inlinable
    public func forEachHeader(_ callback: HeaderCallback) {
        if let contentType = _contentType {
            callback("Content-Type", contentType.value)
        }
        if let contentLength = _contentLength {
            callback("Content-Length", String(contentLength))
        }
        if let value = _entityTag {
            callback("ETag", value.httpRepresentation)
        }
        if let modificationDate = _modificationDate {
            callback("Last-Modified", KvRFC9110.DateFormatter.string(from: modificationDate))
        }
        if let location = _location {
            callback("Location", location.absoluteString)
        }

        _customHeaderProvider?(callback)
    }


    /// - Returns: The result of the reduce operation on the receiver's headers.
    @inlinable
    public func reduceHeaders<T>(into accumulator: @autoclosure () -> T, _ updateAccumulatingResult: (inout T, (name: String, value: String)) -> Void) -> T {
        var accumulator = accumulator()

        forEachHeader { name, value in
            updateAccumulatingResult(&accumulator, (name, value))
        }

        return accumulator
    }

}
