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
//  KvResponseAccumulator.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 28.06.2023.
//

// MARK: - KvResponseAccumulator

protocol KvResponseAccumulator : AnyObject {

    associatedtype NestedAccumulator : KvResponseAccumulator


    /// Resolved configuration of current response group.
    var responseGroupConfiguration: KvResponseGroupConfiguration? { get }


    func with(_ configuration: KvResponseGroupConfiguration, body: (NestedAccumulator) -> Void)

}



// MARK: - KvHttpResponseAccumulator

protocol KvHttpResponseAccumulator : KvResponseAccumulator
where NestedAccumulator: KvHttpResponseAccumulator
{

    func insert<HttpResponse>(_ response: HttpResponse) where HttpResponse : KvHttpResponseImplementationProtocol

}
