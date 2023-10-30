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
//  KvHttpMethod.swift
//  kvHttpKit
//
//  Created by Svyatoslav Popov on 03.10.2023.
//

/// Enumeration of HTTP request methods.
/// 
/// - Note: HTTP methods are from [HTTP Method Registry](https://www.iana.org/assignments/http-methods/http-methods.xhtml ).
public enum KvHttpMethod : Hashable, CustomStringConvertible {

    /// Raw value: "ACL".
    case accessControlList
    /// Raw value: "BASELINE-CONTROL".
    case baselineControl
    /// Raw value: "BIND".
    case bind
    /// Raw value: "CHECKIN".
    case checkIn
    /// Raw value: "CHECKOUT".
    case checkOut
    /// Raw value: "CONNECT".
    case connect
    /// Raw value: "COPY".
    case copy
    /// Raw value: "DELETE".
    case delete
    /// Raw value: "PROPFIND".
    case findProperties
    /// Raw value: "GET".
    case get
    /// Raw value: "HEAD".
    case head
    /// Raw value: "LABEL".
    case label
    /// Raw value: "LINK".
    case link
    /// Raw value: "LOCK".
    case lock
    /// Raw value: "MKACTIVITY".
    case makeActiviy
    /// Raw value: "MKCALENDAR".
    case makeCalendar
    /// Raw value: "MKCOL".
    case makeCollection
    /// Raw value: "MKREDIRECTREF".
    case makeRedirectReference
    /// Raw value: "MKWORKSPACE".
    case makeWorkspace
    /// Raw value: "MERGE".
    case merge
    /// Raw value: "MOVE".
    case move
    /// Raw value: "OPTIONS".
    case options
    /// Raw value: "PATCH".
    case patch
    /// Raw value: "ORDERPATCH".
    case patchOrder
    /// Raw value: "PROPPATCH".
    case patchProperties
    /// Raw value: "POST".
    case post
    /// Raw value: "PUT".
    case put
    /// Raw value: "REBIND".
    case rebind
    /// Raw value: "REPORT".
    case report
    /// Raw value: "SEARCH".
    case search
    /// Raw value: "TRACE".
    case trace
    /// Raw value: "UNBIND".
    case unbind
    /// Raw value: "UNCHECKOUT".
    case uncheckout
    /// Raw value: "UNLINK".
    case unlink
    /// Raw value: "UNLOCK".
    case unlock
    /// Raw value: "UPDATE".
    case update
    /// Raw value: "UPDATEREDIRECTREF".
    case updateRedirectReference
    /// Raw value: "VERSION-CONTROL".
    case versionControl

    case raw(String)



    // MARK: Initialization

    /// Initializes an instance from given raw HTTP method value.
    /// If there is no case matching given raw value then `nil` is returned.
    ///
    /// - Tip: Use ``raw(_:)`` case to initialize instances for arbitrary HTTP methods.
    @inlinable
    public init?(rawValue: String) {
        switch rawValue {
        case "ACL":
            self = .accessControlList
        case "BASELINE-CONTROL":
            self = .baselineControl
        case "BIND":
            self = .bind
        case "CHECKIN":
            self = .checkIn
        case "CHECKOUT":
            self = .checkOut
        case "CONNECT":
            self = .connect
        case "COPY":
            self = .copy
        case "DELETE":
            self = .delete
        case "GET":
            self = .get
        case "HEAD":
            self = .head
        case "LABEL":
            self = .label
        case "LINK":
            self = .link
        case "LOCK":
            self = .lock
        case "MERGE":
            self = .merge
        case "MKACTIVITY":
            self = .makeActiviy
        case "MKCALENDAR":
            self = .makeCalendar
        case "MKCOL":
            self = .makeCollection
        case "MKREDIRECTREF":
            self = .makeRedirectReference
        case "MKWORKSPACE":
            self = .makeWorkspace
        case "MOVE":
            self = .move
        case "OPTIONS":
            self = .options
        case "ORDERPATCH":
            self = .patchOrder
        case "PATCH":
            self = .patch
        case "POST":
            self = .post
        case "PROPFIND":
            self = .findProperties
        case "PROPPATCH":
            self = .patchProperties
        case "PUT":
            self = .put
        case "REBIND":
            self = .rebind
        case "REPORT":
            self = .report
        case "SEARCH":
            self = .search
        case "TRACE":
            self = .trace
        case "UNBIND":
            self = .unbind
        case "UNCHECKOUT":
            self = .uncheckout
        case "UNLINK":
            self = .unlink
        case "UNLOCK":
            self = .unlock
        case "UPDATE":
            self = .update
        case "UPDATEREDIRECTREF":
            self = .updateRedirectReference
        case "VERSION-CONTROL":
            self = .versionControl
            
        default:
            return nil
        }
    }



