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
//  KvHttpStatus.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 16.10.2023.
//

/// Enumeration of HTTP status codes.
///
/// - Note: HTTP status codes are from [HTTP Status Code Registry](https://www.iana.org/assignments/http-status-codes/http-status-codes.xhtml ).
public enum KvHttpStatus : Hashable, CustomStringConvertible {

    // MARK: 1xx (Informational)

    /// Status code: 100 (Continue).
    case `continue`
    /// Status code: 101 (Switching Protocols).
    case switchingProtocols
    /// Status code: 102 (Processing).
    case processing
    /// Status code: 103 (Early Hints).
    case earlyHints

    // MARK: 2xx (Successful)

    /// Status code: 200 (OK).
    case ok
    /// Status code: 201 (Created).
    case created
    /// Status code: 202 (Accepted).
    case accepted
    /// Status code: 203 (Non-Authoritative Information).
    case nonAuthoritativeInformation
    /// Status code: 204 (No Content).
    case noContent
    /// Status code: 205 (Reset Content).
    case resetContent
    /// Status code: 206 (Partial Content).
    case partialContent
    /// Status code: 207 (Multi-Status).
    case multiStatus
    /// Status code: 208 (Already Reported).
    case alreadyReported
    /// Status code: 226 (IM Used).
    case imUsed

    // MARK: 3xx (Redirections)

    /// Status code: 300 (Multiple Choices).
    case multipleChoices
    /// Status code: 301 (Moved Permanently).
    case movedPermanently
    /// Status code: 302 (Found).
    case found
    /// Status code: 303 (See Other).
    case seeOther
    /// Status code: 304 (Not Modified).
    case notModified
    /// Status code: 307 (Temporary Redirect).
    case temporaryRedirect
    /// Status code: 308 (Permanent Redirect).
    case permanentRedirect

    // MARK: 4xx (Client Errors)

    /// Status code: 400 (Bad Request).
    case badRequest
    /// Status code: 401 (Unauthorized).
    case unauthorized
    /// Status code: 402 (Payment Required).
    case paymentRequired
    /// Status code: 403 (Forbidden).
    case forbidden
    /// Status code: 404 (Not Found).
    case notFound
    /// Status code: 405 (Method Not Allowed).
    case methodNotAllowed
    /// Status code: 406 (Not Acceptable).
    case notAcceptable
    /// Status code: 407 (Proxy Authentication Required).
    case proxyAuthenticationRequired
    /// Status code: 408 (Request Timeout).
    case requestTimeout
    /// Status code: 409 (Conflict).
    case conflict
    /// Status code: 410 (Gone).
    case gone
    /// Status code: 411 (Length Required).
    case lengthRequired
    /// Status code: 412 (Precondition Failed).
    case preconditionFailed
    /// Status code: 413 (Content Too Large).
    case contentTooLarge
    /// Status code: 414 (URI Too Long).
    case uriTooLong
    /// Status code: 415 (Unsupported Media Type).
    case unsupportedMediaType
    /// Status code: 416 (Range Not Satisfiable).
    case rangeNotSatisfiable
    /// Status code: 417 (Expectation Failed).
    case expectationFailed
    /// Status code: 421 (Misdirected Request).
    case misdirectedRequest
    /// Status code: 422 (Unprocessable Content).
    case unprocessableContent
    /// Status code: 423 (Locked).
    case locked
    /// Status code: 424 (Failed Dependency).
    case failedDependency
    /// Status code: 426 (Upgrade Required).
    case upgradeRequired
    /// Status code: 428 (Precondition Required).
    case preconditionRequired
    /// Status code: 429 (Too Many Requests).
    case tooManyRequests
    /// Status code: 431 (Request Header Fields Too Large).
    case requestHeaderFieldsTooLarge
    /// Status code: 451 (Unavailable For Legal Reasons).
    case unavailableForLegalReasons

    // MARK: 5xx (Server Errors)

