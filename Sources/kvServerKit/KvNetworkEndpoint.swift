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
//  KvNetworkEndpoint.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 14.07.2023.
//

import Foundation



/// Information required to establish network connection to the server.
///
/// It holds network address and port. Address can be a string representation of an IP address or the host name.
public struct KvNetworkEndpoint : Hashable, CustomStringConvertible {

    /// Type of network address.
    public typealias Address = String

    /// Type of port.
    public typealias Port = UInt16



    /// Address can be a string representation of an IP address or the host name. E.g. "localhost", "192.168.0.1", "::1".
    public var address: Address

    /// Ethernet port.
    public var port: Port



    /// Memberwise initializer
    @inlinable
    public init(_ address: Address, on port: Port) {
        self.address = address
        self.port = port
    }



    // MARK: Fabrics

    /// - Returns: An endpont where address is `"localhost"`.
    ///
    /// - SeeAlso: ``loopback(on:)``.
    @inlinable
    public static func localhost(on port: Port) -> KvNetworkEndpoint { .init("localhost", on: port) }


    /// - Returns: An endpoint where address is a loopback IPv6 address `::1`.
    ///
    /// - SeeAlso: ``localhost(on:)``, ``loopbackIPv4(on:)``.
    @inlinable
    public static func loopback(on port: Port) -> KvNetworkEndpoint { .init("::1", on: port) }


    /// - Returns: An endpoint where address is a loopback IPv4 address `127.0.0.1`.
    ///
    /// - SeeAlso: ``loopback(on:)``.
    @inlinable
    public static func loopbackIPv4(on port: Port) -> KvNetworkEndpoint { .init("127.0.0.1", on: port) }



    // MARK: System Endpoints

    // TODO: Migrate from deprecated `Host.current().addresses` to an up-to-date method.
    /// - Returns: Collection of addresses available on the machine.
    ///
    /// - SeeAlso: ``systemEndpoints(on:)``.
    public static var systemAddresses: AnySequence<String> { .init(Host.current().addresses) }


    /// - Returns: Collection of endpoints with available addresses on the machine.
    ///
    /// - SeeAlso: ``systemAddresses``.
    @inlinable
    public static func systemEndpoints(on port: Port) -> AnySequence<KvNetworkEndpoint> {
        .init(systemAddresses.lazy.map { .init($0, on: port) })
    }



    // MARK: : CustomStringConvertible

    public var description: String { "\(address):\(port)" }

}
