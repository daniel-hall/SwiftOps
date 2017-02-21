//
//  SwiftOps.swift
//  SwiftOps
//
//  Created by Daniel Hall on 9/11/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import Foundation


// MARK: - SwiftOpsError -


/// An error type that represents errors from the SwiftOps framework itself
public enum SwiftOpsError: Error, CustomStringConvertible {
    case canceled  // Error returned to completion closures when an operation was canceled and so could not complete
    case timedOut  // Error returned to completion closures when an operation was canceled and so could not complete
    case missingOutput // Error returned when the function inside an Operation calls the completion closure with a nil error and a nil result
    
    public var description: String {
        switch self {
        case .canceled:
            return "SwiftOpsError: The operation was canceled before it could complete"
        case .timedOut:
            return "SwiftOpsError: The operation timed out before it could complete"
        case .missingOutput:
            return "SwiftOpsError: The function inside an operation called the completion closure with a nil result and a nil error."
        }
    }
}


// MARK: - OperationContext -

/// A protocol that provides information on a currently running Operation, and methods to cancel the Operation in-flight or set a timeout interval
public protocol OperationContext: class {
    var startDate: Date { get }
    func cancel()
    func timeout(at: Date)
}

/// A concrete implementation of the cancel token protocol
private class OperationExecutionContext: OperationContext {
    fileprivate(set) public var startDate = Date()
    fileprivate var canceled = false
    fileprivate var timedOut = false
    fileprivate var errorWasSent = false
    fileprivate var completionClosure: ((Any?)->())?
    fileprivate var errorClosure: ((Error)->())?
    
    public func timeout(at: Date) {
        let timeout = {
            [weak self] in
            self?.timedOut = true
            if self?.errorWasSent == false { self?.errorClosure?(SwiftOpsError.timedOut) }
            self?.cleanup()
        }
        if at <= Date() {
            timeout()
        } else {
            DispatchQueue.global().asyncAfter(deadline: .now() + at.timeIntervalSinceNow) {
                timeout()
            }
        }
    }
    
    public func cancel() {
        self.canceled = true
        if !errorWasSent { errorClosure?(SwiftOpsError.canceled) }
        self.cleanup()
    }
    
    fileprivate func cleanup() {
        completionClosure = nil
        errorClosure = nil
    }
    
    fileprivate func sendErrorIfTimedOutOrCanceled() -> Bool {
        if canceled {
            if !errorWasSent { errorClosure?(SwiftOpsError.canceled); errorWasSent = true }
            cleanup()
            return true
        } else if timedOut {
            if !errorWasSent { errorClosure?(SwiftOpsError.timedOut); errorWasSent = true }
            cleanup()
            return true
        }
        return false
    }
}


// MARK: - OperationErrorContext -

/// An type that is passed to Operation error handler closures which provides them with 1) the underlying error 2) the input that was provided to the Operation which ultimately ended in an error 3) retry methods that allow the handler to start the Operation again with either the original input, or a new initial input 4) a method that allows the handler to continue to the Operation failure and report it back to the completion handler with either the original error, or a different error.
public struct OperationErrorContext<T> {
    let failedInput:T
    let error: Error
    private let retryClosure:(T)->()
    private let continueClosure:(Error)->()
    
    fileprivate init(error: Error, failedInput:T, retryClosure:@escaping (T)->(), continueClosure: @escaping (Error)->()) {
        self.error = error
        self.failedInput = failedInput
        self.retryClosure = retryClosure
        self.continueClosure = continueClosure
    }
    
    func retry() {
        retryClosure(failedInput)
    }
    func retry(withInput:T) {
        retryClosure(withInput)
    }
    func `continue`() {
        continueClosure(error)
    }
    func `continue`(withError: Error) {
        continueClosure(withError)
    }
}


// MARK: - OperationProtocol Protocol -

/// A protocol that exists only to enable the below extensions
public protocol OperationProtocol {
    associatedtype InputType
    associatedtype OutputType
}

/// An extension to add a start method that doesn't require an input parameter if the Operation's input type is Void. So, for example, instead of having to type `operation.start(()) { // completion }`, the invocation can be simplifed to `operation.start{ // completion }`
public extension OperationProtocol where InputType == Void {
    
