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
//  DeclarativeServer.swift
//  DeclarativeServer
//
//  Created by Svyatoslav Popov on 03.07.2023.
//

import kvServerKit

import Foundation



/// This sample server provides examples of various features of *kvServerKit* framework.
/// It's implemented in declarative way.
///
/// - Note: `@main` attribute.
///         See [documentation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/attributes/#main) for details.
///         When server is executed via `@main` attribute, it automatically stops when *SIGINT*, *SIGTERM*, *SIGQUIT* or *SIGHUP* process signal is received.
///         E.g. *SIGINT* is sent when Ctrl+C is pressed, *SIGQUIT* on Ctrl+\\, *SIGTERM* is usually sent by `kill` command by default.
@main
struct DeclarativeServer : KvServer {

    private static let resourceDirectory = "Resources"


    // MARK: : KvServer

    var body: some KvResponseGroup {
        let ssl = try! ssl

        /// This declaration makes it's HTTP responses to be available at all the current machine's IP addresses on port 8080.
        /// E.g. if the machine has "192.168.0.2" IP address then the server is available at "https://192.168.0.2:8080" URL.
        ///
        /// `http: .v2(ssl: ssl)` argument instructs the server to use secure HTTP/2.0 protocol.
        ///
        /// Port 8080 is used due to access to standard HTTP port 80 is probably denied.
        /// Besides, real hosting providers usuasy provide specific address and port for internet connections.
        ///
        /// Host names can be used as addresses. For example:
        ///
        ///     KvGroup(http: .v2(ssl: ssl), at: Host.current().names, on: [ 8080 ])
        ///
        KvGroup(http: .v2(ssl: ssl), at: Host.current().addresses, on: [ 8080 ]) {
            /// Static responses ignore any request context like URL and HTTP method.
            KvHttpResponse.static {
                .string("Hello! It's a sample server on declarative API of kvServerKit framework")
            }

            /// Dynamic responses depend on request context.
            /// For example the response below uses structured query handling.
            KvHttpResponse.dynamic
                /// The modifier adds required string value of query item named `name` to the response context.
                .query(.required("name"))
                .content { context in
                    let name = context.query.trimmingCharacters(in: .whitespacesAndNewlines)
                    return .string("Hello, \(!name.isEmpty ? name : "client")!")
                }

            /// Groups with single unlabeled string argument provide paths to responses.
            /// All the contents of the group below will be available at /random path.
            KvGroup("random") {
                /// The contents of the group below will be available ar /random/int path.
                KvGroup("int") {
                    KvHttpResponse.dynamic
                        /// Arguments can be optional.
                        /// Also arguments can be decoded like shown below when the type conforms to `LosslessStringConvertible`.
                        /// Custom decoding block can be provided too.
                        .query(.optional("from", of: Int.self))
                        /// This modifier adds second optional value to the context.
                        .query(.optional("through", of: Int.self))
                        /// Query values can be transformed and filtered like below to simplify final `.content` statement.
                        .queryFlatMap { from, through -> QueryResult<ClosedRange<Int>> in
                            let lowerBound = from ?? .min, upperBound = through ?? .max
                            return lowerBound <= upperBound ? .success(lowerBound ... upperBound) : .failure
                        }
                        /// Now `$0.query` is the range.
                        .content {
                            .string("\(Int.random(in: $0.query))")
                        }
                }

                KvGroup("uuid") {
                    KvHttpResponse.dynamic
                        /// Boolean query items handle various cases of URL query item values.
                        .query(.bool("string"))
                        /// - Note: Content of response depends on query flag.
                        .content { context in
                            let uuid = UUID()

                            switch context.query {
                            case true:
                                return .string(uuid.uuidString)
                            case false:
                                return withUnsafeBytes(of: uuid, { buffer in
                                    return .binary(buffer)
                                })
                            }
                        }
                }
            }
            /// Custom 404 usage response for "/random" path is provided with an incident handler.
            .onHttpIncident { incident in
                switch incident.defaultStatus {
                case .notFound:
                    return .notFound.string("Usage:\n  - /random/int[?from=1[&through=5]];\n  - /random/uuid[?string].")
                default:
                    return nil
                }
            }

            /// Path groups can contain separators.
            /// Declarations having common path prefixes or equal paths are correctly merged.
            KvGroup("random/int") {
                /// Responses and response groups can be wrapped in properties and functions.
                /// Wrapped responses can depend on arguments.
                ///
                /// - Note: Wrapped responses can be reused.
                randomIntArrayResponse(limit: 64)
            }

            KvGroup("math") {
                /// Note how hesponse groups are wrapped in a computed property.
                mathResponses
            }

            KvGroup("first") {
                /// Note the way arbitrary queries can be handled.
                KvHttpResponse.dynamic
                    /// Value of first URL query item is returned or an empty string.
                    /// If some queries should be declined then `queryFlatMap()` modifier can be used.
                    .queryMap { queryItems in
                        (queryItems?.first).map { "\"\($0.value ?? "")\"" } ?? "nil"
                    }
                    .content {
                        .string($0.query)
                    }
            }

            /// Responses and response groups can be wrapped to types.
            /// In the expample below group of responses depend on argument type and reused to provide different agrument handling.
            KvGroup("range") {
                KvGroup("uint") {
                    RangeResponses<UInt>()
                }
                KvGroup("double") {
                    RangeResponses<Double>()
                }
            }

            KvGroup("random/bytes") {
                /// See the way to use buffered output instead of collecting entire response body.
                randomBytesResponse
            }

            /// Handling of request body.
            KvGroup("body") {
                KvGroup("echo") {
                    /// This response returns binary data provided in the request body.
                    KvHttpResponse.dynamic
                        /// This modifier and the argument provide collecting of data before content is produced.
                        ///
                        /// - Note: The result is optional. Request is not discarded if it has no body.
                        .requestBody(.data)
                        .content { context in
                            guard let data: Data = context.requestBody else { return .badRequest }
                            return .binary(data)
                        }
                }
                KvGroup("bytesum") {
                    /// This response returns plain text representation of cyclic sum of bytes in a request body.
                    KvHttpResponse.dynamic
                        /// This modifier and the argument provide processing of the body on the fly as each portion of the data becomes available.
                        /// This way helps to minimize memory consumption and optimize performance of requests having large bodies.
                        ///
                        /// - Note: Initial value is provided when the request has no body.
                        .requestBody(.reduce(0 as UInt8, { accumulator, buffer in
                            buffer.reduce(accumulator, &+)
                        }))
                        .content {
                            .string("0x" + String($0.requestBody, radix: 16, uppercase: true))
                        }
                }
            }
            /// Responses in the group above are provided for HTTP requests with POST method only.
            ///
            /// - Note: Responses are available for any HTTP method by default.
            .httpMethods(.POST)
            /// Length limit of HTTP request bodies for responses in the group above is increased to 256 KiB.
            /// This limit also can be declared in a request this way: `.requestBody(.data.bodyLengthLimit(65_536))`.
            /// Default limit is ``kvServerKit/KvHttpRequest/Constants/bodyLengthLimit``.
            /// Responses without HTTP request body handling always have zero body limit.
            ///
            /// - Note: If an HTTP request has body exceeding the limit then 413 (Payload Too Large) status is returned by default.
            .httpBodyLengthLimit(256 << 10)

            /// Example of responses processing JSON entites available at the same path by for different HTTP methods.
            KvGroup("date") {
                /// The limited availability feature is supported in `KvResponseGroupBuilder` result builder.
                if #available(macOS 12.0, *) {
                    KvGroup(httpMethods: .POST) {
                        /// Returns ISO 8601 representation of date components in JSON format.
                        KvHttpResponse.dynamic
                            /// This modifier and the argument provide decoding of the request data as given decodable type.
                            ///
                            /// - Note: Decoding errors are handled automatically and 400 (bad request) response is produced.
                            .requestBody(.json(of: DateComponents.self))
                            .content {
                                guard let date = $0.requestBody.date else { return .badRequest }
                                return .string(ISO8601DateFormatter().string(from: date))
                            }
                    }
                }
                KvGroup(httpMethods: .GET) {
                    /// Returns JSON representation of current date.
                    KvHttpResponse.static {
                        do {
                            return try .json(Calendar.current.dateComponents(
                                [ .calendar, .year, .month, .day, .hour, .minute, .second, .nanosecond, .timeZone ],
                                from: Date())
                            )
                        }
                        catch { return .internalServerError.string("\(error)") }
                    }
                }
            }

            /// This response group provides contents of available images in the bundle.
            /// See it's implementation for the way to provide dynamic list of responses with `KvForEach()`.
            BundleImageResponses()
        }
        /// Custom global 404 response is provided with an incident handler.
        .onHttpIncident { incident in
            switch incident.defaultStatus {
            case .notFound:
                return .notFound.string("Unexpected request (404)\n\nSee implementation of `DeclarativeServer.body` for supported requests.")
            default:
                return nil
            }
        }

    }


    /// In this example self-signed certificate from the bundle is used to provide HTTPs.
    ///
    /// - Warning: Don't use this certificate in your projects.
    private var ssl: KvHttpChannel.Configuration.SSL {
        get throws {
            let fileName = "https"
            let fileExtension = "pem"

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            let pemPath = Bundle.module.url(forResource: fileName, withExtension: fileExtension, subdirectory: Self.resourceDirectory)!.path
#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
            // - NOTE: Currently there is a bug in opensource `Bundle.module.url(forResource:withExtension:subdirectory:)`.
            //         So assuming that application is launched with `swift run` shell command in directory containing the package file.
            let pemPath = "./Sources/DeclarativeServer/\(Self.resourceDirectory)/\(fileName).\(fileExtension)"
#endif // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))

            return try .init(pemPath: pemPath)
        }
    }


    /// Responses can be wrapped in properties and functions. Responses can depend on arguments.
    private func randomIntArrayResponse(limit: Int) -> some KvResponse {
        KvHttpResponse.dynamic
            .query(.required("count", of: Int.self))
            .content { context in
                let count = context.query

                // Note the way text responses with 400 status code are produced.
                guard count >= 0 else { return .badRequest.string("Invalid argument: count (\(count)) is negative") }
                guard count <= limit else { return .badRequest.string("Invalid argument: count (\(count)) is too large") }

                // Response is a JSON array.
                do { return try .json((0..<count).lazy.map { _ in Int.random(in: .min ... .max) }) }
                catch { return .internalServerError.string("Failed to encode JSON. \(error)") }
            }
    }


    /// Response groups can be wrappped in properties and functions.
    ///
    /// - Note: `@KvResponseGroupBuilder` attribute is used to combite multiple components.
    @KvResponseGroupBuilder
    private var mathResponses: some KvResponseGroup {
        KvGroup("add") {
            KvHttpResponse.dynamic
                .query(.required("lhs", of: Double.self))
                .query(.required("rhs", of: Double.self))
                .content { .string("\($0.query.0 + $0.query.1)") }
        }
        KvGroup("sub") {
            KvHttpResponse.dynamic
                .query(.required("lhs", of: Double.self))
                .query(.required("rhs", of: Double.self))
                .content { .string("\($0.query.0 - $0.query.1)") }
        }
    }


    /// Responses and response groups can be wrapped to types.
    ///
    /// This structure wraps three unambiguous responses at the same path producing correct result for any valid input.
    private struct RangeResponses<Value> : KvResponseGroup
    where Value : LosslessStringConvertible & Comparable
    {

        /// - Note: Three responses at the same path are unambiguous and produce correct result for any valid input.
        var body: some KvResponseGroup {
            KvHttpResponse.dynamic
                .query(.required("from", of: Value.self))
                .query(.optional("to", of: Value.self))
                .content {
                    switch $0.query {
                    case (let from, .none):
                        return .string("\(from) ...")
                    case (let from, .some(let to)):
                        guard from <= to else { return .badRequest.string("Invalid arguments: `from` (\(from)) must be less than or equal to `to` (\(to))") }
                        return .string("\(from) ..< \(to)")
                    }
                }

            KvHttpResponse.dynamic
                .query(.required("to", of: Value.self))
                .content {
                    .string("..< \($0.query)")
                }

            KvHttpResponse.dynamic
                .query(.optional("from", of: Value.self))
                .query(.required("through", of: Value.self))
                .content {
                    switch $0.query {
                    case (.none, let through):
                        return .string("... \(through)")
                    case (.some(let from), let through):
                        guard from <= through else { return .badRequest.string("Invalid arguments: `from` (\(from)) must be less than or equal to `through` (\(through))") }
                        return .string("\(from) ... \(through)")
                    }
                }
        }

    }


    /// Example of buffered output instead of collecting entire response body.
    private var randomBytesResponse: some KvResponse {
        KvHttpResponse.dynamic
            /// See custom parser providing additional validation.
            .query(.required("count", parseBlock: { rawValue -> KvUrlQueryParseResult<Int> in
                guard let value = rawValue.flatMap(Int.init(_:)), value > 0 else { return .failure }
                return .success(value)
            }))
            .content {
                var count = $0.query

                return .bodyCallback { buffer in
                    let bytesToWrite = min(count, buffer.count)

                    guard bytesToWrite > 0 else { return .success(0) }

                    buffer.copyBytes(from: (0 ..< bytesToWrite).lazy.map { _ in UInt8.random(in: .min ... .max) })
                    count -= bytesToWrite

                    return .success(bytesToWrite)
                }
            }
    }


    /// This response group provides contents of available images in the bundle.
    /// See how `KvForEach()` and file streams are used.
    private struct BundleImageResponses : KvResponseGroup {

        var body: some KvResponseGroup {
            /// - Note: Conditional statements are supported.
            if let urls = imageURLs {
                KvGroup("images") {
                    /// `KvForEach()` is used to provide dynamic list of responses.
                    /// Also it can be used to provide responses for all cases of an enumeration.
                    KvForEach(urls) { url in
                        KvGroup(url.lastPathComponent) {
                            KvHttpResponse.static {
                                guard let stream = InputStream(url: url) else { return .internalServerError }
                                // Use of file streams helps to reduce memory consumption and improve performance.
                                // Note the way response is composed providing body from a stream and PNG content type.
                                return .binary(stream).contentType(.image(.png))
                            }
                        }
                    }
                }
            }
        }

        private var imageURLs: [URL]? {
            // - NOTE: Currently there is a bug in opensource `Bundle.module.urls(forResourcesWithExtension:subdirectory:)`.
            //         So this response is implemented only on platforms listed below.
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            return Bundle.module.urls(forResourcesWithExtension: "png", subdirectory: "Resources")
#else // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
            return try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "./Sources/DeclarativeServer/\(DeclarativeServer.resourceDirectory)/"), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "png" }
#endif // !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
        }

    }

}
