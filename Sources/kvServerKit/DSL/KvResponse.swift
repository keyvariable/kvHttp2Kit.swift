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
//  KvResponse.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 09.06.2023.
//

// MARK: - KvResponse

/// A type that represents a response on server.
///
/// This type can be used to create properties and custom types of responses.
///
/// Below is an example of a current server time HTTP response type having *format* parameter:
///
/// ```swift
/// struct CurrentDateResponse : KvResponse {
///     enum Format { case iso8601, rfc3339 }
///
///     init(format: Format) {
///         switch {
///         case .iso8601:
///             formatter = ISO8601DateFormatter()
///         case .rfc3339:
///             let rfc3339Formatter = DateFormatter()
///             rfc3339Formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
///             rfc3339Formatter.locale = Locale(identifier: "en_US_POSIX")
///             rfc3339Formatter.timeZone = TimeZone(secondsFromGMT: 0)
///             formatter = rfc3339Formatter
///         }
///     }
///
///     private let formatter: Formatter
///
///     var body: some KvResponse {
///         KvHttpResponse { .string { formatter.string(for: Date()! } }
///     }
/// }
/// ```
///
/// Then `CurrentDateResponse` can be used as any Swift type. For example:
///
/// ```swift
/// KvGroup("iso8601") {
///     CurrentDateResponse(format: .iso8601)
/// }
/// KvGroup("rfc3339") {
///     CurrentDateResponse(format: .rfc3339)
/// }
/// ```
///
/// See: ``KvHttpResponse``.
public protocol KvResponse {

    /// It's inferred from your implementation of the required property ``KvResponse/body-swift.property-7lcxm``.
    associatedtype Body : KvResponse


    /// Represents the behavior of response.
    var body: Body { get }

}



// MARK: Auxiliaries

extension KvResponse {

    public typealias QueryResult = KvUrlQueryParseResult

}



// MARK: - KvResponseInternalProtocol

protocol KvResponseInternalProtocol : KvResponse {

    func insert<A : KvHttpResponseAccumulator>(to accumulator: A)

}



// MARK: - KvNeverResponseProtocol

public protocol KvNeverResponseProtocol : KvResponse {

    init()

}


// This approach helps to prevent substitution of `KvNeverResponse` as `Body` in the Xcode's code completion for `body` properties
// when declaring structures conforming to `KvResponse`.
// If body constraint were `Body == KvNeverResponse` then the code completion would always produce `var body: KvNeverResponse`.
extension KvResponse where Body : KvNeverResponseProtocol {

    public var body: Body { Body() }

}



// MARK: - KvNeverResponse

/// Special type for implementations of ``KvResponse`` providing no body.
public struct KvNeverResponse : KvNeverResponseProtocol {

    public typealias Body = KvNeverResponse


    public init() { fatalError("KvNeverResponse must never be instantiated") }

}


extension KvResponse where Body == KvNeverResponse {

    public var body: KvNeverResponse { KvNeverResponse() }

}