    /// Starts the operation
    ///
    /// - Parameter completion: a closure that will be called when the operation completes. The completion closure will be passed a single parameter —— a result closure that will either return the result when called, or throw the error that was encountered while running the operation
    /// - Returns: a cancel token that can either be discarded or used to cancel this operation after it has been started and before it completes.
    @discardableResult public func start(completion:@escaping (() throws -> OutputType)->()) -> OperationContext {
        let blueprint = (self as! Operation<InputType, OutputType>).blueprint
        var copy:Any = (blueprint.first!("") as! Bootstrappable).bootstrap()
        for index in 1..<blueprint.count {
            copy = blueprint[index](copy)
        }
        let complete = copy as! Operation<InputType, OutputType>
        complete.context.completionClosure = { if let closure = $0 as? (() throws -> OutputType){ completion(closure) } }
        complete.context.errorClosure = { error in completion{ throw error } }
        complete.context.startDate = Date()
        complete.startInternal(withInput: ())
        return complete.context
    }
}

/// An extension to add a start method that doesn't require a completion closure, in the event that the calling code doesn't care about any errors (fire and forget)
public extension OperationProtocol where OutputType == Void {
    
    /// Starts the operation
    ///
    /// - Parameter withInput: the initial input to start the operation with
    /// - Returns: a cancel token that can either be discarded or used to cancel this operation after it has been started and before it completes.
    @discardableResult public func start(withInput:InputType) -> OperationContext {
        let blueprint = (self as! Operation<InputType, OutputType>).blueprint
        var copy:Any = (blueprint.first!("") as! Bootstrappable).bootstrap()
        for index in 1..<blueprint.count {
            copy = blueprint[index](copy)
        }
        let complete = copy as! Operation<InputType, OutputType>
        complete.context.startDate = Date()
        complete.startInternal(withInput: withInput)
        return complete.context
    }
}

/// An extension to add a start method that doesn't require input or a completion closure in the event that the input type is Void anyway and the calling code doesn't care about any errors (fire and forget)
public extension OperationProtocol where InputType == Void, OutputType == Void {

    /// Starts the operation
    ///
    /// - Returns: a cancel token that can either be discarded or used to cancel this operation after it has been started and before it completes.
    @discardableResult public func start() -> OperationContext {
        let blueprint = (self as! Operation<InputType, OutputType>).blueprint
        var copy:Any = (blueprint.first!("") as! Bootstrappable).bootstrap()
        for index in 1..<blueprint.count {
            copy = blueprint[index](copy)
        }
        let complete = copy as! Operation<InputType, OutputType>
        complete.context.startDate = Date()
        complete.startInternal(withInput: ())
        return complete.context
    }
}

// MARK: - Operation -

/// An enum which describes how an operation should be dispatched / executed
fileprivate enum OperationType {
    /// An Operation that always runs on a background thread and calls back to the main thread when complete
    case async
    /// An Operation that always runs on the current thread and calls back to the main thread when complete
    case sync
    /// An Operation that always runs on the main thread and calls back to the main thread when complete
    case ui
}

/// A thin wrapper around a function of the type (Input) throws -> Output.  An Operation adds some useful functionality on top of the funtion it wraps, specifically:
/// - Verbs for composing the function/Operation with other functions/Operation ('or', 'then', 'and') without needing custom operators
/// - Declaration of how the function should run ('sync', 'async', 'ui') and automatic dispatch queue management as appropriate
/// - Automatic extrapolation of the nature of composed Operations.  For example, Operation.sync.then(Operation.sync) -> Operation.sync, but Operation.sync.then(Operation.async) -> Operation.async
/// - A visible type for debugging, e.g. 'Operation<Int -> String>' instead of 'Function'
public struct Operation<Input, Output> : OperationProtocol, CustomStringConvertible  {
    
    public typealias InputType = Input
    public typealias OutputType = Output
    
    fileprivate let blueprint: [(Any)->Any]
    fileprivate let context: OperationExecutionContext
    fileprivate var type: OperationType
    fileprivate var function: (Input, @escaping (Output?, Error?)->())->()
    
    /// Return an asynchronous Operation that always runs on a background thread and calls back to the main thread when complete
    ///
    /// - parameter function: an asynchronous function that has the signature (Input, @escaping (Output?, Error?)->())->(), meaning it accepts an input and a completion closure which in turn expects to be passed an optional result and an optional error
    ///
    /// - returns: an asynchronous Operation
    public static func async(function:@escaping (Input, @escaping (Output?, Error?)->())->()) -> Operation<Input, Output> {
        return Operation<Input, Output>(type: .async, context: OperationExecutionContext(), blueprint:[{ _ in return RootOperation(type:.async, function:function) }], function: function)
    }
    
