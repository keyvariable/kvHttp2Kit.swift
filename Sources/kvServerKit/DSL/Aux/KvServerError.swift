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
//  KvServerError.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 05.07.2023.
//

import Foundation



/// Server-level errors related to operation of ``KvServer`` based servers.
public enum KvServerError : LocalizedError {

    /// A server internal error. See ``InternalError`` for details.
    case `internal`(InternalError)



    // MARK: .InternalError

    public enum InternalError : LocalizedError {

        /// It's thrown when unable to access an HTTP channel expected to be available.
        case missingHttpChannel


        // MARK: : LocalizedError

        public var errorDescription: String? {
            switch self {
            case .missingHttpChannel:
                return "Declared HTTP channel is missing on server"
            }
        }

    }



    // MARK: : LocalizedError

    public var errorDescription: String? {
        switch self {
        case .internal(let error):
            return [ "Internal error", error.errorDescription ].compactMap({ $0 }).joined(separator: ". ")
        }
    }

}
