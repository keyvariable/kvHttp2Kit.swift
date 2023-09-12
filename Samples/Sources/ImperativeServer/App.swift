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
        /// Besides, real hosting providers usuasy provide specific addressa and port for internet connections.
        ///
        /// - Note: Host names can be used as addresses.
        let configurations = Host.current().addresses
            .lazy.map { address in KvHttpChannel.Configuration(endpoint: .init(address, on: 8080), http: .v2(ssl: ssl)) }

        let server = ImperativeServer(with: configurations)

        try server.start()

        // Code below is optional. It's a way to wait for all server's channels are started.
        do {
            try await server.forEachChannel { channel in
                try channel.waitWhileStarting().get()

                print("Channel has started: \(channel.endpointURLs!)")
            }
            print("Server has started")
        }

        // In this example server is operating until any key is pressed.
        print("Press any key to stop server")
        _ = getchar()

        server.stop()

        print("Server is being stopped...")
        try server.waitUntilStopped().get()
        print("Server has stopped")
    }


    /// In this example self-signed certificate from the bundle is used to provide HTTPs.
    ///
    /// - Warning: Don't use this certificate in your projects.
    private static var ssl: KvHttpChannel.Configuration.SSL {
        get throws {
            let resourceDirectory = "Resources"
            let fileName = "https"
            let fileExtension = "pem"

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            let pemPath = Bundle.module.url(forResource: fileName, withExtension: fileExtension, subdirectory: resourceDirectory)!.path
#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
            // - NOTE: Currently there is a bug in opensource `Bundle.module.url(forResource:withExtension:subdirectory:)`.
            //         So assuming that application is launched with `swift run` shell command in directory containing the package file.
            let pemPath = "./Sources/ImperativeServer/\(resourceDirectory)/\(fileName).\(fileExtension)"
#endif // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))

            return try .init(pemPath: pemPath)
        }
    }

}




