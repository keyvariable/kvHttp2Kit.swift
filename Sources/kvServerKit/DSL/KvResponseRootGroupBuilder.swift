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
//  KvResponseRootGroupBuilder.swift
//  kvServerKit
//
//  Created by Svyatoslav Popov on 22.10.2023.
//

import Foundation



@resultBuilder
public struct KvResponseRootGroupBuilder {

    public typealias Group = KvResponseRootGroup



    /// Root response group expression builder.
    @inlinable
    public static func buildExpression<Component>(_ expression: Component) -> Component
    where Component : Group
    { expression }


    /// Response group expression builder.
    @inlinable
    public static func buildExpression<G>(_ responseGroup: G) -> WrapperGroup<G>
    where G : KvResponseGroup
    { WrapperGroup(responseGroup) }


    /// Response expression builder.
    @inlinable
    public static func buildExpression<R>(_ response: R) -> some Group
    where R : KvResponse
    { buildExpression(KvResponseGroupBuilder.buildExpression(response)) }


    /// URL expression builder.
    @inlinable
    public static func buildExpression(_ url: URL) -> some Group { buildExpression(KvResponseGroupBuilder.buildExpression(url)) }


    /// Optional URL expression builder.
    @inlinable
    public static func buildExpression(_ url: URL?) -> some Group { buildExpression(KvResponseGroupBuilder.buildExpression(url)) }


    /// MultiURL expression builder.
    @inlinable
    public static func buildExpression<URLs>(_ urls: URLs) -> some Group
    where URLs : Sequence, URLs.Element == URL
    { buildExpression(KvResponseGroupBuilder.buildExpression(urls)) }


    /// Optional MultiURL expression builder.
    @inlinable
    public static func buildExpression<URLs>(_ urls: URLs?) -> some Group
    where URLs : Sequence, URLs.Element == URL
    { buildExpression(KvResponseGroupBuilder.buildExpression(urls)) }


    @inlinable
    public static func buildBlock() -> KvEmptyResponseRootGroup { KvEmptyResponseRootGroup() }


    @inlinable
    public static func buildBlock<Component>(_ component: Component) -> Component
    where Component : Group
    { component }


    @inlinable
    public static func buildOptional<Component>(_ component: Component?) -> ConditionalGroup<Component, KvEmptyResponseRootGroup>
    where Component : Group
    {
        component.map { .init(trueGroup: $0) } ?? .init(falseGroup: .init())
    }


    @inlinable
    public static func buildEither<TrueComponent, FalseComponent>(first component: TrueComponent) -> ConditionalGroup<TrueComponent, FalseComponent>
    where TrueComponent : Group, FalseComponent : Group
    { .init(trueGroup: component) }


    @inlinable
    public static func buildEither<TrueComponent, FalseComponent>(second component: FalseComponent) -> ConditionalGroup<TrueComponent, FalseComponent>
    where TrueComponent : Group, FalseComponent : Group
    { .init(falseGroup: component) }


    @inlinable
    public static func buildPartialBlock<Component>(first: Component) -> Component
    where Component : Group
    { first }


    @inlinable
    public static func buildPartialBlock<C0, C1>(accumulated: C0, next: C1) -> GroupOfTwo<C0, C1>
    where C0 : Group, C1 : Group
    { GroupOfTwo(accumulated, next) }

    @inlinable
    public static func buildPartialBlock<C0, C1, C2>(accumulated: GroupOfTwo<C0, C1>, next: C2) -> GroupOfThree<C0, C1, C2>
    where C0 : Group, C1 : Group, C2 : Group
    { GroupOfThree(accumulated, next) }

    @inlinable
    public static func buildPartialBlock<C0, C1, C2, C3>(accumulated: GroupOfThree<C0, C1, C2>, next: C3) -> GroupOfFour<C0, C1, C2, C3>
    where C0 : Group, C1 : Group, C2 : Group, C3 : Group
    { GroupOfFour(accumulated, next) }

    @inlinable
    public static func buildPartialBlock<C0, C1, C2, C3, C4>(accumulated: GroupOfFour<C0, C1, C2, C3>, next: C4) -> GroupOfTwo<GroupOfFour<C0, C1, C2, C3>, C4>
    where C0 : Group, C1 : Group, C2 : Group, C3 : Group, C4 : Group
    { GroupOfTwo(accumulated, next) }



    // MARK: - WrapperGroup

    public struct WrapperGroup<E : KvResponseGroup> : Group, KvResponseRootGroupInternalProtocol {

