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
//  KvServerStopSignals.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 03.10.2023.
//

import Foundation

import kvKit



/// A helper signleton calling provided callback when process receives a stop signal.
///
/// See ``KvServer/start()`` and ``KvHttpServer/start()`` for an examples.
public struct KvServerStopSignals {

    public typealias Callback = (Int32) -> Void


    private init() { }


    private static var callback: (Callback)?


    // MARK: Operations

    /// Registers given *callback* for stop process signals.
    ///
    /// *Callback* is called once for first received signal. Then *callback* is cleared.
    ///
    /// - Important: Callback can be registered once. Other attempts will be ignored until a signal is received.
    public static func setCallback(_ callback: @escaping Callback) {
        guard self.callback == nil else { return KvDebug.pause("Attempt to register stop signal callback twice") }

        self.callback = callback

        [ SIGHUP, SIGINT, SIGQUIT, SIGTERM ].forEach {
            signal($0) { signal in
                KvServerStopSignals.runCallback(for: signal)
            }
        }
    }


    private static func runCallback(for signal: Int32) {
        guard let callback = self.callback else { return }

        callback(signal)

        self.callback = nil
    }

}