    /// Status code: 500 (Internal Server Error).
    case internalServerError
    /// Status code: 501 (Not Implemented).
    case notImplemented
    /// Status code: 502 (Bad Gateway).
    case badGateway
    /// Status code: 503 (Service Unavailable).
    case serviceUnavailable
    /// Status code: 504 (Gateway Timeout).
    case gatewayTimeout
    /// Status code: 505 (HTTP Version Not Supported).
    case httpVersionNotSupported
    /// Status code: 506 (Variant Also Negotiates).
    case variantAlsoNegotiates
    /// Status code: 507 (Insufficient Storage).
    case insufficientStorage
    /// Status code: 508 (Not Extended).
    case loopDetected
    /// Status code: 511 (Network Authentication Required).
    case networkAuthenticationRequired

    // MARK: .raw

    /// Arbitrary status code and provider of reason phrase.
    case raw(UInt, reasonPhrase: @autoclosure () -> String = "")


    // MARK: Initialization

    /// Initializes an instance from given raw HTTP response status value.
    /// If there is no case matching given raw value then `nil` is returned.
    ///
    /// - Tip: Use ``raw(_:reasonPhrase:)`` case to initialize instances for arbitrary HTTP response statuses.
    @inlinable
    public init?(rawValue: UInt) {
        switch rawValue {
        case 100:
            self = .`continue`
        case 101:
            self = .switchingProtocols
        case 102:
            self = .processing
        case 103:
            self = .earlyHints
        case 200:
            self = .ok
        case 201:
            self = .created
        case 202:
            self = .accepted
        case 203:
            self = .nonAuthoritativeInformation
        case 204:
            self = .noContent
        case 205:
            self = .resetContent
        case 206:
            self = .partialContent
        case 207:
            self = .multiStatus
        case 208:
            self = .alreadyReported
        case 226:
            self = .imUsed
        case 300:
            self = .multipleChoices
        case 301:
            self = .movedPermanently
        case 302:
            self = .found
        case 303:
            self = .seeOther
        case 304:
            self = .notModified
        case 307:
            self = .temporaryRedirect
        case 308:
            self = .permanentRedirect
        case 400:
            self = .badRequest
        case 401:
            self = .unauthorized
        case 402:
            self = .paymentRequired
        case 403:
            self = .forbidden
        case 404:
            self = .notFound
        case 405:
            self = .methodNotAllowed
        case 406:
            self = .notAcceptable
        case 407:
            self = .proxyAuthenticationRequired
        case 408:
            self = .requestTimeout
        case 409:
            self = .conflict
        case 410:
            self = .gone
        case 411:
            self = .lengthRequired
        case 412:
            self = .preconditionFailed
        case 413:
            self = .contentTooLarge
        case 414:
            self = .uriTooLong
        case 415:
            self = .unsupportedMediaType
        case 416:
            self = .rangeNotSatisfiable
        case 417:
            self = .expectationFailed
        case 421:
            self = .misdirectedRequest
        case 422:
            self = .unprocessableContent
        case 423:
            self = .locked
        case 424:
            self = .failedDependency
        case 426:
            self = .upgradeRequired
        case 428:
            self = .preconditionRequired
        case 429:
            self = .tooManyRequests
        case 431:
            self = .requestHeaderFieldsTooLarge
        case 451:
            self = .unavailableForLegalReasons
        case 500:
            self = .internalServerError
        case 501:
            self = .notImplemented
        case 502:
            self = .badGateway
        case 503:
            self = .serviceUnavailable
        case 504:
            self = .gatewayTimeout
        case 505:
            self = .httpVersionNotSupported
        case 506:
            self = .variantAlsoNegotiates
        case 507:
            self = .insufficientStorage
        case 508:
            self = .loopDetected
        case 511:
            self = .networkAuthenticationRequired

        default:
            return nil
        }
    }



    // MARK: Fabrics

    /// Status code: 305 (Use Proxy).
    ///
    /// - Important: The 305 (Use Proxy) status code has been deprecated due to security concerns.
    ///     See [RFC 7231](https://www.rfc-editor.org/rfc/rfc7231.html#appendix-B ).
    ///     If it is still necessary, then `.raw(305, reasonPhrase: "Use Proxy")` can be used.
    @available(*, deprecated, message: "The 305 (Use Proxy) status code has been deprecated due to security concerns. See https://www.rfc-editor.org/rfc/rfc7231.html#appendix-B")
    @inlinable
    public static var useProxy: Self { .raw(305, reasonPhrase: "Use Proxy") }


