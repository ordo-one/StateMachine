//
//  Copyright (c) 2019, Match Group, LLC
//  BSD License, see LICENSE file for details
//

import Nimble
@testable import StateMachine
import XCTest

final class StateMachineTests: XCTestCase, StateMachineBuilder {

    enum State: StateMachineHashable {

        case stateOne, stateTwo, stateUndeclared
    }

    enum Event: StateMachineHashable {

        case eventOne, eventTwo
    }

    enum SideEffect {

        case commandOne, commandTwo, commandThree
    }

    typealias TestStateMachine = StateMachine<State, Event, SideEffect>
    typealias ValidTransition = TestStateMachine.Transition.Valid
    typealias InvalidTransition = TestStateMachine.Transition.Invalid

    static func testStateMachine(withInitialState _state: State) -> TestStateMachine {
        TestStateMachine {
            initialState(_state)
            state(.stateOne) {
                on(.eventOne) {
                    dontTransition(emit: .commandOne)
                }
                on(.eventTwo) {
                    transition(to: .stateTwo, emit: .commandTwo)
                }
            }
            state(.stateTwo) {
                on(.eventTwo) {
                    dontTransition(emit: .commandThree)
                }
            }
        }
    }

    func givenState(is state: State) -> TestStateMachine {
        let stateMachine: TestStateMachine = Self.testStateMachine(withInitialState: state)
        expect(stateMachine.state).to(equal(state))
        return stateMachine
    }

    func testDontTransition() throws {

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateOne)

        // When
        let transition: ValidTransition = try stateMachine.transition(.eventOne)

