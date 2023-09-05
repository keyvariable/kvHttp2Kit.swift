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
//  KvHttpResponseImplementation.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 21.06.2023.
//

import Foundation



// MARK: - KvHttpResponseImplementationProtocol

protocol KvHttpResponseImplementationProtocol {

    var urlQueryParser: KvUrlQueryParserProtocol { get }

    func makeProcessor() -> KvHttpRequestProcessorProtocol?

}



// MARK: - KvHttpRequestProcessorProtocol

protocol KvHttpRequestProcessorProtocol : AnyObject {

    func process(_ requestHeaders: KvHttpServer.RequestHeaders) -> Result<Void, Error>

    func makeRequestHandler() -> Result<KvHttpRequestHandler, Error>

}



// MARK: - KvHttpResponseImplementation

struct KvHttpResponseImplementation<QueryParser, Headers, BodyValue> : KvHttpResponseImplementationProtocol
where QueryParser : KvUrlQueryParserProtocol & KvUrlQueryParseResultProvider {

    typealias HeadCallback = (KvHttpServer.RequestHeaders) -> Result<Headers, Error>
    typealias ResponseProvider = (QueryParser.Value, Headers, BodyValue) async throws -> KvHttpResponseProvider



    var urlQueryParser: KvUrlQueryParserProtocol { queryParser }



    init<Body>(urlQueryParser: QueryParser, headCallback: @escaping HeadCallback, body: Body, responseProvider: @escaping ResponseProvider)
    where Body : KvHttpRequestBody<BodyValue>
    {
        self.queryParser = urlQueryParser
        self.headCallback = headCallback
        self.body = body
        self.responseProvider = responseProvider
    }



    private let queryParser: QueryParser

    private let headCallback: HeadCallback
    private let body: KvHttpRequestBody<BodyValue>
    private let responseProvider: ResponseProvider



    // MARK: Operations

    func makeProcessor() -> KvHttpRequestProcessorProtocol? {
        switch queryParser.parseResult() {
        case .success(let queryValue):
            return Processor(queryValue, headCallback, body, responseProvider)
        case .failure:
            return nil
        }
    }



    // MARK: .Processor

    class Processor : KvHttpRequestProcessorProtocol {

        init<Body>(_ queryValue: QueryParser.Value, _ headCallback: @escaping HeadCallback, _ body: Body, _ responseProvider: @escaping ResponseProvider)
        where Body : KvHttpRequestBody<BodyValue>
        {
            self.queryValue = queryValue
            self.headCallback = headCallback
            self.body = body
            self.responseProvider = responseProvider
        }


        private let queryValue: QueryParser.Value
        private var headers: Headers?

        private let headCallback: HeadCallback
        private let body: KvHttpRequestBody<BodyValue>
        private let responseProvider: ResponseProvider


        // MARK: : KvHttpResponseImplementation

        func process(_ requestHeaders: KvHttpServer.RequestHeaders) -> Result<Void, Error> {
            switch headCallback(requestHeaders) {
            case .success(let value):
                headers = value
                return .success(())

            case .failure(let error):
                return .failure(error)
            }
        }


        func makeRequestHandler() -> Result<KvHttpRequestHandler, Error> {
            guard let headers = headers else { return .failure(ProcessError.noHeaders) }

            let queryValue = queryValue
            let responseProvider = responseProvider

            return .success(body.makeRequestHandler { bodyValue in
                try await responseProvider(queryValue, headers, bodyValue)
            })
        }


        // MARK: .ProcessError

        enum ProcessError : LocalizedError {
            case noHeaders
        }

    }

}



// MARK: Simple Response Case

extension KvHttpResponseImplementation where QueryParser == KvEmptyUrlQueryParser, Headers == Void, BodyValue == KvHttpRequestVoidBodyValue {

    /// Initializes implementation for emptry URL query, requiring head-only request, providing no analysis of request headers.
    init(responseProvider: @escaping () async throws -> KvHttpResponseProvider) {
        self.init(urlQueryParser: .init(),
                  headCallback: { _ in .success(()) },
                  body: KvHttpRequestProhibitedBody(),
                  responseProvider: { _, _, _ in try await responseProvider() })
    }

}