    /// Status code: 413 (Payload Too Large).
    ///
    /// - Note: The 413 (Payload Too Large) [RFC 7231, section 6.5.11](https://datatracker.ietf.org/doc/html/rfc7231#section-6.5.11 )
    ///     has been changed to 413 (Content Too Large) [RFC 9110, section 15.5.14](https://www.rfc-editor.org/rfc/rfc9110.html#section-15.5.14 ).
    ///     Use ``contentTooLarge`` instead.
    @available(*, deprecated, renamed: "contentTooLarge")
    @inlinable
    public static var payloadTooLarge: Self { .raw(413, reasonPhrase: "Payload Too Large") }


    /// Status code: 422 (Unprocessable Entity).
    ///
    /// - Note: The 422 (Unprocessable Entity) [RFC 4918, section 11.2](https://datatracker.ietf.org/doc/html/rfc4918#section-11.2 )
    ///     has been changed to 422 (Unprocessable Content) [RFC 9110, section 15.5.21](https://www.rfc-editor.org/rfc/rfc9110.html#section-15.5.21 ).
    ///     Use ``unprocessableContent`` instead.
    @available(*, deprecated, renamed: "unprocessableContent")
    @inlinable
    public static var unprocessableEntity: Self { .raw(422, reasonPhrase: "Unprocessable Entity") }


    /// Status code: 510 (Not Extended).
    ///
    /// - Important: The 510 (Not Extended) status code has been obsoleted.
    ///     If it is still necessary, then `.raw(510, reasonPhrase: "Not Extended")` can be used.
    @available(*, deprecated, message: "The 510 (Not Extended) status code has been obsoleted")
    @inlinable
    public static var notExtended: Self { .raw(510, reasonPhrase: "Not Extended") }



    // MARK: Operations

    /// The receiver's raw HTTP response status value.
    @inlinable
    public var rawValue: UInt {
        switch self {
        case .`continue`:
            return 100
        case .switchingProtocols:
            return 101
        case .processing:
            return 102
        case .earlyHints:
            return 103
        case .ok:
            return 200
        case .created:
            return 201
        case .accepted:
            return 202
        case .nonAuthoritativeInformation:
            return 203
        case .noContent:
            return 204
        case .resetContent:
            return 205
        case .partialContent:
            return 206
        case .multiStatus:
            return 207
        case .alreadyReported:
            return 208
        case .imUsed:
            return 226
        case .multipleChoices:
            return 300
        case .movedPermanently:
            return 301
        case .found:
            return 302
        case .seeOther:
            return 303
        case .notModified:
            return 304
        case .temporaryRedirect:
            return 307
        case .permanentRedirect:
            return 308
        case .badRequest:
            return 400
        case .unauthorized:
            return 401
        case .paymentRequired:
            return 402
        case .forbidden:
            return 403
        case .notFound:
            return 404
        case .methodNotAllowed:
            return 405
        case .notAcceptable:
            return 406
        case .proxyAuthenticationRequired:
            return 407
        case .requestTimeout:
            return 408
        case .conflict:
            return 409
        case .gone:
            return 410
        case .lengthRequired:
            return 411
        case .preconditionFailed:
            return 412
        case .contentTooLarge:
            return 413
        case .uriTooLong:
            return 414
        case .unsupportedMediaType:
            return 415
        case .rangeNotSatisfiable:
            return 416
        case .expectationFailed:
            return 417
        case .misdirectedRequest:
            return 421
        case .unprocessableContent:
            return 422
        case .locked:
            return 423
        case .failedDependency:
            return 424
        case .upgradeRequired:
            return 426
        case .preconditionRequired:
            return 428
        case .tooManyRequests:
            return 429
        case .requestHeaderFieldsTooLarge:
            return 431
        case .unavailableForLegalReasons:
            return 451
        case .internalServerError:
            return 500
        case .notImplemented:
            return 501
        case .badGateway:
            return 502
        case .serviceUnavailable:
            return 503
        case .gatewayTimeout:
            return 504
        case .httpVersionNotSupported:
            return 505
        case .variantAlsoNegotiates:
            return 506
        case .insufficientStorage:
            return 507
        case .loopDetected:
            return 510
        case .networkAuthenticationRequired:
            return 511

        case .raw(let rawValue, reasonPhrase: _):
            return rawValue
        }
    }