        let wrapped: E


        @usableFromInline
        init(_ wrapped: E) { self.wrapped = wrapped }


        // MARK: : Group

        public var body: KvNeverResponseRootGroup { KvNeverResponseRootGroup() }


        // MARK: : KvResponseRootGroupInternalProtocol

        func insertResponses<A : KvHttpResponseAccumulator>(to accumulator: A) {
            wrapped.resolvedGroup.insertResponses(to: accumulator)
        }

    }



    // MARK: - ConditionalGroup

    public struct ConditionalGroup<TrueGroup, FalseGroup> : Group, KvResponseRootGroupInternalProtocol
    where TrueGroup : Group, FalseGroup : Group
    {

        let content: Content


        @usableFromInline
        init(trueGroup: TrueGroup) {
            content = .trueGroup(trueGroup)
        }


        @usableFromInline
        init(falseGroup: FalseGroup) {
            content = .falseGroup(falseGroup)
        }


        // MARK: .Content

        enum Content {
            case trueGroup(TrueGroup)
            case falseGroup(FalseGroup)
        }


        // MARK: : Group

        public var body: KvNeverResponseRootGroup { KvNeverResponseRootGroup() }


        // MARK: : KvResponseRootGroupInternalProtocol

        func insertResponses<A : KvHttpResponseAccumulator>(to accumulator: A) {
            switch content {
            case .falseGroup(let value):
                value.resolvedGroup.insertResponses(to: accumulator)
            case .trueGroup(let value):
                value.resolvedGroup.insertResponses(to: accumulator)
            }
        }
    }



    // MARK: - GroupOfTwo

    public struct GroupOfTwo<E0, E1> : Group, KvResponseRootGroupInternalProtocol
    where E0 : Group, E1 : Group
    {

        let e0: E0
        let e1: E1


        @usableFromInline
        init(_ e0: E0, _ e1: E1) {
            self.e0 = e0
            self.e1 = e1
        }


        // MARK: : Group

        public var body: KvNeverResponseRootGroup { KvNeverResponseRootGroup() }


        // MARK: : KvResponseRootGroupInternalProtocol

        func insertResponses<A : KvHttpResponseAccumulator>(to accumulator: A) {
            e0.resolvedGroup.insertResponses(to: accumulator)
            e1.resolvedGroup.insertResponses(to: accumulator)
        }

    }



    // MARK: - GroupOfThree

    public struct GroupOfThree<E0, E1, E2> : Group, KvResponseRootGroupInternalProtocol
    where E0 : Group, E1 : Group, E2 : Group
    {

        let e0: E0
        let e1: E1
        let e2: E2


        @usableFromInline
        init(_ g: GroupOfTwo<E0, E1>, _ e2: E2) {
            self.e0 = g.e0
            self.e1 = g.e1
            self.e2 = e2
        }


        // MARK: : Group

        public var body: KvNeverResponseRootGroup { KvNeverResponseRootGroup() }


        // MARK: : KvResponseRootGroupInternalProtocol

        func insertResponses<A : KvHttpResponseAccumulator>(to accumulator: A) {
            e0.resolvedGroup.insertResponses(to: accumulator)
            e1.resolvedGroup.insertResponses(to: accumulator)
            e2.resolvedGroup.insertResponses(to: accumulator)
        }

    }



    // MARK: - GroupOfFour

    public struct GroupOfFour<E0, E1, E2, E3> : Group, KvResponseRootGroupInternalProtocol
    where E0 : Group, E1 : Group, E2 : Group, E3 : Group
    {

        let e0: E0
        let e1: E1
        let e2: E2
        let e3: E3


        @usableFromInline
        init(_ g: GroupOfThree<E0, E1, E2>, _ e3: E3) {
            self.e0 = g.e0
            self.e1 = g.e1
            self.e2 = g.e2
            self.e3 = e3
        }


        // MARK: : Group

        public var body: KvNeverResponseRootGroup { KvNeverResponseRootGroup() }


        // MARK: : KvResponseRootGroupInternalProtocol

        func insertResponses<A : KvHttpResponseAccumulator>(to accumulator: A) {
            e0.resolvedGroup.insertResponses(to: accumulator)
            e1.resolvedGroup.insertResponses(to: accumulator)
            e2.resolvedGroup.insertResponses(to: accumulator)
            e3.resolvedGroup.insertResponses(to: accumulator)
        }

    }

}
