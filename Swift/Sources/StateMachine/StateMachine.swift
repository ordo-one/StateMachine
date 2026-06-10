//
//  Copyright (c) 2018, Match Group, LLC
//  BSD License, see LICENSE file for details
//

open class StateMachine<State: StateMachineHashable, Event: StateMachineHashable, SideEffect> {

    public enum Transition {

        public typealias Result = Swift.Result<Valid, Error>
        public typealias Callback = (_ result: Result) -> Void

        public struct Valid: CustomDebugStringConvertible {

            public var debugDescription: String {
                guard let sideEffect: SideEffect = sideEffect
                else { return "fromState: \(fromState), event: \(event), toState: \(toState), sideEffect: nil" }
                return "fromState: \(fromState), event: \(event), toState: \(toState), sideEffect: \(sideEffect)"
            }

            public let fromState: State
            public let event: Event
            public let toState: State
            public let sideEffect: SideEffect?
        }

        public struct Invalid: Error, Equatable {}
    }

    /// Policy for events received in a state that does not declare a handler
    /// for them. By default the machine treats unhandled (state, event) pairs
    /// as programming errors and throws `Transition.Invalid`, which matches
    /// the original library semantics and is correct for tightly-controlled
    /// flows (UI, auth, video player state, etc.) where reaching an
    /// undeclared transition means a bug.
    ///
    /// For consumers fed by asynchronous external event streams — for
    /// example a server-side actor consuming order/cache updates that
    /// genuinely can arrive after the state machine has transitioned past
    /// the relevant phase — the `.absorb` case opts in to "unhandled event
    /// is a no-op, not a fatal error". The transition completes as a
    /// no-state-change with no side effect, the result is a success rather
    /// than a failure, and the optional callback is invoked so the consumer
    /// can log or otherwise observe the absorbed event.
    public enum UnhandledEventPolicy {

        /// Default. Unhandled (state, event) pairs throw `Transition.Invalid`.
        case invalid

        /// Unhandled (state, event) pairs are absorbed as a successful
        /// no-op transition. The optional callback is invoked synchronously
        /// before the result is observed; pass `nil` to absorb silently.
        ///
        /// Absorption only applies to events missing from a *declared*
        /// state. An event received in a state the definition never
        /// declared at all still throws `Transition.Invalid` under either
        /// policy — that is a misdeclared machine, not a late event.
        ///
        /// Observers see the absorbed transition as a regular success with
        /// `fromState == toState` and a `nil` side effect — indistinguishable
        /// from a declared `dontTransition()`. Use this callback when the
        /// distinction matters. Dispatching a new event from within the
        /// callback throws `StateMachineError.recursionDetected`, same as
        /// from an observer callback.
        case absorb(((_ state: State, _ event: Event) -> Void)?)
    }

    public enum StateMachineError: Error {

        case recursionDetected
    }

    private struct Observer {

        weak var object: AnyObject?

        let callback: Transition.Callback
    }

    public typealias Definition = StateMachineTypes.Definition<State, Event, SideEffect>

    private typealias DefinitionBuilder = StateMachineTypes.DefinitionBuilder
    private typealias InitialState = StateMachineTypes.InitialState<State>
    private typealias Component = StateMachineTypes.Component<State, Event, SideEffect>

    private typealias States = [State.HashableIdentifier: Events]
    private typealias Events = [Event.HashableIdentifier: Action.Factory]

    private typealias EventHandler = StateMachineTypes.EventHandler<State, Event, SideEffect>
    private typealias Action = StateMachineTypes.Action<State, Event, SideEffect>

    public private(set) var state: State

    private let states: States
    private let unhandledEventPolicy: UnhandledEventPolicy
    private var observers: [Observer] = []

    private var isNotifying: Bool = false

    public init(
        unhandledEventPolicy: UnhandledEventPolicy = .invalid,
        @DefinitionBuilder build: () -> Definition
    ) {
        let definition: Definition = build()
        state = definition.initialState.state
        states = definition.states.reduce(into: States()) {
            $0[$1.state] = $1.events.reduce(into: Events()) {
                $0[$1.event] = $1.action
            }
        }
        self.unhandledEventPolicy = unhandledEventPolicy
        observers = definition.callbacks.map {
            Observer(object: self, callback: $0)
        }
    }

