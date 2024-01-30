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
//  App.swift
//  ImperativeServer
//
//  Created by Svyatoslav Popov on 06.09.2023.
//

import kvServerKit

import Foundation



@main
struct App {

    static func main() async throws {
        let ssl = try ssl

        /// In this example channel configurations are created for each current machine's IP address on port 8080.
        /// E.g. if the machine has "192.168.0.2" IP address then the server is available at "https://192.168.0.2:8080" URL.
        ///
        /// `http: .v2(ssl: ssl)` argument instructs the server to use secure HTTP/2.0 protocol.
        ///
        /// Port 8080 is used due to access to standard HTTP port 80 is probably denied.
        /// Besides, real hosting providers usually provide specific address and port for internet connections.
        ///
        /// - Note: Host names can be used as addresses.
        let configurations = KvNetworkEndpoint.systemAddresses
            .lazy.map { address in KvHttpChannel.Configuration(endpoint: .init(address, on: 8080), http: .v2(ssl: ssl)) }

        let server = ImperativeServer(with: configurations)

        try server.start()

        /// Code below is optional. It's a way to wait for all server's channels are started.
        do {
            /// `channel.waitWhileStarting()` below can fail due to channels may be is in *stopped* state until server is completely started.
            /// So we wait while server is starting and then wait while channels are starting.
            try server.waitWhileStarting().get()
            try await server.forEachChannel { channel in
                try channel.waitWhileStarting().get()

                print("Channel has started: \(channel.endpointURLs!)")
            }
            print("Server has started")
        }

        /// Servers usually run in the background and stop on process signals.
        KvServerStopSignals.setCallback { _ in
            server.stop()
            print("Server is being stopped...")
        }
        
        print("Press Ctrl+C or run `kill \(ProcessInfo.processInfo.processIdentifier)` command to stop server normally")

        try server.waitUntilStopped().get()
        print("Server has stopped")
    }


    /// In this example self-signed certificate from the bundle is used to provide HTTPs.
    ///
    /// - Warning: Don't use this certificate in your projects.
    private static var ssl: KvHttpChannel.Configuration.SSL {
        get throws {
            let pemPath = Bundle.module.url(forResource: "https", withExtension: "pem")!.path

            return try .init(pemPath: pemPath)
        }
    }

}




