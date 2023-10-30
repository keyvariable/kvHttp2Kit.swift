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
//  kvHttpKit_NIOHTTP1
//
//  Created by Svyatoslav Popov on 03.10.2023.
//

import kvHttpKit

import NIOHTTP1



extension KvHttpMethod {

    /// - Initializes an instance from value of `HTTPMethod`.
    @inlinable
    public init(from nioMethod: HTTPMethod) {
        switch nioMethod {
        case .ACL:
            self = .accessControlList
        case .BIND:
            self = .bind
        case .CHECKOUT:
            self = .checkOut
        case .CONNECT:
            self = .connect
        case .COPY:
            self = .copy
        case .DELETE:
            self = .delete
        case .GET:
            self = .get
        case .HEAD:
            self = .head
        case .LINK:
            self = .link
        case .LOCK:
            self = .lock
        case .MERGE:
            self = .merge
        case .MKACTIVITY:
            self = .makeActiviy
        case .MKCALENDAR:
            self = .makeCalendar
        case .MKCOL:
            self = .makeCollection
        case .MOVE:
            self = .move
        case .OPTIONS:
            self = .options
        case .PATCH:
            self = .patch
        case .POST:
            self = .post
        case .PROPFIND:
            self = .findProperties
        case .PROPPATCH:
            self = .patchProperties
        case .PUT:
            self = .put
        case .REBIND:
            self = .rebind
        case .REPORT:
            self = .report
        case .SEARCH:
            self = .search
        case .TRACE:
            self = .trace
        case .UNBIND:
            self = .unbind
        case .UNLINK:
            self = .unlink
        case .UNLOCK:
            self = .unlock

        case .MSEARCH, .NOTIFY, .PURGE, .SOURCE, .SUBSCRIBE, .UNSUBSCRIBE:
            let rawValue = nioMethod.rawValue
            self = KvHttpMethod(rawValue: rawValue) ?? .raw(rawValue)

        case .RAW(let rawValue):
            self = KvHttpMethod(rawValue: rawValue) ?? .raw(rawValue)
        }
    }



    // MARK: Operations

    /// Instance of `HTTPMethod` corresponding to the receiver.
    @inlinable
    public var nioMethod: HTTPMethod {
        switch self {
        case .accessControlList:
            return .ACL
        case .bind:
            return .BIND
        case .checkOut:
            return .CHECKOUT
        case .connect:
            return .CONNECT
        case .copy:
            return .COPY
        case .delete:
            return .DELETE
        case .findProperties:
            return .PROPFIND
        case .get:
            return .GET
        case .head:
            return .HEAD
        case .link:
            return .LINK
        case .lock:
            return .LOCK
        case .makeActiviy:
            return .MKACTIVITY
        case .makeCalendar:
            return .MKCALENDAR
        case .makeCollection:
            return .MKCOL
        case .merge:
            return .MERGE
        case .move:
            return .MOVE
        case .options:
            return .OPTIONS
        case .patch:
            return .PATCH
        case .patchProperties:
            return .PROPPATCH
        case .post:
            return .POST
        case .put:
            return .PUT
        case .rebind:
            return .REBIND
        case .report:
            return .REPORT
        case .search:
            return .SEARCH
        case .trace:
            return .TRACE
        case .unbind:
            return .UNBIND
        case .unlink:
            return .UNLINK
        case .unlock:
            return .UNLOCK

        case .baselineControl, .checkIn, .label, .makeRedirectReference, .makeWorkspace, .patchOrder, .uncheckout, .update,
                .updateRedirectReference, .versionControl:
            return .init(rawValue: rawValue)

        case .raw(let rawValue):
            return .RAW(value: rawValue)
        }
    }

}
