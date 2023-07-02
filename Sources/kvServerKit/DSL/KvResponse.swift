//===----------------------------------------------------------------------===//
//
//  Copyright (c) 2023 Svyatoslav Popov.
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
/// This type can be used to create properties and custom types of serponses.
///
/// Below is an example of a current server time HTTP response type having format parameter:
///
///     struct CurrentDateResponse<F> : KvResponse
///     where F : FormatStyle, F.FormatInput == Date
///     {
///         let format: F
///
///         var body: some KvResponse {
///             KvHttpResponse.static { .string(Date().formatted(format) }
///         }
///     }
///
/// Then `CurrentDateResponse` can be used as any Swift type. For example:
///
///     KvGroup("iso8601") {
///         CurrentDateResponse(format: .iso8601)
///     }
///     KvGroup("date") {
///         CurrentDateResponse(format: .dateTime.year().month().day())
///     }
///
/// See ``KvHttpResponse``.
public protocol KvResponse {

    /// It's inferred from your implementation of the required property ``KvResponse/body-swift.property-9pflg``.
    associatedtype Body : KvResponse


    /// Represens the behaviour of response.
    var body: Self.Body { get }

}



// MARK: Auxiliaries

extension KvResponse {

    public typealias QueryResult = KvUrlQueryParseResult

}



// MARK: Accumulation

extension KvResponse {

    internal func insert<A : KvResponseAccumulator>(to accumulator: A) {
        switch self {
        case let response as any KvResponseInternalProtocol:
            response.insert(to: accumulator)
        default:
            body.insert(to: accumulator)
        }
    }

}



// MARK: - KvResponseInternalProtocol

protocol KvResponseInternalProtocol : KvResponse {

    func insert<A : KvResponseAccumulator>(to accumulator: A)

}



// MARK: - KvNeverResponseProtocol

public protocol KvNeverResponseProtocol : KvResponse {

    init()

}


// This approach helps to prevent substituion of `KvNeverResponse` as `Body` in the Xcode's code completion for `body` properties
// when declaring structures conforming to `KvResponse`.
// If body constaint were `Body == KvNeverResponse` then the code completion would always produce `var body: KvNeverResponse`.
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
