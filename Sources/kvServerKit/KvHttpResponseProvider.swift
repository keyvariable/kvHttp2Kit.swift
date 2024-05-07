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
//  KvHttpResponseProvider.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 11.04.2024.
//

import kvHttpKit
import kvKit



/// A callable type to be invoked with the result of request processing.
///
/// - Important: *KvHttpResponseProvider* is also a token.
///     If it's released before invocation then ``KvHttpChannel/RequestIncident/noResponse`` incident is triggered.
///
/// - Tip: If *KvHttpResponseProvider* is invoked with an error then ``KvHttpChannel/RequestIncident/requestProcessingError(_:)`` incident is triggered.
///
/// - Important: *KvHttpResponseProvider* is not thread-safe.
public class KvHttpResponseProvider {

    public typealias Callback = (Result<KvHttpResponseContent?, Error>) -> Void


    init(callback: @escaping Callback) {
        self.callback = callback
    }


    deinit {
        guard !isInvoked else { return }

        callback(.success(nil))
    }


    @usableFromInline
    let callback: Callback

    @usableFromInline
    private(set) var isInvoked = false


    // MARK: Operations

    @usableFromInline
    func invokeOnce(with response: Result<KvHttpResponseContent?, Error>) {
        guard !isInvoked
        else { return KvDebug.pause("\(Self.self) must be invoked once") }

        isInvoked = true

        callback(response)
    }


    @inlinable
    public func callAsFunction(_ response: Result<KvHttpResponseContent, Error>) {
        invokeOnce(with: response.map { $0 })
    }


    @inlinable
    public func callAsFunction(_ response: KvHttpResponseContent) {
        invokeOnce(with: .success(response))
    }


    @inlinable
    public func callAsFunction(_ error: Error) {
        invokeOnce(with: .failure(error))
    }


    /// Invokes the receiver with result of given block.
    ///
    /// - SeeAlso: There are various overloads of this method for async and/or throwing response blocks.
    func invoke(with response: () -> KvHttpResponseContent?) {
        invokeOnce(with: .success(response()))
    }


    /// Invokes the receiver with result of given throwing block.
    ///
    /// - SeeAlso: There are various overloads of this method for async and/or throwing response blocks.
    func invoke(with response: () throws -> KvHttpResponseContent?) {
        invokeOnce(with: .init(catching: response))
    }


    /// Invokes the receiver with result of given asynchronous block.
    ///
    /// - SeeAlso: There are various overloads of this method for async and/or throwing response blocks.
    func invoke(with response: @escaping () async -> KvHttpResponseContent?) {
        Task.detached {
            self.invokeOnce(with: .success(await response()))
        }
    }


    /// Invokes the receiver with result of given asynchronous throwing block.
    ///
    /// - SeeAlso: There are various overloads of this method for async and/or throwing response blocks.
    func invoke(with response: @escaping () async throws -> KvHttpResponseContent?) {
        Task.detached {
            let result: Result<KvHttpResponseContent?, Error>

            do { result = .success(try await response()) }
            catch { result = .failure(error) }

            self.invokeOnce(with: result)
        }
    }

}