    /// Return a synchronous Operation that runs on the current thread and calls back to the main thread when complete.  Will call back immediately in the same frame if started from the main thread
    ///
    /// - parameter function: a synchronous function that has the signature (Input) throws -> Output
    ///
    /// - returns: an synchronous Operation
    public static func sync(function:@escaping (Input) throws -> Output) -> Operation<Input, Output> {
        return Operation<Input, Output>(type: .sync, context: OperationExecutionContext(), blueprint:[{ _ in return RootOperation(type: .sync, function:convertToCallbackFunction(function)) }], function: convertToCallbackFunction(function))
    }
    
    /// Return a UI Operation that always runs on the main thread and calls back to the main thread when complete.  Will call back immediately in the same frame if started from the main thread.
    ///
    /// - parameter function: a synchronous function that has the signature (Input) throws -> Output and operates on UI elements or other APIs that only be used on the main thread
    ///
    /// - returns: a UI Operation
    public static func ui(function:@escaping (Input) throws -> Output) -> Operation<Input, Output> {
        return Operation<Input, Output>(type: .ui, context: OperationExecutionContext(), blueprint:[{ _ in return RootOperation(type:.ui, function:convertToCallbackFunction(function)) }], function: convertToCallbackFunction(function))
    }
    
    /// Initializes an Operation of the given type, using the token provided for cancelation.  Depending on the type specified for the provided function, it will be wrapped in a closure that dispatches it to the appropriate thread.
    fileprivate init(type:OperationType, context: OperationExecutionContext, blueprint:[(Any)->Any], function:@escaping (Input, @escaping (Output?, Error?)->())->()) {
        let wrappedFunction:(Input, @escaping (Output?, Error?)->())->()
        self.type = type
        self.context = context
        self.blueprint = blueprint
        
        switch type {
        case .async:
            wrappedFunction = {
                [weak context]
                input, completion in
                let closure = {
                    if context?.sendErrorIfTimedOutOrCanceled() == true { return }
                    function(input) {
                        result, error in
                        if context?.sendErrorIfTimedOutOrCanceled() == true { return }
                        if let result = result {
                            completion(result, nil)
                        } else {
                            completion(nil, error!)
                        }
                    }
                }
                if Thread.isMainThread {
                    DispatchQueue.global().async(execute: closure)
                } else {
                    closure()
                }
            }
        case .sync:
            wrappedFunction = {
                [weak context]
                input, completion in
                if context?.sendErrorIfTimedOutOrCanceled() == true { return }
                function(input) {
                    result, error in
                    if context?.sendErrorIfTimedOutOrCanceled() == true { return }
                    if let result = result {
                        completion(result, nil)
                    } else {
                        completion(nil, error!)
                    }
                }
            }
        case .ui:
            wrappedFunction = {
                [weak context]
                input, completion in
                let closure = {
                    if context?.sendErrorIfTimedOutOrCanceled() == true { return }
                    function(input) {
                        result, error in
                        if context?.sendErrorIfTimedOutOrCanceled() == true { return }
                        if let result = result {
                            completion(result, nil)
                        } else {
                            completion(nil, error!)
                        }
                    }
                }
                if Thread.isMainThread {
                    closure()
                } else {
                    DispatchQueue.main.async {
                        closure()
                    }
                }
            }
        }
        
        self.function = wrappedFunction
    }
    
    /// A description of this type at runtime for debugging
    public var description: String {
        switch self.type {
        case .async :
            return "Operation.async<" + "\(Input.self) -> " + "\(Output.self)>"
        case .sync :
            return "Operation.sync<" + "\(Input.self) -> " + "\(Output.self)>"
        case .ui :
            return "Operation.ui<" + "\(Input.self) -> " + "\(Output.self)>"
        }
    }
    
