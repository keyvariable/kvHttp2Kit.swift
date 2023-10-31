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

import kvHttpKit
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

    // MARK: : KvServer

    var body: some KvResponseRootGroup {
        let ssl = try! ssl

        /// This declaration makes it's HTTP responses to be available at all the current machine's IP addresses on port 8080.
        /// E.g. if the machine has "192.168.0.2" IP address then the server is available at "https://192.168.0.2:8080" URL.
        ///
        /// `http: .v2(ssl: ssl)` argument instructs the server to use secure HTTP/2.0 protocol.
        ///
        /// Port 8080 is used due to access to standard HTTP port 80 is probably denied.
        /// Besides, real hosting providers usually provide specific address and port for internet connections.
        ///
        /// Host names can be used as addresses. For example:
        /// ```swift
        /// KvGroup(http: .v2(ssl: ssl), at: Host.current().names, on: [ 8080 ])
        /// ```
        KvGroup(http: .v2(ssl: ssl), at: Host.current().addresses, on: [ 8080 ]) {
            /// A hierarchy of files at some URL can be declared with just URL.
            /// It's a good way to declare frontends and resource directories.
            /// This directory is declared at the root of server's response hierarchy, so entire URL paths in requests are appended to the directory's root URL.
            /// Directory declarations provide automatic searching of the index files.
            /// Also directory declarations via URL provide automatic search of "Status" or "status" subdirectory
            /// to provide non-200 responses from files named "\(statusCode).html".
            /// See `KvDirectory` and `KvFiles` for details.
            Bundle.module.resourceURL!.appendingPathComponent("Frontend")

            /// Parameterized responses provide customizable processing of request content.
            /// For example the response below uses structured URL query handling.
            KvHttpResponse.with
                /// This modifier adds required string value of query item named `name` to the response input.
                .query(.required("name"))
                .content { input in
                    let name = input.query.trimmingCharacters(in: .whitespacesAndNewlines)
                    return .string { "Hello, \(!name.isEmpty ? name : "client")!" }
                }

            /// Groups with single unlabeled string argument provide paths to responses.
            /// All the contents of the group below will be available at /generate path.
            KvGroup("generate") {
                /// The contents of the group below will be available at /generate/int path.
                KvGroup("int") {
                    KvHttpResponse.with
                        /// Arguments can be optional.
                        /// Also arguments can be decoded like shown below when the type conforms to `LosslessStringConvertible`.
                        /// Custom decoding block can be provided too.
                        .query(.optional("from", of: Int.self))
                        /// This modifier adds second optional value to the input.
                        .query(.optional("through", of: Int.self))
                        /// Query values can be transformed and filtered like below to simplify final `.content` statement.
                        .queryFlatMap { from, through -> QueryResult<ClosedRange<Int>> in
                            let lowerBound = from ?? .min, upperBound = through ?? .max
                            return lowerBound <= upperBound ? .success(lowerBound ... upperBound) : .failure
                        }
                        /// Now `input.query` is the range.
                        .content { input in .string { "\(Int.random(in: input.query))" } }
                }

                KvGroup("uuid") {
                    KvHttpResponse.with
                        /// Boolean query items handle various cases of URL query item values.
                        .query(.bool("string"))
                        /// - Note: Content of response depends on query flag.
                        .content { input in
                            let uuid = UUID()

                            switch input.query {
                            case true:
                                return .string { uuid.uuidString }
                            case false:
                                return withUnsafeBytes(of: uuid, { buffer in
                                    return .binary { buffer }
                                })
                            }
                        }
                }
            }
            /// Custom 404 usage response for "/generate" path is provided with an incident handler.
            .onHttpIncident { incident, context in
                switch incident.defaultStatus {
                case .notFound:
                    var prefixComponents = context.urlComponents
                    prefixComponents.path = "/generate"
                    prefixComponents.query = nil
                    let prefix = prefixComponents.url?.absoluteString ?? ""
                    return .notFound.string { "Usage:\n  - \(prefix)/int[?from=1[&through=5]];\n  - \(prefix)/int?count=10;\n  - \(prefix)/uuid[?string]." }
                default:
                    return nil
                }
            }

            /// Path groups can contain separators.
            /// Declarations having common path prefixes or equal paths are correctly merged.
            KvGroup("generate/int") {
                /// Responses and response groups can be wrapped in properties and functions.
                /// Wrapped responses can depend on arguments.
                ///
                /// - Note: Wrapped responses can be reused.
                randomIntArrayResponse(limit: 64)
            }

            KvGroup("math") {
                /// Note how response groups are wrapped in a computed property.
                mathResponses
            }

            KvGroup("first") {
                /// Note the way arbitrary queries can be handled.
                KvHttpResponse.with
                    /// Value of first URL query item is returned or an empty string.
                    /// If some queries should be declined then `queryFlatMap()` modifier can be used.
                    .queryMap { queryItems in
                        (queryItems?.first).map { "\"\($0.value ?? "")\"" } ?? "nil"
                    }
                    .content { input in .string { input.query } }
            }

            /// Responses and response groups can be wrapped to types.
            /// In the example below group of responses depends on argument type and reused to provide different argument handling.
            KvGroup("range") {
                KvGroup("uint") {
                    RangeResponses<UInt>()
                }
                KvGroup("double") {
                    RangeResponses<Double>()
                }
            }

            KvGroup("generate/bytes") {
                /// See the way to use buffered output instead of collecting entire response body.
                randomBytesResponse
            }

            /// Handling of request body.
            KvGroup("body") {
                KvGroup("echo") {
                    /// This response returns binary data provided in the request body.
                    KvHttpResponse.with
                        /// This modifier and the argument provide collecting of data before it is processed.
                        ///
                        /// - Note: The resulting body value is optional. It's `nil` when request has no body.
                        .requestBody(.data)
                        .content { input in
                            guard let data: Data = input.requestBody else { return .badRequest }
                            return .binary({ data }).contentLength(data.count)
                        }
                }
                KvGroup("bytesum") {
                    /// This response returns plain text representation of cyclic sum of bytes in a request body.
                    KvHttpResponse.with
                        /// This modifier and the argument provide processing of the body on the fly as each portion of the data becomes available.
                        /// This way helps to minimize memory consumption and optimize performance of requests having large bodies.
                        ///
                        /// - Note: Initial value is provided when the request has no body.
                        .requestBody(.reduce(0 as UInt8, { accumulator, buffer in
                            buffer.reduce(accumulator, &+)
                        }))
                        .content { input in .string { "0x" + String(input.requestBody, radix: 16, uppercase: true) } }
                }
            }
            /// Responses in the group above are provided for HTTP requests with POST method only.
            ///
            /// - Note: Responses are available for any HTTP method by default.
            .httpMethods(.post)
            /// Length limit of HTTP request bodies for responses in the group above is increased to 256 KiB.
            /// This limit also can be declared in a request this way: `.requestBody(.data.bodyLengthLimit(65_536))`.
            /// Default limit is ``kvServerKit/KvHttpRequest/Constants/bodyLengthLimit``.
            /// Responses without HTTP request body handling always have zero body limit.
            ///
            /// - Note: If an HTTP request has body exceeding the limit then 413 (Payload Too Large) status is returned by default.
            .httpBodyLengthLimit(256 << 10)

            /// Example of responses processing JSON entities available at the same path by for different HTTP methods.
            KvGroup("date") {
                /// The limited availability feature is supported in `KvResponseGroupBuilder` result builder.
                /// This availability check is for `ISO8601DateFormatter`.
                if #available(macOS 12.0, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
                    KvGroup(httpMethods: .post) {
                        /// Returns ISO 8601 representation of date components in JSON format.
                        KvHttpResponse.with
                            /// This modifier and the argument provide decoding of the request data as given decodable type.
                            ///
                            /// - Note: Decoding errors are handled automatically and 400 (bad request) response is produced.
                            .requestBody(.json(of: DateComponents.self))
                            .content {
                                guard let date = $0.requestBody.date else { return .badRequest }
                                return .string { ISO8601DateFormatter().string(from: date) }
                            }
                    }
                }
                KvGroup(httpMethods: .get) {
                    /// Returns JSON representation of current date.
                    KvHttpResponse {
                        .json {
                            Calendar.current.dateComponents(
                                [ .calendar, .year, .month, .day, .hour, .minute, .second, .nanosecond, .timeZone ],
                                from: Date()
                            )
                        }
                    }
                }
            }

            /// This response group provides contents of available images in the bundle.
            /// See it's implementation for the way to provide dynamic list of responses with `KvForEach()`.
            BundleImageResponses()

            KvGroup("entities") {
                /// It's a simple example of managing a database of sample entities.
                /// It responds with:
                /// - entity at "/entities/$id" path where $id is an identifier of existing entity;
                /// - array of entities at "/entities";
                /// - top-rated entity "/entities/top".
                EntityResponseGroup()
            }
        }
    }


    /// In this example self-signed certificate from the bundle is used to provide HTTPs.
    ///
    /// - Warning: Don't use this certificate in your projects.
    private var ssl: KvHttpChannel.Configuration.SSL {
        get throws {
            let pemPath = Bundle.module.url(forResource: "https", withExtension: "pem")!.path

            return try .init(pemPath: pemPath)
        }
    }


    /// Responses can be wrapped in properties and functions. Responses can depend on arguments.
    private func randomIntArrayResponse(limit: Int) -> some KvResponse {
        KvHttpResponse.with
            .query(.required("count", of: Int.self))
            .content { input in
                let count = input.query

                // Note the way text responses with 400 status code are produced.
                guard count >= 0 else { return .badRequest.string { "Invalid argument: count (\(count)) is negative" } }
                guard count <= limit else { return .badRequest.string { "Invalid argument: count (\(count)) is too large" } }

                // Response is a JSON array.
                return .json { (0..<count).lazy.map { _ in Int.random(in: .min ... .max) } }
            }
    }


    /// Response groups can be wrapped in properties and functions.
    ///
    /// - Note: `@KvResponseGroupBuilder` attribute is used to combine multiple components.
    @KvResponseGroupBuilder
    private var mathResponses: some KvResponseGroup {
        KvGroup("add") {
            KvHttpResponse.with
                .query(.required("lhs", of: Double.self))
                .query(.required("rhs", of: Double.self))
                .content { input in .string { "\(input.query.0 + input.query.1)" } }
        }
        KvGroup("sub") {
            KvHttpResponse.with
                .query(.required("lhs", of: Double.self))
                .query(.required("rhs", of: Double.self))
                .content { input in .string { "\(input.query.0 - input.query.1)" } }
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
            KvHttpResponse.with
                .query(.required("from", of: Value.self))
                .query(.optional("to", of: Value.self))
                .content {
                    switch $0.query {
                    case (let from, .none):
                        return .string { "\(from) ..." }
                    case (let from, .some(let to)):
                        guard from <= to else { return .badRequest.string { "Invalid arguments: `from` (\(from)) must be less than or equal to `to` (\(to))" } }
                        return .string { "\(from) ..< \(to)" }
                    }
                }

            KvHttpResponse.with
                .query(.required("to", of: Value.self))
                .content { input in .string { "..< \(input.query)" } }

            KvHttpResponse.with
                .query(.optional("from", of: Value.self))
                .query(.required("through", of: Value.self))
                .content {
                    switch $0.query {
                    case (.none, let through):
                        return .string { "... \(through)" }
                    case (.some(let from), let through):
                        guard from <= through else { return .badRequest.string { "Invalid arguments: `from` (\(from)) must be less than or equal to `through` (\(through))" } }
                        return .string { "\(from) ... \(through)" }
                    }
                }
        }

    }


    /// Example of buffered output instead of collecting entire response body.
    private var randomBytesResponse: some KvResponse {
        KvHttpResponse.with
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
            ///
            /// - Tip: `KvForEach()` is used as example. The same result can be archived with shorter code: `KvGroup("images") { imageURLs }`.
            if let urls = (Bundle.module.urls(forResourcesWithExtension: "png", subdirectory: nil) as [URL]?) {
                KvGroup("images") {
                    /// `KvForEach()` is used to provide dynamic list of responses.
                    /// Also it can be used to provide responses for all cases of an enumeration.
                    KvForEach(urls) { url in
                        KvGroup(url.lastPathComponent) {
                            KvHttpResponse {
                                /// Use of `.file` fabric and modifier helps to reduce memory consumption and improve performance.
                                /// Also consider `.binary`  fabric and modifier for input streams.
                                try .file(at: url).contentType(.image(.png))
                            }
                        }
                    }
                }
            }
        }

    }


    /// Example of a subpath processing response returning entity profiles by identifier in URL path, list of all entities and top-rated entity.
    private struct EntityResponseGroup : KvResponseGroup {

        var body: some KvResponseGroup {
            KvGroup(httpMethods: .get) {
                KvHttpResponse.with
                    /// At first subpaths are filtered accepting single component subpaths.
                    ///
                    /// This modifier accepts or rejects requests by subpath.
                    /// Subpaths are relative to point of the URL path hierarchy the response is declared at.
                    .subpathFilter { $0.components.count == 1 }
                    /// Then subpath is parsed as entity identifier and entity is fetched from the sample database.
                    /// In this way response is accepted only for existing entities.
                    ///
                    /// This modifier also filters requests as `.subpathFilter` and allows to transform current value of subpath.
                    .subpathFlatMap { .unwrapping(
                        Entity.ID($0.components.first!)
                            .flatMap { Self.sampleDB[$0] }
                    ) }
                    /// The resulting subpath processing result is in `input.subpath`.
                    .content { input in .json { input.subpath } }

                /// Entity list.
                ///
                /// Note that there is no ambiguity due to the subpath processing response requires non-empty subpath.
                KvHttpResponse {
                    .json { Self.sampleDB.values.lazy.map { $0 } }
                }

                /// Top-rated entity.
                ///
                /// Note that there is no ambiguity due to the subpath processing response requires first subpath component to be a number.
                KvGroup("top") {
                    KvHttpResponse {
                        .json { Self.sampleDB.values.max(by: { $0.rate < $1.rate }) }
                    }
                }
            }
        }

        private struct Entity : Codable {
            typealias ID = UInt

            let id: ID
            let label: String
            let rate: Double
        }

        private static let sampleDB: Dictionary<Entity.ID, Entity> = [
            Entity(id: 1, label: UUID().uuidString, rate: 4.57),
            Entity(id: 4, label: UUID().uuidString, rate: 1.32),
            Entity(id: 6, label: UUID().uuidString, rate: 3.14),
        ].reduce(into: .init()) { $0[$1.id] = $1 }

    }

}
