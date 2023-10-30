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
//  kvHttpKit_NIOHTTP1
//
//  Created by Svyatoslav Popov on 29.10.2023.
//

import kvHttpKit

import NIOHTTP1



extension KvHttpStatus {

    /// - Initializes an instance from value of `HTTPResponseStatus`.
    @inlinable
    public init(from nioStatus: HTTPResponseStatus) {
        switch nioStatus {
        case .continue:
            self = .continue
        case .switchingProtocols:
            self = .switchingProtocols
        case .processing:
            self = .processing
        case .ok:
            self = .ok
        case .created:
            self = .created
        case .accepted:
            self = .accepted
        case .nonAuthoritativeInformation:
            self = .nonAuthoritativeInformation
        case .noContent:
            self = .noContent
        case .resetContent:
            self = .resetContent
        case .partialContent:
            self = .partialContent
        case .multiStatus:
            self = .multiStatus
        case .alreadyReported:
            self = .alreadyReported
        case .imUsed:
            self = .imUsed
        case .multipleChoices:
            self = .multipleChoices
        case .movedPermanently:
            self = .movedPermanently
        case .found:
            self = .found
        case .seeOther:
            self = .seeOther
        case .notModified:
            self = .notModified
        case .temporaryRedirect:
            self = .temporaryRedirect
        case .permanentRedirect:
            self = .permanentRedirect
        case .badRequest:
            self = .badRequest
        case .unauthorized:
            self = .unauthorized
        case .paymentRequired:
            self = .paymentRequired
        case .forbidden:
            self = .forbidden
        case .notFound:
            self = .notFound
        case .methodNotAllowed:
            self = .methodNotAllowed
        case .notAcceptable:
            self = .notAcceptable
        case .proxyAuthenticationRequired:
            self = .proxyAuthenticationRequired
        case .requestTimeout:
            self = .requestTimeout
        case .conflict:
            self = .conflict
        case .gone:
            self = .gone
        case .lengthRequired:
            self = .lengthRequired
        case .preconditionFailed:
            self = .preconditionFailed
        case .payloadTooLarge:
            self = .contentTooLarge
        case .uriTooLong:
            self = .uriTooLong
        case .unsupportedMediaType:
            self = .unsupportedMediaType
        case .rangeNotSatisfiable:
            self = .rangeNotSatisfiable
        case .expectationFailed:
            self = .expectationFailed
        case .misdirectedRequest:
            self = .misdirectedRequest
        case .unprocessableEntity:
            self = .unprocessableContent
        case .locked:
            self = .locked
        case .failedDependency:
            self = .failedDependency
        case .upgradeRequired:
            self = .upgradeRequired
        case .preconditionRequired:
            self = .preconditionRequired
        case .tooManyRequests:
            self = .tooManyRequests
        case .requestHeaderFieldsTooLarge:
            self = .requestHeaderFieldsTooLarge
        case .unavailableForLegalReasons:
            self = .unavailableForLegalReasons
        case .internalServerError:
            self = .internalServerError
        case .notImplemented:
            self = .notImplemented
        case .badGateway:
            self = .badGateway
        case .serviceUnavailable:
            self = .serviceUnavailable
        case .gatewayTimeout:
            self = .gatewayTimeout
        case .httpVersionNotSupported:
            self = .httpVersionNotSupported
        case .variantAlsoNegotiates:
            self = .variantAlsoNegotiates
        case .insufficientStorage:
            self = .insufficientStorage
        case .loopDetected:
            self = .loopDetected
        case .networkAuthenticationRequired:
            self = .networkAuthenticationRequired

        case .imATeapot, .notExtended, .useProxy:
            let (code, reasonPhrase) = (nioStatus.code, nioStatus.reasonPhrase)
            self = Self(rawValue: code) ?? .raw(code, reasonPhrase: reasonPhrase)

        case .custom(let code, let reasonPhrase):
            self = Self(rawValue: code) ?? .raw(code, reasonPhrase: reasonPhrase)
        }
    }



    // MARK: Operations

    /// Instance of `HTTPResponseStatus` corresponding to the receiver.
    @inlinable
    public var nioStatus: HTTPResponseStatus {
        switch self {
        case .continue:
            return .continue
        case .switchingProtocols:
            return .switchingProtocols
        case .processing:
            return .processing
        case .ok:
            return .ok
        case .created:
            return .created
        case .accepted:
            return .accepted
        case .nonAuthoritativeInformation:
            return .nonAuthoritativeInformation
        case .noContent:
            return .noContent
        case .resetContent:
            return .resetContent
        case .partialContent:
            return .partialContent
        case .multiStatus:
            return .multiStatus
        case .alreadyReported:
            return .alreadyReported
        case .imUsed:
            return .imUsed
        case .multipleChoices:
            return .multipleChoices
        case .movedPermanently:
            return .movedPermanently
        case .found:
            return .found
        case .seeOther:
            return .seeOther
        case .notModified:
            return .notModified
        case .temporaryRedirect:
            return .temporaryRedirect
        case .permanentRedirect:
            return .permanentRedirect
        case .badRequest:
            return .badRequest
        case .unauthorized:
            return .unauthorized
        case .paymentRequired:
            return .paymentRequired
        case .forbidden:
            return .forbidden
        case .notFound:
            return .notFound
        case .methodNotAllowed:
            return .methodNotAllowed
        case .notAcceptable:
            return .notAcceptable
        case .proxyAuthenticationRequired:
            return .proxyAuthenticationRequired
        case .requestTimeout:
            return .requestTimeout
        case .conflict:
            return .conflict
        case .gone:
            return .gone
        case .lengthRequired:
            return .lengthRequired
        case .preconditionFailed:
            return .preconditionFailed
        case .contentTooLarge:
            return .payloadTooLarge
        case .uriTooLong:
            return .uriTooLong
        case .unsupportedMediaType:
            return .unsupportedMediaType
        case .rangeNotSatisfiable:
            return .rangeNotSatisfiable
        case .expectationFailed:
            return .expectationFailed
        case .misdirectedRequest:
            return .misdirectedRequest
        case .unprocessableContent:
            return .unprocessableEntity
        case .locked:
            return .locked
        case .failedDependency:
            return .failedDependency
        case .upgradeRequired:
            return .upgradeRequired
        case .preconditionRequired:
            return .preconditionRequired
        case .tooManyRequests:
            return .tooManyRequests
        case .requestHeaderFieldsTooLarge:
            return .requestHeaderFieldsTooLarge
        case .unavailableForLegalReasons:
            return .unavailableForLegalReasons
        case .internalServerError:
            return .internalServerError
        case .notImplemented:
            return .notImplemented
        case .badGateway:
            return .badGateway
        case .serviceUnavailable:
            return .serviceUnavailable
        case .gatewayTimeout:
            return .gatewayTimeout
        case .httpVersionNotSupported:
            return .httpVersionNotSupported
        case .variantAlsoNegotiates:
            return .variantAlsoNegotiates
        case .insufficientStorage:
            return .insufficientStorage
        case .loopDetected:
            return .loopDetected
        case .networkAuthenticationRequired:
            return .networkAuthenticationRequired

        case .earlyHints:
            return .custom(code: rawValue, reasonPhrase: reasonPhrase)

        case .raw(let rawValue, let reasonPhrase):
            return .custom(code: rawValue, reasonPhrase: reasonPhrase())
        }
    }

}