    @discardableResult
    public func startObserving(_ observer: AnyObject?, callback: @escaping Transition.Callback) -> Self {
        guard let observer: AnyObject = observer
        else { return self }
        observers.append(Observer(object: observer, callback: callback))
        return self
    }

    public func stopObserving(_ observers: AnyObject?...) {
        stopObserving(observers)
    }

    public func stopObserving(_ observers: [AnyObject?]) {
        self.observers.removeAll {
            guard let object: AnyObject = $0.object
            else { return true }
            return observers.contains { $0 === object }
        }
    }

    @discardableResult
    public func transition(_ event: Event) throws -> Transition.Valid {
        guard !isNotifying
        else { throw StateMachineError.recursionDetected }
        let result: Transition.Result
        defer { notify(result) }
        do {
            let stateIdentifier: State.HashableIdentifier = state.hashableIdentifier
            let eventIdentifier: Event.HashableIdentifier = event.hashableIdentifier
            let declaredEvents: Events? = states[stateIdentifier]
            let factory: Action.Factory? = declaredEvents?[eventIdentifier]
            if let action: Action = try factory?(state, event) {
                let transition: Transition.Valid = .init(fromState: state,
                                                         event: event,
                                                         toState: action.toState ?? state,
                                                         sideEffect: action.sideEffect)
                if let toState: State = action.toState {
                    state = toState
                }
                result = .success(transition)
            } else if declaredEvents == nil {
                // The *state* itself was never declared in the definition.
                // That is a programming error (typo'd or missing `state(...)`
                // block), not a late event for a known phase — always throw,
                // regardless of policy. Absorbing here would turn a
                // misdeclared machine into one that reports success while
                // permanently ignoring everything.
                result = .failure(Transition.Invalid())
            } else {
                switch unhandledEventPolicy {
                case .invalid:
                    result = .failure(Transition.Invalid())
                case .absorb(let callback):
                    if let callback {
                        // Same re-entrancy protection observer callbacks get:
                        // dispatching a new event from inside the callback
                        // throws recursionDetected instead of mutating state
                        // mid-transition.
                        isNotifying = true
                        defer { isNotifying = false }
                        callback(state, event)
                    }
                    let transition: Transition.Valid = .init(fromState: state,
                                                             event: event,
                                                             toState: state,
                                                             sideEffect: nil)
                    result = .success(transition)
                }
            }
        } catch {
            result = .failure(error)
        }
        return try result.get()
    }

    private func notify(_ result: Transition.Result) {
        isNotifying = true
        defer { isNotifying = false }
        var observers: [Observer] = []
        for observer in self.observers {
            guard observer.object != nil
            else { continue }
            observers.append(observer)
            observer.callback(result)
        }
        self.observers = observers
    }
}

extension StateMachine.Transition.Valid: Equatable where State: Equatable,
                                                         Event: Equatable,
                                                         SideEffect: Equatable {}

public protocol StateMachineBuilder {

    associatedtype State: StateMachineHashable
    associatedtype Event: StateMachineHashable

    associatedtype SideEffect

    typealias InitialState = StateMachineTypes.InitialState<State>
    typealias Component = StateMachineTypes.Component<State, Event, SideEffect>

    typealias EventHandlerArrayBuilder = StateMachineTypes.EventHandlerArrayBuilder

    typealias EventHandler = StateMachineTypes.EventHandler<State, Event, SideEffect>
    typealias Action = StateMachineTypes.Action<State, Event, SideEffect>
}

extension StateMachineBuilder {

    public static func initialState(
        _ state: State
    ) -> InitialState {
        InitialState(state: state)
    }

    public static func state(
        _ state: State.HashableIdentifier
    ) -> Component {
        .state(state: state, events: [])
    }

    public static func state(
        _ state: State.HashableIdentifier,
        @EventHandlerArrayBuilder build: () -> [EventHandler]
    ) -> Component {
        .state(state: state, events: build())
    }

    public static func on(
        _ event: Event.HashableIdentifier,
        perform: @escaping (State, Event) throws -> Action
    ) -> [EventHandler] {
        [EventHandler(event: event, action: perform)]
    }

    public static func on(
        _ event: Event.HashableIdentifier,
        perform: @escaping (State) throws -> Action
    ) -> [EventHandler] {
        [EventHandler(event: event) { state, _ in try perform(state) }]
    }

