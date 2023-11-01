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
//  KvClientCallbacks.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 22.10.2023.
//

import kvHttpKit



/// Callbacks handling issues from ``KvHttpChannel/Client``.
@usableFromInline
struct KvClientCallbacks : KvCascadable, KvReplacingOverlayCascadable, KvDefaultAccumulationCascadable {

    @usableFromInline
    typealias ErrorCallback = (Error, KvHttpRequestContext) -> Void

    @usableFromInline
    typealias IncidentCallback = (KvHttpIncident, KvHttpRequestContext) -> KvHttpResponseContent?


    /// Handles incidents.
    @usableFromInline
    var onHttpIncident: IncidentCallback?

    /// Handles errors from clients and requests.
    @usableFromInline
    var onError: ErrorCallback?


    @usableFromInline
    init(onHttpIncident: IncidentCallback? = nil, onError: ErrorCallback? = nil) {
        self.onHttpIncident = onHttpIncident
        self.onError = onError
    }


    // MARK: : KvCascadable

    @usableFromInline
    static func accumulate(_ addition: Self, into base: Self) -> Self {
        .init(onHttpIncident: addition.onHttpIncident ?? base.onHttpIncident,
              onError: addition.onError ?? base.onError)
    }

}
