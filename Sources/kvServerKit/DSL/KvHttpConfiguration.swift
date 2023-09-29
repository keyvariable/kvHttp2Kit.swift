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
//  KvHttpConfiguration.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 29.09.2023.
//

import Foundation



/// Parameters of HTTP connection on an end-point.
///
/// Consider fabrics and modfiers providing ability to build configurations:
///
///     .v2(ssl: ssl).connection(requestLimit: 256)
///
public struct KvHttpConfiguration : Equatable {

    public typealias Connection = KvHttpChannel.Configuration.Connection
    public typealias HTTP = KvHttpChannel.Configuration.HTTP
    public typealias SSL = KvHttpChannel.Configuration.SSL


    public static let `default` = Self()


    public var http: HTTP
    public var connection: Connection


    @inlinable
    public init(http: HTTP = KvHttpChannel.Configuration.Defaults.http,
                connection: Connection = .init()
    ) {
        self.http = http
        self.connection = connection
    }


    // MARK: Fabrics

    /// - Returns: A configuration with ``http`` property set to HTTP/1.1 with optional *ssl* configuration.
    @inlinable
    public static func v1_1(ssl: SSL? = nil) -> Self { .init(http: .v1_1(ssl: ssl)) }

    /// - Returns: A configuration with ``http`` property set to HTTP/2.0 with givel *ssl* configuration.
    @inlinable
    public static func v2(ssl: SSL) -> Self { .init(http: .v2(ssl: ssl)) }


    // MARK: Modifiers

    /// - Returns: A copy of the receiver where ``http`` propetry is replaced with new *value*.
    @inlinable
    public func http(_ value: HTTP) -> Self {
        modified {
            $0.http = value
        }
    }


    /// - Returns: A copy of the receiver where ``connection`` propetry is merged with new *value*.
    @inlinable
    public func connection(_ value: Connection) -> Self {
        modified {
            $0.connection = .init(lhs: $0.connection, rhs: value)
        }
    }


    /// - Returns: A copy of the receiver where ``connection`` propetry is merged with new values.
    @inlinable
    public func connection(idleTimeInterval: TimeInterval? = nil, requestLimit: UInt? = nil) -> Self {
        connection(.init(idleTimeInterval: idleTimeInterval, requestLimit: requestLimit))
    }


    // MARK: Auxiliaries

    @inline(__always)
    @usableFromInline
    func modified(_ block: (inout Self) -> Void) -> Self {
        var copy = self
        block(&copy)
        return copy
    }

}