    /// The receiver's reason phrase.
    @inlinable
    public var reasonPhrase: String {
        switch self {
        case .`continue`:
            return "Continue"
        case .switchingProtocols:
            return "Switching Protocols"
        case .processing:
            return "Processing"
        case .earlyHints:
            return "Early Hints"
        case .ok:
            return "OK"
        case .created:
            return "Created"
        case .accepted:
            return "Accepted"
        case .nonAuthoritativeInformation:
            return "Non-Authoritative Information"
        case .noContent:
            return "No Content"
        case .resetContent:
            return "Reset Content"
        case .partialContent:
            return "Partial Content"
        case .multiStatus:
            return "Multi-Status"
        case .alreadyReported:
            return "Already Reported"
        case .imUsed:
            return "IM Used"
        case .multipleChoices:
            return "Multiple Choices"
        case .movedPermanently:
            return "Moved Permanently"
        case .found:
            return "Found"
        case .seeOther:
            return "See Other"
        case .notModified:
            return "Not Modified"
        case .temporaryRedirect:
            return "Temporary Redirect"
        case .permanentRedirect:
            return "Permanent Redirect"
        case .badRequest:
            return "Bad Request"
        case .unauthorized:
            return "Unauthorized"
        case .paymentRequired:
            return "Payment Required"
        case .forbidden:
            return "Forbidden"
        case .notFound:
            return "Not Found"
        case .methodNotAllowed:
            return "Method Not Allowed"
        case .notAcceptable:
            return "Not Acceptable"
        case .proxyAuthenticationRequired:
            return "Proxy Authentication Required"
        case .requestTimeout:
            return "Request Timeout"
        case .conflict:
            return "Conflict"
        case .gone:
            return "Gone"
        case .lengthRequired:
            return "Length Required"
        case .preconditionFailed:
            return "Precondition Failed"
        case .contentTooLarge:
            return "Content Too Large"
        case .uriTooLong:
            return "URI Too Long"
        case .unsupportedMediaType:
            return "Unsupported Media Type"
        case .rangeNotSatisfiable:
            return "Range Not Satisfiable"
        case .expectationFailed:
            return "Expectation Failed"
        case .misdirectedRequest:
            return "Misdirected Request"
        case .unprocessableContent:
            return "Unprocessable Content"
        case .locked:
            return "Locked"
        case .failedDependency:
            return "Failed Dependency"
        case .upgradeRequired:
            return "Upgrade Required"
        case .preconditionRequired:
            return "Precondition Required"
        case .tooManyRequests:
            return "Too Many Requests"
        case .requestHeaderFieldsTooLarge:
            return "Request Header Fields Too Large"
        case .unavailableForLegalReasons:
            return "Unavailable For Legal Reasons"
        case .internalServerError:
            return "Internal Server Error"
        case .notImplemented:
            return "Not Implemented"
        case .badGateway:
            return "Bad Gateway"
        case .serviceUnavailable:
            return "Service Unavailable"
        case .gatewayTimeout:
            return "Gateway Timeout"
        case .httpVersionNotSupported:
            return "HTTP Version Not Supported"
        case .variantAlsoNegotiates:
            return "Variant Also Negotiates"
        case .insufficientStorage:
            return "Insufficient Storage"
        case .loopDetected:
            return "Not Extended"
        case .networkAuthenticationRequired:
            return "Network Authentication Required"

        case .raw(_, let reasonPhrase):
            return reasonPhrase()
        }
    }



    // MARK: : Equatable

    @inlinable
    public static func ==(lhs: Self, rhs: Self) -> Bool { lhs.rawValue == rhs.rawValue }



    // MARK: : Hashable

    @inlinable
    public func hash(into hasher: inout Hasher) { rawValue.hash(into: &hasher) }



    // MARK: : CustomStringConvertible

    @inlinable
    public var description: String { "\(rawValue) (\(reasonPhrase)" }

}