    /// Provides an input for this Operation, so that it can be started with that stored input at a later date, or grouped with other Operations to run in parallel (using the 'and' method).
    ///
    /// - Parameter input: The input that this Operation should use when it is started
    ///
    /// - Returns: A new Operation that requires no input (Void input) and returns the same type of output as the original operation.
    public func using(input:Input) -> Operation<Void, Output> {
        var blueprint = self.blueprint
        blueprint.append{ return ($0 as! Operation<Input, Output>).using(input: input) }
        let function: (Void, @escaping (Output?, Error?)->())->() = { _, completion in self.function(input, completion) }
        return Operation<Void, Output>(type:self.type, context: context, blueprint: blueprint, function: function)
    }
    
    
    /// Provides a handler closure for this operation, which will called only in the event of an error, before that error is returned to the completion handler. The error handler closure is passed an OperationErrorContext instance, which allows the handler to examine the error, the input which resulted in the error, and to either retry the operation with the same or a different input value, or continue with the failure using the original error or a new error which will be passed through to the completion closure. NOTE: It's important that the handler closure call one of the retry or continue methods on the OperationErrorContext, otherwise the completion closure for the overall Operation will never get called with either an error or success result.
    ///
    /// - Parameter handler: A closure that takes an OperationErrorContext and calls one of the retry methods on it or one of the continue methods
    /// - Returns: An asynchronous Operation with the same Input and Output types of this original operation, but which incorporates the provided error handler
    public func ifError(_ handler: @escaping (OperationErrorContext<Input>)->()) -> Operation<Input, Output> {
        var blueprint = self.blueprint
        blueprint.append{ return ($0 as! Operation<Input, Output>).ifError(handler) }
        func newFunction(input:Input, completion: @escaping (Output?, Error?)->()) {
            if context.sendErrorIfTimedOutOrCanceled() == true { return }
            self.function(input) {
                result, error in
                if self.context.sendErrorIfTimedOutOrCanceled() == true { return }
                if let result = result {
                    completion(result, nil)
                } else if let error = error {
                    let retryClosure:(Input)->() = { newFunction(input: $0, completion: completion) }
                    let continueClosure:(Error)->() = { completion(nil, $0) }
                    let errorContext = OperationErrorContext(error: error, failedInput:input, retryClosure:retryClosure, continueClosure: continueClosure)
                    handler(errorContext)
                }
                else {
                    completion(nil, SwiftOpsError.missingOutput)
                }
            }
        }

        return Operation<Input, Output>(type: .async, context: context, blueprint: blueprint, function: newFunction)
    }
    
    /// Starts the operation
    ///
    /// - Parameter withInput: the initial input to start the operation with
    ///
    /// - Parameter completion: a closure that will be called when the operation completes. The completion closure will be passed a single parameter —— a result closure that will either return the result when called, or throw the error that was encountered while running the operation
    ///
    /// - Returns: a cancel token that can either be discarded or used to cancel this operation after it has been started and before it completes.
    @discardableResult public func start(withInput:Input, completion:@escaping (@escaping () throws -> Output)->()) -> OperationContext {
        var copy:Any = (blueprint.first!("") as! Bootstrappable).bootstrap()
        for index in 1..<blueprint.count {
            copy = blueprint[index](copy)
        }
        let complete = copy as! Operation<Input, Output>
        complete.context.startDate = Date()
        complete.context.completionClosure = { if let closure = $0 as? (() throws -> Output) { completion(closure) } }
        complete.context.errorClosure = { error in completion{ throw error } }
        complete.startInternal(withInput: withInput)
        return complete.context
    }
    
    /// The actual internal mechanism of executing the current operation.  The public 'start' method performs a "copy-on-execute" and recreates the operation chain with a new, unique cancel token before calling this internal implementation to execute that new chain
    fileprivate func startInternal (withInput: Input) {
        function(withInput) {
            [weak context]
            result, error in
            if context?.sendErrorIfTimedOutOrCanceled() == true { return }
            let closure = {
                if let result = result {
                    let resultClosure:() throws -> Output = { return result }
                    context?.completionClosure?(resultClosure)
                    context?.cleanup()
                } else {
                    context?.errorClosure?(error ?? SwiftOpsError.missingOutput)
                    context?.errorWasSent = true
                }
            }
            if Thread.isMainThread {
                closure()
            } else {
                DispatchQueue.main.async {
                    closure()
                }
            }
        }
    }
    