        // Then
        expect(stateMachine.state).to(equal(.stateOne))
        expect(transition).to(equal(ValidTransition(fromState: .stateOne,
                                                    event: .eventOne,
                                                    toState: .stateOne,
                                                    sideEffect: .commandOne)))
    }

    func testTransition() throws {

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateOne)

        // When
        let transition: ValidTransition = try stateMachine.transition(.eventTwo)

        // Then
        expect(stateMachine.state).to(equal(.stateTwo))
        expect(transition).to(equal(ValidTransition(fromState: .stateOne,
                                                    event: .eventTwo,
                                                    toState: .stateTwo,
                                                    sideEffect: .commandTwo)))
    }

    func testInvalidTransition() throws {

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateTwo)

        // When
        let transition: () throws -> ValidTransition = {
            try stateMachine.transition(.eventOne)
        }

        // Then
        expect(transition).to(throwError { error in
            expect(error).to(beAKindOf(InvalidTransition.self))
        })
    }

    static func absorbingStateMachine(
        initialState _state: State,
        onAbsorb: ((State, Event) -> Void)?
    ) -> TestStateMachine {
        TestStateMachine(unhandledEventPolicy: .absorb(onAbsorb)) {
            initialState(_state)
            state(.stateOne) {
                on(.eventOne) { dontTransition(emit: .commandOne) }
                on(.eventTwo) { transition(to: .stateTwo, emit: .commandTwo) }
            }
            state(.stateTwo) {
                on(.eventTwo) { dontTransition(emit: .commandThree) }
            }
        }
    }

    func testAbsorbWithNilCallback_succeedsSilently() throws {

        // Given — eventOne in stateTwo has no declared handler, no callback
        let stateMachine: TestStateMachine = Self.absorbingStateMachine(
            initialState: .stateTwo,
            onAbsorb: nil
        )

        // When
        let transition: ValidTransition = try stateMachine.transition(.eventOne)

        // Then — absorbed silently: state unchanged, no side effect
        expect(stateMachine.state).to(equal(.stateTwo))
        expect(transition).to(equal(ValidTransition(fromState: .stateTwo,
                                                    event: .eventOne,
                                                    toState: .stateTwo,
                                                    sideEffect: nil)))
    }

    func testMachineRemainsUsable_afterAbsorbedEventWithCallback() throws {

        // Given — an absorbed event whose callback has run (exercises the
        // isNotifying guard around the callback being released afterwards)
        let stateMachine: TestStateMachine = Self.absorbingStateMachine(
            initialState: .stateTwo,
            onAbsorb: { _, _ in }
        )
        _ = try stateMachine.transition(.eventOne) // absorbed

        // When — a declared transition follows
        let transition: ValidTransition = try stateMachine.transition(.eventTwo)

        // Then — the machine was not left stuck in the notifying guard
        expect(transition.sideEffect).to(equal(.commandThree))
    }

    func testAbsorbCallbackCapturingMachine_isReleasedOnceReferenceCleared() {

        // A callback that captures its own machine by reference forms a
        // cycle (machine → policy → closure → capture box → machine).
        // Verify the machine deallocates once the captured reference is
        // cleared — without the `machine = nil`, the weak reference
        // below stays non-nil and this test fails.
        weak var weakMachine: TestStateMachine?
        do {
            var machine: TestStateMachine!
            machine = Self.absorbingStateMachine(
                initialState: .stateTwo,
                onAbsorb: { _, _ in _ = machine.state }
            )
            weakMachine = machine
            expect(weakMachine).toNot(beNil())
            machine = nil // breaks the cycle
        }
        expect(weakMachine).to(beNil())
    }

    func testAbsorbPolicy_undeclaredStateStillThrowsInvalid() throws {

        // Given — the machine is in a state the definition never declared.
        // That is a misdeclared machine (typo'd or missing `state(...)`
        // block), not a late event for a known phase — absorb must NOT
        // swallow it.
        var absorbedEvents: [(state: State, event: Event)] = []
        let stateMachine: TestStateMachine = Self.absorbingStateMachine(
            initialState: .stateUndeclared,
            onAbsorb: { absorbedEvents.append(($0, $1)) }
        )

        // When
        let transition: () throws -> ValidTransition = {
            try stateMachine.transition(.eventOne)
        }

        // Then — Invalid is thrown despite the absorb policy
        expect(transition).to(throwError { error in
            expect(error).to(beAKindOf(InvalidTransition.self))
        })
        expect(absorbedEvents).to(beEmpty())
    }

    func testAbsorbedTransition_isDeliveredToObservers_afterAbsorbCallback() throws {

        // Given — an observer plus an absorb callback, with an order log
        var sequence: [String] = []
        let stateMachine: TestStateMachine = Self.absorbingStateMachine(
            initialState: .stateTwo,
            onAbsorb: { _, _ in sequence.append("absorbCallback") }
        )
        var observed: [Result<ValidTransition, InvalidTransition>] = []
        stateMachine.startObserving(self) {
            sequence.append("observer")
            observed.append($0.mapError { $0 as! InvalidTransition })
        }

        // When — eventOne is unhandled in (declared) stateTwo
        _ = try stateMachine.transition(.eventOne)

        // Then — the observer received the absorbed no-op as a success,
        // and the absorb callback ran before observers were notified
        expect(observed).to(equal([
            .success(ValidTransition(fromState: .stateTwo,
                                     event: .eventOne,
                                     toState: .stateTwo,
                                     sideEffect: nil))
        ]))
        expect(sequence).to(equal(["absorbCallback", "observer"]))
    }

    func testAbsorbCallback_reentrantTransitionThrowsRecursionDetected() throws {

        // Given — the absorb callback tries to dispatch a new event.
        // The closure must capture `stateMachine` by reference (it is
        // still nil when the closure is created), which forms a cycle:
        // machine → policy → closure → capture box → machine. Break it
        // at test end by clearing the variable. A `[weak stateMachine]`
        // capture list would NOT work here — it copies the current
        // (nil) value at closure-creation time.
        var stateMachine: TestStateMachine!
        defer { stateMachine = nil }
        var reentrantError: Error?
        stateMachine = Self.absorbingStateMachine(
            initialState: .stateTwo,
            onAbsorb: { _, _ in
                do {
                    try stateMachine.transition(.eventTwo)
                } catch {
                    reentrantError = error
                }
            }
        )

        // When — eventOne is unhandled in stateTwo, triggering the callback
        _ = try stateMachine.transition(.eventOne)

        // Then — the re-entrant dispatch threw instead of mutating state
        expect(reentrantError).to(matchError(TestStateMachine.StateMachineError.recursionDetected))
        expect(stateMachine.state).to(equal(.stateTwo))
    }

    func testAbsorbedUnhandledTransition_succeedsWithNoStateChangeAndNoSideEffect() throws {

        // Given — eventOne in stateTwo has no declared handler
        var absorbedEvents: [(state: State, event: Event)] = []
        let stateMachine: TestStateMachine = Self.absorbingStateMachine(
            initialState: .stateTwo,
            onAbsorb: { absorbedEvents.append(($0, $1)) }
        )

        // When
        let transition: ValidTransition = try stateMachine.transition(.eventOne)

        // Then — absorbed: state unchanged, no side effect, callback observed
        expect(stateMachine.state).to(equal(.stateTwo))
        expect(transition).to(equal(ValidTransition(fromState: .stateTwo,
                                                    event: .eventOne,
                                                    toState: .stateTwo,
                                                    sideEffect: nil)))
        expect(absorbedEvents.count).to(equal(1))
        expect(absorbedEvents.first?.state).to(equal(.stateTwo))
        expect(absorbedEvents.first?.event).to(equal(.eventOne))
    }

    func testAbsorbPolicy_doesNotAffectDeclaredTransitions() throws {

        // Given — eventTwo in stateOne is declared
        var absorbedEvents: [(state: State, event: Event)] = []
        let stateMachine: TestStateMachine = Self.absorbingStateMachine(
            initialState: .stateOne,
            onAbsorb: { absorbedEvents.append(($0, $1)) }
        )

        // When
        let transition: ValidTransition = try stateMachine.transition(.eventTwo)

        // Then — normal transition fires; absorb callback is not invoked
        expect(stateMachine.state).to(equal(.stateTwo))
        expect(transition).to(equal(ValidTransition(fromState: .stateOne,
                                                    event: .eventTwo,
                                                    toState: .stateTwo,
                                                    sideEffect: .commandTwo)))
        expect(absorbedEvents).to(beEmpty())
    }

    func testObservation() throws {

        var results: [Result<ValidTransition, InvalidTransition>] = []

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateOne)
            .startObserving(self) {
                results.append($0.mapError { $0 as! InvalidTransition })
            }

        // When
        try stateMachine.transition(.eventOne)
        try stateMachine.transition(.eventTwo)
        let transition: () throws -> ValidTransition = {
            try stateMachine.transition(.eventOne)
        }

        // Then
        expect(transition).to(throwError { error in
            expect(error).to(beAKindOf(InvalidTransition.self))
        })

        // When
        try stateMachine.transition(.eventTwo)

        // Then
        expect(results).to(equal([
            .success(ValidTransition(fromState: .stateOne,
                                     event: .eventOne,
                                     toState: .stateOne,
                                     sideEffect: .commandOne)),
            .success(ValidTransition(fromState: .stateOne,
                                     event: .eventTwo,
                                     toState: .stateTwo,
                                     sideEffect: .commandTwo)),
            .failure(InvalidTransition()),
            .success(ValidTransition(fromState: .stateTwo,
                                     event: .eventTwo,
                                     toState: .stateTwo,
                                     sideEffect: .commandThree))
        ]))
    }

    func testStopObservation() throws {

        var transitionCount: Int = 0

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateOne)
            .startObserving(self) { _ in
                transitionCount += 1
            }

        // When
        try stateMachine.transition(.eventOne)
        try stateMachine.transition(.eventOne)

        // Then
        expect(transitionCount).to(equal(2))

        // When
        stateMachine.stopObserving(self)
        try stateMachine.transition(.eventOne)
        try stateMachine.transition(.eventOne)

        // Then
        expect(transitionCount).to(equal(2))
    }

    func testRecursionDetectedError() throws {

        var error: TestStateMachine.StateMachineError? = nil

        // Given
        let stateMachine: TestStateMachine = givenState(is: .stateOne)

        stateMachine.startObserving(self) { [unowned stateMachine] _ in
            do {
                try stateMachine.transition(.eventOne)
            } catch let e as TestStateMachine.StateMachineError {
                error = e
            } catch {}
        }

        // When
        try stateMachine.transition(.eventOne)

        // Then
        expect(error).to(equal(.recursionDetected))
    }
}

final class Logger {

    private(set) var messages: [String] = []

    func log(_ message: String) {
        messages.append(message)
    }
}

func log(_ expectedMessages: String...) -> Matcher<Logger> {
    let expectedString: String = stringify(expectedMessages.joined(separator: "\\n"))
    return Matcher {
        let actualMessages: [String]? = try $0.evaluate()?.messages
        let actualString: String = stringify(actualMessages?.joined(separator: "\\n"))
        let message: ExpectationMessage = .expectedCustomValueTo("log <\(expectedString)>",
                                                                 actual: "<\(actualString)>")
        return MatcherResult(bool: actualMessages == expectedMessages, message: message)
    }
}