    public static func on(
        _ event: Event.HashableIdentifier,
        perform: @escaping () throws -> Action
    ) -> [EventHandler] {
        [EventHandler(event: event) { _, _ in try perform() }]
    }

    public static func transition(
        to state: State,
        emit sideEffect: SideEffect? = nil
    ) -> Action {
        Action(toState: state, sideEffect: sideEffect)
    }

    public static func dontTransition(
        emit sideEffect: SideEffect? = nil
    ) -> Action {
        Action(toState: nil, sideEffect: sideEffect)
    }

    public static func onTransition(
        _ callback: @escaping StateMachine<State, Event, SideEffect>.Transition.Callback
    ) -> Component {
        .callback(callback: callback)
    }
}

public enum StateMachineTypes {

    public struct Definition<State: StateMachineHashable, Event: StateMachineHashable, SideEffect> {

        fileprivate let initialState: InitialState<State>
        fileprivate let components: [Component<State, Event, SideEffect>]

        fileprivate typealias States = [
            (state: State.HashableIdentifier, events: [EventHandler<State, Event, SideEffect>])
        ]

        fileprivate typealias Callbacks = [StateMachine<State, Event, SideEffect>.Transition.Callback]

        fileprivate var states: States {
            components.compactMap {
                guard case let .state(state, events) = $0
                else { return nil }
                return (state: state, events: events)
            }
        }

        fileprivate var callbacks: Callbacks {
            components.compactMap {
                guard case let .callback(callback) = $0
                else { return nil }
                return callback
            }
        }
    }

    @resultBuilder
    public struct DefinitionBuilder {

        public static func buildBlock<State, Event, SideEffect>(
            _ initialState: InitialState<State>,
            _ components: Component<State, Event, SideEffect>...
        ) -> Definition<State, Event, SideEffect> {
            Definition(initialState: initialState, components: components)
        }
    }

    public struct InitialState<State> {

        fileprivate let state: State
    }

    public enum Component<State: StateMachineHashable, Event: StateMachineHashable, SideEffect> {

        case state(state: State.HashableIdentifier, events: [EventHandler<State, Event, SideEffect>])
        case callback(callback: StateMachine<State, Event, SideEffect>.Transition.Callback)
    }

    @resultBuilder
    public struct EventHandlerArrayBuilder {

        public static func buildBlock<State, Event, SideEffect>(
            _ events: [EventHandler<State, Event, SideEffect>]...
        ) -> [EventHandler<State, Event, SideEffect>] {
            Array(events.joined())
        }
    }

    public struct EventHandler<State: StateMachineHashable, Event: StateMachineHashable, SideEffect> {

        fileprivate let event: Event.HashableIdentifier
        fileprivate let action: Action<State, Event, SideEffect>.Factory
    }

    public struct Action<State: StateMachineHashable, Event: StateMachineHashable, SideEffect> {

        fileprivate typealias Factory = (State, Event) throws -> Self

        fileprivate let toState: State?
        fileprivate let sideEffect: SideEffect?
    }

    public struct IncorrectTypeError: Error, CustomDebugStringConvertible {

        public var debugDescription: String {
            "Incorrect Type: expected `\(expectedType)`, encountered `\(encounteredType)`"
        }

        public let expectedType: Any.Type
        public let encounteredType: Any.Type
    }
}

@dynamicMemberLookup
public protocol StateMachineHashable {

    associatedtype HashableIdentifier: Hashable

    typealias IncorrectTypeError = StateMachineTypes.IncorrectTypeError

    var hashableIdentifier: HashableIdentifier { get }
    var associatedValue: Any { get }
}

extension StateMachineHashable where Self: Hashable {

    public var hashableIdentifier: Self { self }
}

extension StateMachineHashable {

    public var associatedValue: Any { () }

    // TODO: [CF] Return T (instead of closure) once Swift supports throwing subscript
    public subscript<T>(dynamicMember member: String) -> () throws -> T {
        { [associatedValue] in
            guard let value: T = associatedValue as? T
            else { throw IncorrectTypeError(expectedType: T.self, encounteredType: type(of: associatedValue)) }
            return value
        }
    }
}

public protocol AutoStateMachineHashable {}