    /// Composes current Operation with the supplied nextOperation and returns new Operation that takes the input of the first and returns the output of the second. For example, Operation<String, Int>.then(Operation<Int, Data>) will return an Operation<String, Data> that executes by first running the left-side Operation and then using the output from that to run the right-side Operation and return its output as the final result.
    ///
    /// - Parameter nextOperation: The Operation that should be composed with this Operation and run using the output from this one as input
    ///
    /// - Returns: A new Operation that takes the input of the first, uses the output of the first as input for the second, and finally returns the output from the second.
    public func then<NextOutput>(_ nextOperation:Operation<Output, NextOutput>) -> Operation<Input, NextOutput> {
        let closure:(Input, @escaping (NextOutput?, Error?)->())->() = {
            [weak context]
            input, completion in
            if context?.sendErrorIfTimedOutOrCanceled() == true { return }
            self.function(input) {
                result, error in
                if context?.sendErrorIfTimedOutOrCanceled() == true { return }
                if let result = result {
                    nextOperation.function(result) {
                        result, error in
                        if context?.sendErrorIfTimedOutOrCanceled() == true { return }
                        if let result = result {
                            completion(result, nil)
                        } else {
                            completion(nil, error!)
                        }
                    }
                } else {
                    completion(nil, error!)
                }
            }
        }
        
        var  blueprint = self.blueprint
        blueprint.append({ return ($0 as! Operation<Input, Output>).then(nextOperation) })
        
        switch (self.type, nextOperation.type) {
        case (.sync, .sync) :
            return Operation<Input, NextOutput>(type: .sync, context: context, blueprint: blueprint, function: closure)
        case (.sync, .async) :
            return Operation<Input, NextOutput>(type: .async, context: context, blueprint: blueprint, function: closure)
        case (.sync, .ui) :
            return Operation<Input, NextOutput>(type: .sync, context: context, blueprint: blueprint, function: closure)
        case (.async, .sync) :
            return Operation<Input, NextOutput>(type: .async, context: context, blueprint: blueprint, function: closure)
        case (.async, .async) :
            return Operation<Input, NextOutput>(type: .async, context: context, blueprint: blueprint, function: closure)
        case (.async, .ui) :
            return Operation<Input, NextOutput>(type: .async, context: context, blueprint: blueprint, function: closure)
        case (.ui, .sync) :
            return Operation<Input, NextOutput>(type: .sync, context: context, blueprint: blueprint, function: closure)
        case (.ui, .async) :
            return Operation<Input, NextOutput>(type: .async, context: context, blueprint: blueprint, function: closure)
        case (.ui, .ui) :
            return Operation<Input, NextOutput>(type: .sync, context: context, blueprint: blueprint, function: closure)
        }
    }
    
    
    /// Creates a new Operation of the same type as the current Operation and the alternateOperation parameter.  The new Operation will first try to execute the current Operation and if that succeeds, it will return that result.  However if it fails, instead of throwing an error, it will then try the alternateOperation, return that result if successful, or otherwise throw the specified error. Any number of Operations with the same Input and Output types can be combined as alternates using this method.
    ///
    /// - Parameter alternateOperation: An Operation that takes the same Input type and returns the same Output type which should run if the current Operation fails.
    ///
    /// - Returns: A new Operation with the same type (<Input, Output> as the current Operation and the alternateOperation parameter
    public func or(_ alternateOperation:Operation<Input, Output>) -> Operation<Input, Output> {
        let closure:(Input, @escaping (Output?, Error?)->())->() = {
            [weak context]
            input, completion in
            if context?.sendErrorIfTimedOutOrCanceled() == true { return }
            self.function(input) {
                result, error in
                if context?.sendErrorIfTimedOutOrCanceled() == true { return }
                if let result = result {
                    completion(result, nil)
                } else {
                    alternateOperation.function(input) {
                        result, error in
                        if let result = result {
                            completion(result, nil)
                        } else {
                            completion(nil, error!)
                        }
                    }
                }
            }
        }
        var  blueprint = self.blueprint
        blueprint.append({ return ($0 as! Operation<Input, Output>).or(alternateOperation) })
        
        switch (self.type, alternateOperation.type) {
        case (.sync, .sync) :
            return Operation<Input, Output>(type: .sync, context: context, blueprint: blueprint, function: closure)
        case (.sync, .async) :
            return Operation<Input, Output>(type: .async, context: context, blueprint: blueprint, function: closure)
        case (.sync, .ui) :
            return Operation<Input, Output>(type: .sync, context: context, blueprint: blueprint, function: closure)
        case (.async, .sync) :
            return Operation<Input, Output>(type: .async, context: context, blueprint: blueprint, function: closure)
        case (.async, .async) :
            return Operation<Input, Output>(type: .async, context: context, blueprint: blueprint, function: closure)
        case (.async, .ui) :
            return Operation<Input, Output>(type: .async, context: context, blueprint: blueprint, function: closure)
        case (.ui, .sync) :
            return Operation<Input, Output>(type: .sync, context: context, blueprint: blueprint, function: closure)
        case (.ui, .async) :
            return Operation<Input, Output>(type: .async, context: context, blueprint: blueprint, function: closure)
        case (.ui, .ui) :
            return Operation<Input, Output>(type: .sync, context: context, blueprint: blueprint, function: closure)
        }
    }
    
    
    /// Creates a new Operation that runs the first operation and the additional operation provided in the parameter asynchronously and in parallel.  When both operation are completed, a tuple containing both of their results will be passed to either the next operation in the chain, or the completion closure. Both operations are given the same input to execute, so an operation can only be combined using this method with another operation that hs the same input type (commonly just Void).
    ///
    /// - Parameter additionalOperation: another operation that should run in parallel with this operation
    ///
    /// - Returns: An new Operation that has the same input type as both source operations, and an output type of a tuple containing the first operation's result plus the second operation's result
    func and<OtherOutput>(_ additionalOperation:Operation<Input, OtherOutput>) -> Operation<Input, (Output, OtherOutput)> {
        let closure:(Input, @escaping ((Output, OtherOutput)?, Error?)->())->() = {
            [weak context]
            input, completion in
            if context?.sendErrorIfTimedOutOrCanceled() == true { return }
            let group = DispatchGroup()
            var resultOne:OutputType?
            var resultTwo:OtherOutput?
            var resultError:Error?
            var canceled = false
            var timedOut = false
            group.enter()
            DispatchQueue.global().async {
                self.function(input) {
                    result, error in
                    if canceled {
                        // no action required
                    } else if timedOut {
                        // no action required
                    } else if context?.canceled == true {
                        canceled = true
                        completion(nil, SwiftOpsError.canceled)
                    } else if context?.timedOut == true {
                        timedOut = true
                        completion(nil, SwiftOpsError.timedOut)
                    } else if let result = result {
                        resultOne = result
                    } else {
                        resultError = error
                    }
                    group.leave()
                }
            }
            group.enter()
            DispatchQueue.global().async {
                additionalOperation.function(input) {
                    result, error in
                    if canceled {
                        //no action required
                    } else if timedOut {
                        // no action required
                    } else if context?.canceled == true {
                        canceled = true
                        completion(nil, SwiftOpsError.canceled)
                    } else if context?.timedOut == true {
                        timedOut = true
                        completion(nil, SwiftOpsError.timedOut)
                    } else if let result = result {
                        resultTwo = result
                    } else {
                        if resultError == nil {
                            resultError = error
                        }
                    }
                    group.leave()
                }
            }
            group.wait()
            if canceled { return }
            if timedOut { return }
            if context?.canceled == true {
                completion(nil, SwiftOpsError.canceled)
                return
            }
            if context?.timedOut == true {
                completion(nil, SwiftOpsError.timedOut)
                return
            }
            if let error = resultError {
                completion(nil, error)
            } else if let resultOne = resultOne, let resultTwo = resultTwo {
                completion((resultOne, resultTwo), nil)
            } else {
                completion(nil, SwiftOpsError.missingOutput)
            }
        }
        var  blueprint = self.blueprint
        blueprint.append({ return ($0 as! Operation<Input, Output>).and(additionalOperation) })
        return Operation<Input, (Output, OtherOutput)>(type:.async, context: context, blueprint:blueprint, function:closure)
    }
}

