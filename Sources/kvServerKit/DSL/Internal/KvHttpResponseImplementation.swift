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



// MARK: KvHttpResponseContext

struct KvHttpResponseContext {

    typealias ClientCallbacks = KvResponseGroupConfiguration.ClientCallbacks


    var subpathComponents: ArraySlice<String>

    var clientCallbacks: ClientCallbacks?

}



// MARK: - KvHttpResponseImplementationProtocol

protocol KvHttpResponseImplementationProtocol {

    var urlQueryParser: KvUrlQueryParserProtocol { get }


    func makeProcessor(in responseContext: KvHttpResponseContext) -> KvHttpRequestProcessorProtocol?

}



// MARK: - KvHttpRequestProcessorProtocol

protocol KvHttpRequestProcessorProtocol : AnyObject {

    func process(_ requestHeaders: KvHttpServer.RequestHeaders) -> Result<Void, Error>

    func makeRequestHandler() -> Result<KvHttpRequestHandler, Error>

    func onIncident(_ incident: KvHttpIncident) -> KvHttpResponseProvider?

}



// MARK: - KvHttpSubpathResponseImplementation

/// Protocol for `KvHttpResponseImplementation` where `Subpath` is `KvUrlSubpath`.
protocol KvHttpSubpathResponseImplementation { }



// MARK: - KvHttpResponseImplementation

struct KvHttpResponseImplementation<QueryParser, Headers, BodyValue, Subpath> : KvHttpResponseImplementationProtocol
where QueryParser : KvUrlQueryParserProtocol & KvUrlQueryParseResultProvider,
      Subpath : KvUrlSubpathProtocol
{

    typealias HeadCallback = (KvHttpServer.RequestHeaders) -> Result<Headers, Error>
    typealias ClientCallbacks = KvResponseGroupConfiguration.ClientCallbacks

    typealias ResponseContext = KvHttpResponseContext

    typealias ResponseProvider = (QueryParser.Value, Headers, BodyValue, Subpath) throws -> KvHttpResponseProvider



    var urlQueryParser: KvUrlQueryParserProtocol { queryParser }



    init(urlQueryParser: QueryParser,
         headCallback: @escaping HeadCallback,
         body: any KvHttpRequestBodyInternal,
         clientCallbacks: ClientCallbacks?,
         responseProvider: @escaping ResponseProvider
    ) {
        self.queryParser = urlQueryParser
        self.headCallback = headCallback
        self.body = body
        self.clientCallbacks = clientCallbacks
        self.responseProvider = responseProvider
    }



    private let queryParser: QueryParser

    private let headCallback: HeadCallback
    private let body: any KvHttpRequestBodyInternal

    private let clientCallbacks: ClientCallbacks?

    private let responseProvider: ResponseProvider



    // MARK: Operations

    func makeProcessor(in responseContext: ResponseContext) -> KvHttpRequestProcessorProtocol? {
        switch queryParser.parseResult() {
        case .success(let queryValue):
            var responseContext = responseContext
            responseContext.clientCallbacks = .accumulate(clientCallbacks, into: responseContext.clientCallbacks)
            return Processor(queryValue, headCallback, body, responseContext, responseProvider)

        case .failure:
            return nil
        }
    }



    // MARK: .Processor

    class Processor : KvHttpRequestProcessorProtocol {

        init(_ queryValue: QueryParser.Value,
             _ headCallback: @escaping HeadCallback,
             _ body: any KvHttpRequestBodyInternal,
             _ responseContext: ResponseContext,
             _ responseProvider: @escaping ResponseProvider
        ) {
            self.queryValue = queryValue
            self.headCallback = headCallback
            self.body = body
            self.responseContext = responseContext
            self.responseProvider = responseProvider
        }


        private let queryValue: QueryParser.Value
        private var headers: Headers?

        private let headCallback: HeadCallback
        private let body: any KvHttpRequestBodyInternal

        private let responseContext: ResponseContext

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
            let responseContext = responseContext

            let responseProvider = responseProvider

            return .success(body.makeRequestHandler(responseContext.clientCallbacks) { bodyValue in
                try responseProvider(queryValue, headers, bodyValue as! BodyValue, Subpath(with: responseContext.subpathComponents))
            })
        }


        func onIncident(_ incident: KvHttpIncident) -> KvHttpResponseProvider? {
            responseContext.clientCallbacks?.onHttpIncident?(incident)
        }


        // MARK: .ProcessError

        enum ProcessError : LocalizedError {
            case noHeaders
        }

    }

}



extension KvHttpResponseImplementation : KvHttpSubpathResponseImplementation where Subpath == KvUrlSubpath {
    // MARK: : KvHttpSubpathResponseImplementation
}



extension KvHttpResponseImplementation
where QueryParser == KvEmptyUrlQueryParser, Headers == Void, BodyValue == KvHttpRequestVoidBodyValue, Subpath == KvUnavailableUrlSubpath
{
    // MARK: Simple Response Case

    /// Initializes implementation for emptry URL query, requiring head-only request, providing no analysis of request headers.
    init(clientCallbacks: ClientCallbacks?, responseProvider: @escaping () throws -> KvHttpResponseProvider) {
        self.init(urlQueryParser: .init(),
                  headCallback: { _ in .success(()) },
                  body: KvHttpRequestProhibitedBody(),
                  clientCallbacks: clientCallbacks,
                  responseProvider: { _, _, _, _ in try responseProvider() })
    }

}