    // MARK: Operations

    /// The receiver's raw HTTP method value.
    @inlinable
    public var rawValue: String {
        switch self {
        case .accessControlList:
            return "ACL"
        case .baselineControl:
            return "BASELINE-CONTROL"
        case .bind:
            return "BIND"
        case .checkIn:
            return "CHECKIN"
        case .checkOut:
            return "CHECKOUT"
        case .connect:
            return "CONNECT"
        case .copy:
            return "COPY"
        case .delete:
            return "DELETE"
        case .findProperties:
            return "PROPFIND"
        case .get:
            return "GET"
        case .head:
            return "HEAD"
        case .label:
            return "LABEL"
        case .link:
            return "LINK"
        case .lock:
            return "LOCK"
        case .makeActiviy:
            return "MKACTIVITY"
        case .makeCalendar:
            return "MKCALENDAR"
        case .makeCollection:
            return "MKCOL"
        case .makeRedirectReference:
            return "MKREDIRECTREF"
        case .makeWorkspace:
            return "MKWORKSPACE"
        case .merge:
            return "MERGE"
        case .move:
            return "MOVE"
        case .options:
            return "OPTIONS"
        case .patch:
            return "PATCH"
        case .patchOrder:
            return "ORDERPATCH"
        case .patchProperties:
            return "PROPPATCH"
        case .post:
            return "POST"
        case .put:
            return "PUT"
        case .rebind:
            return "REBIND"
        case .report:
            return "REPORT"
        case .search:
            return "SEARCH"
        case .trace:
            return "TRACE"
        case .unbind:
            return "UNBIND"
        case .uncheckout:
            return "UNCHECKOUT"
        case .unlink:
            return "UNLINK"
        case .unlock:
            return "UNLOCK"
        case .update:
            return "UPDATE"
        case .updateRedirectReference:
            return "UPDATEREDIRECTREF"
        case .versionControl:
            return "VERSION-CONTROL"

        case .raw(let rawValue):
            return rawValue
        }
    }


    /// "Safe" property of the receiver as in [HTTP Method Registry](https://www.iana.org/assignments/http-methods/http-methods.xhtml).
    /// It's `nil` for ``KvHttpMethod/raw(_:)`` case .
    @inlinable
    public var isSafe: Bool? {
        switch self {
        case .accessControlList, .baselineControl, .bind, .checkIn, .checkOut, .connect, .copy, .delete, .label, .link, .lock, .makeActiviy,
                .makeCalendar, .makeCollection, .makeRedirectReference, .makeWorkspace, .merge, .move, .patchOrder, .patch, .post,
                .patchProperties, .put, .rebind, .unbind, .uncheckout, .unlink, .unlock, .update, .updateRedirectReference, .versionControl:
            return false
        case .findProperties, .get, .head, .options, .report, .search, .trace:
            return true
        case .raw(_):
            return nil
        }
    }


    /// "Idempotent" property of the receiver as in [HTTP Method Registry](https://www.iana.org/assignments/http-methods/http-methods.xhtml).
    /// It's `nil` for ``KvHttpMethod/raw(_:)`` case .
    @inlinable
    public var isIdempotent: Bool? {
        switch self {
        case .accessControlList, .baselineControl, .bind, .checkIn, .checkOut, .copy, .delete, .findProperties, .get, .head, .label, .link,
                .makeActiviy, .makeCalendar, .makeCollection, .makeRedirectReference, .makeWorkspace, .merge, .move, .options, .patchOrder,
                .patchProperties, .put, .rebind, .report, .search, .trace, .unbind, .uncheckout, .unlink, .unlock, .update,
                .updateRedirectReference, .versionControl:
            return true
        case .connect, .lock, .patch, .post:
            return false
        case .raw(_):
            return nil
        }
    }



    // MARK: : CustomStringConvertible

    @inlinable
    public var description: String { rawValue }

}