// MARK: - Blueprinting -

// Blueprinting is used to store the steps needed to recreate a fresh instance of an operation (including all the operations that were chained together to create it) based on a new cancel token. This allows each run of the same operation to have a unique token to cancel it with that doesn't affect other executions of the same operation.

/// A non-generic protocol for recreating the root operation in a blueprint
fileprivate protocol Bootstrappable {
    func bootstrap() -> Any
}

/// A basic container for representing the intial operation in a blueprint array
fileprivate struct RootOperation<Input, Output>: Bootstrappable {
    let type: OperationType
    let function: (Input, @escaping (Output?, Error?)->())->()
    func bootstrap() -> Any {
        return Operation<Input, Output>.init(type: type, context: OperationExecutionContext(), blueprint: [{_ in return self}], function: function)
    }
}

// MARK: - Helper Functions -

/// Converts a function with the signature (Input) throws -> Output to a function with the signature (Input, (Output?, Error?)->())->(). Used internally for dealing with async functions
///
/// - parameter function: The function to convert
private func convertToCallbackFunction<FunctionInput, FunctionOutput>(_ function:@escaping (FunctionInput) throws -> FunctionOutput) -> (FunctionInput, @escaping (FunctionOutput?, Error?)->())->() {
    return {
        input, completion in
        do {
            completion(try function(input), nil)
        } catch {
            completion(nil, error)
        }
    }
}
