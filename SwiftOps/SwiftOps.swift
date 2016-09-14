//
//  SwiftOps.swift
//  SwiftOps
//
//  Created by Daniel Hall on 9/11/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import Foundation

// MARK: - Operation -

// MARK: OperationType Protocol


/// A protocol that exists only to enable the below extension
protocol OperationType {
    associatedtype InputType
    associatedtype OutputType
}

/// An extension to add a start method that doesn't require an input parameter if the Operation's input type is Void
extension OperationType where InputType == Void {
    
    
    /// Start the Operation
    ///
    /// - parameter completion: A closure that is called upon completion of the operation. The closure accepts a single throwing closure which either returns to the Operation's result or throws the Operation's error.
    func start(completion:@escaping (() throws -> OutputType)->()) {
        if let me = self as? Operation<InputType, OutputType> {
            me.start(withInput:(), completion:completion)
        }
    }
}

// MARK: Operation


/// A thin wrapper around a function of the type (Input) throws -> Output.  An Operation adds some useful functionality on top of the funtion it wraps, specifically:
/// - Verbs for composing the function/Operation with other functions/Operation ('or', 'then', 'and') without needing custom operators
/// - Declaration of how the function should run ('sync', 'async', 'ui') and automatic dispatch queue management as appropriate
/// - Automatic extrapolation of the nature of composed Operations.  For example, Operation.sync.then(Operation.sync) -> Operation.sync, but Operation.sync.then(Operation.async) -> Operation.async
/// - A visible type for debugging, e.g. 'Operation<Int -> String>' instead of 'Function'
enum Operation<Input, Output> : OperationType, CustomStringConvertible  {
    typealias InputType = Input
    typealias OutputType = Output
    
    /// An Operation that always runs on a background thread and calls back to the main thread when complete. Initialize with an asynchronous function that has the signature (Input, @escaping (Output?, Error?)->())->(), meaning it accepts an input and a completion closure which in turn expects to be passed an optional result and an optional error
    case async(function:(Input, @escaping (Output?, Error?)->())->())
    
    /// An Operation that always runs on the current thread and calls back to the main thread when complete.  Will call back immediately in the same frame if started from the main thread. Initialize with a function that has the signature (Input) throws -> Output
    case sync(function:(Input) throws -> Output)
    
    /// An Operation that always runs on the main thread and calls back to the main thread when complete.  Will call back immediately in the same frame if started from the main thread. Initialize with a function that has the signature (Input) throws -> Output
    case ui(function:(Input) throws -> Output)
    
    
    /// Retrieves the underlying wrapped function
    private var function:(Input) throws -> Output {
        switch self {
        // For async functions, convert the stored callback version into to format (Input) throws -> Output using dispatch semaphores
        case .async(let function) :
            return convertToThrowingFunction(function)
        case .sync(let function) :
            return function
        case .ui(let function) :
            return function
        }
    }
    
    
    /// A description of this type at runtime for debugging
    var description: String {
        switch self {
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
    /// - parameter input: The input that this Operation should use when it is started
    ///
    /// - returns: An OperationGroupOfOne, which is a partially applied Operation (it already has an input value) that can be grouped with other OperationGroup types to be run in parallel using the 'and' method. It can also be started at a later time, or chained with other Operations or groups using 'or' and 'then'.
    func using(input:Input) -> OperationGroupOfOne<Input, Output> {
        return OperationGroupOfOne<Input, Output>(operation:self, input:input)
    }
    
    
    /// Executes the Operation and returns the result via callback to a completion closure. Note that an instance of 'Operation.sync' or 'Operation.ui' will call back immediately in the same frame if started on the main thread, otherwise will call back to the main thread asynchronously.  And instance of 'Operation.async' will always call back to the main thread in a future frame. 'Operation.sync' will always run on whatever thread it was started from, 'Operation.ui' will always run on the main thread, and 'Operation.async' will always run on the default background thread.
    ///
    /// - parameter withInput:  The starting input expected by this Operation
    /// - parameter completion: A closure that the Operation will call with the result when it has completed. The closure will receive a result closure of type () throws -> Output, which means that it needs to be invoke the result closure using try to either extract the final ouput value, or to catch any error the Operation throws.
    func start(withInput:Input, completion:@escaping (@escaping () throws -> Output)->()) {
        switch self {
        // Run on background thread, callback to completion closure on main thread
        case .async :
            DispatchQueue.global().async {
                do {
                    let result = try self.function(withInput)
                    DispatchQueue.main.async {
                        completion { result }
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion { throw(error) }
                    }
                }
            }
        // Run on current thread.  If this is main thread, completion closure called in same frame
        case .sync :
            do {
                let resultClosure = try self.function(withInput)
                if Thread.isMainThread {
                    completion { resultClosure }
                } else {
                    DispatchQueue.main.async {
                        completion { resultClosure }
                    }
                }
            } catch {
                if Thread.isMainThread {
                    completion { throw(error) }
                } else {
                    DispatchQueue.main.async {
                        completion { throw(error) }
                    }
                }
            }
        // Run on main thread and call back on main thread. If already on main thread, happens in same frame
        case .ui :
            var resultClosure:(() throws ->Output)?
            if Thread.isMainThread {
                do {
                    let result = try self.function(withInput)
                    resultClosure = { result }
                } catch {
                    resultClosure = { throw(error) }
                }
            } else {
                let wait = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    do {
                        let result = try self.function(withInput)
                        resultClosure = { result }
                    } catch {
                        resultClosure = { throw(error) }
                    }
                    wait.signal()
                }
                _ = wait.wait(timeout: DispatchTime.distantFuture)
            }
            DispatchQueue.main.async {
                completion(resultClosure!)
            }
        }
    }
    
    
    /// Composes current Operation with the supplied nextOperation and returns new Operation that takes the input of the first and returns the output of the second. For example, Operation<String, Int>.then(Operation<Int, Data>) will return an Operation<String, Data> that executes by first running the left-side Operation and then using the output from that to run the right-side Operation and return its output as the final result.
    ///
    /// - parameter nextOperation: The Operation that should be composed with this Operation and run using the output from this one as input
    ///
    /// - returns: A new Operation that takes the input of the first, uses the output of the first as input for the second, and finally returns the output from the second.
    func then<NextOutput>(_ nextOperation:Operation<Output, NextOutput>) -> Operation<Input, NextOutput> {
        
        let combiningClosure:(Input) throws -> NextOutput = {
            input in
            var finalResult:NextOutput?
            var finalError:Error?
            let wait = DispatchSemaphore(value: 0)
            self.start(withInput: input) {
                result in
                do {
                    let value = try result()
                    nextOperation.start(withInput: value) {
                        result in
                        do {
                            finalResult = try result()
                            wait.signal()
                        } catch {
                            finalError = error
                            wait.signal()
                        }
                        
                    }
                } catch {
                    finalError = error
                    wait.signal()
                }
            }
            _ = wait.wait(timeout: DispatchTime.distantFuture)
            if let finalError = finalError {
                throw(finalError)
            }
            return finalResult!
        }
        
        switch (self, nextOperation) {
        case (.sync, .sync) :
            return Operation<Input, NextOutput>.sync(function: combiningClosure)
        case (.sync, .async) :
            return Operation<Input, NextOutput>.async(function: convertToCallbackFunction(combiningClosure))
        case (.sync, .ui) :
            return Operation<Input, NextOutput>.sync(function: combiningClosure)
        case (.async, .sync) :
            return Operation<Input, NextOutput>.async(function: convertToCallbackFunction(combiningClosure))
        case (.async, .async) :
            return Operation<Input, NextOutput>.async(function: convertToCallbackFunction(combiningClosure))
        case (.async, .ui) :
            return Operation<Input, NextOutput>.async(function: convertToCallbackFunction(combiningClosure))
        case (.ui, .sync) :
            return Operation<Input, NextOutput>.sync(function: combiningClosure)
        case (.ui, .async) :
            return Operation<Input, NextOutput>.async(function: convertToCallbackFunction(combiningClosure))
        case (.ui, .ui) :
            return Operation<Input, NextOutput>.sync(function: combiningClosure)
        }
    }
    
    
    /// Creates a new Operation of the same type as the current Operation and the alternateOperation parameter.  The new Operation will first try to execute the current Operation and if that succeeds, it will return that result.  However if it fails, instead of throwing an error, it will then try the alternateOperation, return that result if successful, or otherwise throw the specified error. Any number of Operations with the same Input and Output types can be combined as alternates using this method.
    ///
    /// - parameter alternateOperation: An Operation that takes the same Input type and returns the same Output type which should run if the current Operation fails.
    ///
    /// - returns: A new Operation with the same type (<Input, Output> as the current Operation and the alternateOperation parameter
    func or(_ alternateOperation:Operation<Input, Output>) -> Operation<Input, Output> {
        
        let combiningClosure:(Input) throws -> Output = {
            input in
            var finalResult:Output?
            var finalError:Error?
            let wait = DispatchSemaphore(value: 0)
            self.start(withInput: input) {
                result in
                do {
                    finalResult = try result()
                    wait.signal()
                } catch {
                    finalError = error
                    alternateOperation.start(withInput: input) {
                        result in
                        do {
                            finalResult = try result()
                            wait.signal()
                        } catch {
                            finalError = error
                            wait.signal()
                        }
                    }
                }
            }
            _ = wait.wait(timeout: DispatchTime.distantFuture)
            if let finalError = finalError {
                throw(finalError)
            }
            return finalResult!
        }
        
        switch (self, alternateOperation) {
        case (.sync, .sync) :
            return Operation<Input, Output>.sync(function: combiningClosure)
        case (.sync, .async) :
            return Operation<Input, Output>.async(function: convertToCallbackFunction(combiningClosure))
        case (.sync, .ui) :
            return Operation<Input, Output>.sync(function: combiningClosure)
        case (.async, .sync) :
            return Operation<Input, Output>.async(function: convertToCallbackFunction(combiningClosure))
        case (.async, .async) :
            return Operation<Input, Output>.async(function: convertToCallbackFunction(combiningClosure))
        case (.async, .ui) :
            return Operation<Input, Output>.async(function: convertToCallbackFunction(combiningClosure))
        case (.ui, .sync) :
            return Operation<Input, Output>.sync(function: combiningClosure)
        case (.ui, .async) :
            return Operation<Input, Output>.async(function: convertToCallbackFunction(combiningClosure))
        case (.ui, .ui) :
            return Operation<Input, Output>.sync(function: combiningClosure)
        }
    }
    
    
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
    
    /// Converts a function with the signature (Input, (Output?, Error?)->())->() to a function with the signature (Input) throws -> Output. Used internally for dealing with async functions
    ///
    /// - parameter function: The function to convert
    private func convertToThrowingFunction<FunctionInput, FunctionOutput>(_ function:@escaping (FunctionInput, @escaping (FunctionOutput?, Error?)->())->()) -> ((FunctionInput) throws -> FunctionOutput) {
        return {
            input in
            var resultOutput:FunctionOutput?
            var resultError:Error?
            let wait = DispatchSemaphore(value: 0)
            function(input){
                output, error in
                if let error = error {
                    resultError = error
                    wait.signal()
                } else if let output = output {
                    resultOutput = output
                    wait.signal()
                } else {
                    wait.signal()
                }
            }
            _ = wait.wait(timeout: DispatchTime.distantFuture)
            if let resultOutput = resultOutput {
                return resultOutput
            } else if let resultError = resultError {
                throw(resultError)
            } else {
                throw(NSError(domain:"swiftops.danielhall.io", code:0, userInfo:[NSLocalizedDescriptionKey : "Asynchronous function returned nil result and nil error"]))
            }
        }
    }
    
}

// MARK: - Operation Groups -

/// An Operation Group consists of one or more Operations that already have their input provided, but which have not yet been started. When an Operation Group is started, all the comprised Operations are run asynchronously and in parallel; when they have _all_ finished executing, a tuple containing all of their results (or errors) is returned to a completion closure. Operation Groups can also be chained with subsequent Operations using the 'then' method, or can be combined using the 'or' method with another Operation Group that runs if any of the first Group's Operations throw an error. Operation Groups can also be added together using the 'and' method to create larger groups of Operations to run in parallel. Since Operation Groups already have the inputs provided for all of their comprised Operations, they don't require any additional input to start running, just a completion closure.
struct OperationGroupOfOne<Input, Output> {
    fileprivate let operation:Operation<Input, Output>
    fileprivate let input:Input
    
    
    /// Initializes the Operation Group with the coorect number of contained Operations and input values for those Operations
    /// - returns: An Operation Group containing the provided Operations
    init(operation:Operation<Input, Output>, input:Input) {
        self.operation = operation
        self.input = input
    }
    
    
    /// Executes all the Operations contained in this Operation Group in parallel on background threads using the inputs previously provided. When all Operations have finished running, the completion closure is called and passed a tuple containing the results from each contained Operation.  The results are each passed in the form of a throwing closure which, when executed will either return the actual result value if it exists, or will throw the error that was generated by the Operation when it ran.
    ///
    /// - parameter completion: A closure that is called when all the Operations in this Operation Group have finished executing. The completion closure is passed a tuple containing the results from each contained Operation.  The results are each passed in the form of a throwing closure which, when executed will either return the actual result value if it exists, or will throw the error that was generated by the Operation when it ran.
    func start(completion:@escaping ((@escaping () throws -> Output))->()) {
        operation.start(withInput: input) {
            result in
            if Thread.isMainThread {
                completion(result)
            } else {
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }
    
    /// Combines this Operation Group with provided additionalOperationGroup to create a new Operation Group that contains all the Operations from both.
    ///
    /// - parameter additionalOperationGroup: Another Operation Group containing one or more Operations that should run in parallel with this Operation Group's Operations.
    ///
    /// - returns: A new Operation Group that contains all the Operations from this Operation Group plus all the Operations from the additionalOperationGroup
    func and<NextInput, NextOutput>(_ additionalOperationGroup:OperationGroupOfOne<NextInput, NextOutput>) -> OperationGroupOfTwo<Input, Output, NextInput, NextOutput> {
        return OperationGroupOfTwo<Input, Output, NextInput, NextOutput>(operationOne:operation, inputOne:input, operationTwo:additionalOperationGroup.operation, inputTwo:additionalOperationGroup.input)
    }
    
    /// Combines this Operation Group with provided additionalOperationGroup to create a new Operation Group that contains all the Operations from both.
    ///
    /// - parameter additionalOperationGroup: Another Operation Group containing one or more Operations that should run in parallel with this Operation Group's Operations.
    ///
    /// - returns: A new Operation Group that contains all the Operations from this Operation Group plus all the Operations from the additionalOperationGroup
    func and<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo>(_ additionalOperationGroup:OperationGroupOfTwo<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo>) -> OperationGroupOfThree<Input, Output, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo> {
        return OperationGroupOfThree<Input, Output, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo>(operationOne:operation, inputOne:input, operationTwo:additionalOperationGroup.operationOne, inputTwo:additionalOperationGroup.inputOne, operationThree:additionalOperationGroup.operationTwo, inputThree:additionalOperationGroup.inputTwo)
    }
    
    /// Combines this Operation Group with provided additionalOperationGroup to create a new Operation Group that contains all the Operations from both.
    ///
    /// - parameter additionalOperationGroup: Another Operation Group containing one or more Operations that should run in parallel with this Operation Group's Operations.
    ///
    /// - returns: A new Operation Group that contains all the Operations from this Operation Group plus all the Operations from the additionalOperationGroup
    func and<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree>(_ additionalOperationGroup:OperationGroupOfThree<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree>) -> OperationGroupOfFour<Input, Output, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree> {
        return OperationGroupOfFour<Input, Output, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree>(operationOne:operation, inputOne:input, operationTwo:additionalOperationGroup.operationOne, inputTwo:additionalOperationGroup.inputOne, operationThree:additionalOperationGroup.operationTwo, inputThree:additionalOperationGroup.inputTwo, operationFour:additionalOperationGroup.operationThree, inputFour:additionalOperationGroup.inputThree)
    }
    
    /// Combines this Operation Group with provided additionalOperationGroup to create a new Operation Group that contains all the Operations from both.
    ///
    /// - parameter additionalOperationGroup: Another Operation Group containing one or more Operations that should run in parallel with this Operation Group's Operations.
    ///
    /// - returns: A new Operation Group that contains all the Operations from this Operation Group plus all the Operations from the additionalOperationGroup
    func and<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree, NextInputFour, NextOutputFour>(_ additionalOperationGroup:OperationGroupOfFour<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree, NextInputFour, NextOutputFour>) -> OperationGroupOfFive<Input, Output, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree, NextInputFour, NextOutputFour> {
        return OperationGroupOfFive<Input, Output, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree, NextInputFour, NextOutputFour>(operationOne:operation, inputOne:input, operationTwo:additionalOperationGroup.operationOne, inputTwo:additionalOperationGroup.inputOne, operationThree:additionalOperationGroup.operationTwo, inputThree:additionalOperationGroup.inputTwo, operationFour:additionalOperationGroup.operationThree, inputFour:additionalOperationGroup.inputThree, operationFive:additionalOperationGroup.operationFour, inputFive:additionalOperationGroup.inputFour)
    }
    
    /// Composes this Operation Group with the supplied nextOperation and returns new Operation that runs the Operation Group, passes its resulting output to the nextOperation, and executes the nextOperation, finally returning its result.
    /// - parameter nextOperation: The Operation that should be composed with this Operation Group and run using the tuple output from this Group as its input
    ///
    /// - returns: A new Operation that has a Void Input type (because Operation Groups are pre-populated with their Input), and returns the output of the nextOperation parameter
    func then<NextOutput>(_ nextOperation:Operation<Output, NextOutput>) -> Operation<Void, NextOutput> {
        return Operation.async {
            _, completion in
            self.start {
                do {
                    nextOperation.start(withInput: try $0()) {
                        result in
                        do {
                            completion(try result(), nil)
                        } catch {
                            completion(nil, error)
                        }
                    }
                } catch {
                    completion(nil, error)
                }
            }
        }
    }
    
    /// Creates a new Operation Group that has the same Output types as the current Operation Group and the alternateGroup parameter.  The new Operation Group will first execute all of its own Operations, and if they all succeed it will return a tuple of their Outputs as a result. However if it fails, instead of throwing an error it will then execute the alternateGroup, return that result if successful, or otherwise throw the error that caused it to fail. Any number of Operation Groups with the same number and types of Outputs can be combined as alternates using this method.
    ///
    /// - parameter alternateGroup: An Operation Group that has the same number and types of Output should run if the current Operation Group fails.
    ///
    /// - returns: A new Operation Group with Void Input Types but the same number and types of Output as the current Operation Group and the alternateGroup parameter
    func or<OtherInput>(_ alternateGroup:OperationGroupOfOne<OtherInput, Output>) -> OperationGroupOfOne<Void, Output> {
        let compoundOperation = Operation<Void, Output>.async {
            _, completion in
            self.start {
                result in
                do {
                    completion(try result(), nil)
                } catch {
                    alternateGroup.start {
                        alternateResult in
                        do {
                            completion(try alternateResult(), nil)
                        } catch {
                            completion(nil, error)
                        }
                    }
                }
            }
        }
        return OperationGroupOfOne<Void, Output>(operation: compoundOperation, input: ())
    }
}

/// An Operation Group consists of one or more Operations that already have their input provided, but which have not yet been started. When an Operation Group is started, all the comprised Operations are run asynchronously and in parallel; when they have _all_ finished executing, a tuple containing all of their results (or errors) is returned to a completion closure. Operation Groups can also be chained with subsequent Operations using the 'then' method, or can be combined using the 'or' method with another Operation Group that runs if any of the first Group's Operations throw an error. Operation Groups can also be added together using the 'and' method to create larger groups of Operations to run in parallel. Since Operation Groups already have the inputs provided for all of their comprised Operations, they don't require any additional input to start running, just a completion closure.
struct OperationGroupOfTwo<InputOne, OutputOne, InputTwo, OutputTwo> {
    fileprivate let operationOne:Operation<InputOne, OutputOne>!
    fileprivate let inputOne:InputOne!
    fileprivate let operationTwo:Operation<InputTwo, OutputTwo>!
    fileprivate let inputTwo:InputTwo!
    private let condensedOperation:Operation <Void, (OutputOne, OutputTwo)>?
    
    /// Initializes the Operation Group with the coorect number of contained Operations and input values for those Operations
    /// - returns: An Operation Group containing the provided Operations
    init(operationOne:Operation<InputOne, OutputOne>, inputOne:InputOne, operationTwo:Operation<InputTwo, OutputTwo>, inputTwo:InputTwo) {
        self.operationOne = operationOne
        self.inputOne = inputOne
        self.operationTwo = operationTwo
        self.inputTwo = inputTwo
        self.condensedOperation = nil
    }
    
    /// Initializes the Operation Group with a single compound Operation, used internally when combining two Operation Groups with the 'or' method
    /// - returns: An Operation Group containing an Operation that will try multiple alternative Operation Groups when executed until one Group succeeds or they all fail.
    private init(operation:Operation <Void, (OutputOne, OutputTwo)>) {
        self.operationOne = nil
        self.inputOne = nil
        self.operationTwo = nil
        self.inputTwo = nil
        self.condensedOperation = operation
    }
    
    /// Combines this Operation Group with provided additionalOperationGroup to create a new Operation Group that contains all the Operations from both.
    ///
    /// - parameter additionalOperationGroup: Another Operation Group containing one or more Operations that should run in parallel with this Operation Group's Operations.
    ///
    /// - returns: A new Operation Group that contains all the Operations from this Operation Group plus all the Operations from the additionalOperationGroup
    func and<NextInput, NextOutput>(_ additionalOperationGroup:OperationGroupOfOne<NextInput, NextOutput>) -> OperationGroupOfThree<InputOne, OutputOne, InputTwo, OutputTwo, NextInput, NextOutput> {
        return OperationGroupOfThree<InputOne, OutputOne, InputTwo, OutputTwo, NextInput, NextOutput>(operationOne:operationOne, inputOne:inputOne, operationTwo:operationTwo, inputTwo:inputTwo, operationThree:additionalOperationGroup.operation, inputThree:additionalOperationGroup.input)
    }
    
    /// Combines this Operation Group with provided additionalOperationGroup to create a new Operation Group that contains all the Operations from both.
    ///
    /// - parameter additionalOperationGroup: Another Operation Group containing one or more Operations that should run in parallel with this Operation Group's Operations.
    ///
    /// - returns: A new Operation Group that contains all the Operations from this Operation Group plus all the Operations from the additionalOperationGroup
    func and<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo>(_ additionalOperationGroup:OperationGroupOfTwo<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo>) -> OperationGroupOfFour<InputOne, OutputOne, InputTwo, OutputTwo, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo> {
        return OperationGroupOfFour<InputOne, OutputOne, InputTwo, OutputTwo, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo> (operationOne:operationOne, inputOne:inputOne, operationTwo:operationTwo, inputTwo:inputTwo, operationThree:additionalOperationGroup.operationOne, inputThree:additionalOperationGroup.inputOne, operationFour:additionalOperationGroup.operationTwo, inputFour:additionalOperationGroup.inputTwo)
    }
    
    /// Combines this Operation Group with provided additionalOperationGroup to create a new Operation Group that contains all the Operations from both.
    ///
    /// - parameter additionalOperationGroup: Another Operation Group containing one or more Operations that should run in parallel with this Operation Group's Operations.
    ///
    /// - returns: A new Operation Group that contains all the Operations from this Operation Group plus all the Operations from the additionalOperationGroup
    func and<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree>(_ additionalOperationGroup:OperationGroupOfThree<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree>) -> OperationGroupOfFive<InputOne, OutputOne, InputTwo, OutputTwo, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree> {
        return OperationGroupOfFive<InputOne, OutputOne, InputTwo, OutputTwo, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo, NextInputThree, NextOutputThree> (operationOne:operationOne, inputOne:inputOne, operationTwo:operationTwo, inputTwo:inputTwo, operationThree:additionalOperationGroup.operationOne, inputThree:additionalOperationGroup.inputOne, operationFour:additionalOperationGroup.operationTwo, inputFour:additionalOperationGroup.inputTwo, operationFive:additionalOperationGroup.operationThree, inputFive:additionalOperationGroup.inputThree)
    }
    
    /// Executes all the Operations contained in this Operation Group in parallel on background threads using the inputs previously provided. When all Operations have finished running, the completion closure is called and passed a tuple containing the results from each contained Operation.  The results are each passed in the form of a throwing closure which, when executed will either return the actual result value if it exists, or will throw the error that was generated by the Operation when it ran.
    ///
    /// - parameter completion: A closure that is called when all the Operations in this Operation Group have finished executing. The completion closure is passed a tuple containing the results from each contained Operation.  The results are each passed in the form of a throwing closure which, when executed will either return the actual result value if it exists, or will throw the error that was generated by the Operation when it ran.
    func start(completion:@escaping ((@escaping () throws -> OutputOne, @escaping () throws -> OutputTwo))->()) {
        if let condensedOperation = condensedOperation {
            condensedOperation.start {
                do {
                    let result = try $0()
                    completion(({result.0}, {result.1}))
                } catch {
                    completion(({ throw(error) }, { throw(error) }))
                }
            }
            return
        }
        
        DispatchQueue.global().async {
            var resultOne:(() throws -> OutputOne)?
            var resultTwo:(() throws -> OutputTwo)?
            
            let wait = DispatchSemaphore(value: 0)
            
            DispatchQueue.global().async {
                self.operationOne.start(withInput: self.inputOne) {
                    resultOne = $0
                    wait.signal()
                }
            }
            
            DispatchQueue.global().async {
                self.operationTwo.start(withInput: self.inputTwo) {
                    resultTwo = $0
                    wait.signal()
                }
            }
            
            (1...2).forEach { _ in _ = wait.wait(timeout: DispatchTime.distantFuture) }
            
            DispatchQueue.main.async {
                completion((resultOne!, resultTwo!))
            }
        }
    }
    
    /// Composes this Operation Group with the supplied nextOperation and returns new Operation that runs the Operation Group, passes its resulting output to the nextOperation, and executes the nextOperation, finally returning its result.
    /// - parameter nextOperation: The Operation that should be composed with this Operation Group and run using the tuple output from this Group as its input
    ///
    /// - returns: A new Operation that has a Void Input type (because Operation Groups are pre-populated with their Input), and returns the output of the nextOperation parameter
    func then<NextOutput>(_ nextOperation:Operation<(OutputOne, OutputTwo), NextOutput>) -> Operation<Void, NextOutput> {
        return Operation.async {
            _, completion in
            self.start {
                do {
                    nextOperation.start(withInput: (try $0(), try $1())) {
                        result in
                        do {
                            completion(try result(), nil)
                        } catch {
                            completion(nil, error)
                        }
                    }
                } catch {
                    completion(nil, error)
                }
            }
        }
    }
    
    /// Creates a new Operation Group that has the same Output types as the current Operation Group and the alternateGroup parameter.  The new Operation Group will first execute all of its own Operations, and if they all succeed it will return a tuple of their Outputs as a result. However if it fails, instead of throwing an error it will then execute the alternateGroup, return that result if successful, or otherwise throw the error that caused it to fail. Any number of Operation Groups with the same number and types of Outputs can be combined as alternates using this method.
    ///
    /// - parameter alternateGroup: An Operation Group that has the same number and types of Output should run if the current Operation Group fails.
    ///
    /// - returns: A new Operation Group with Void Input Types but the same number and types of Output as the current Operation Group and the alternateGroup parameter
    func or<OtherInputOne, OtherInputTwo>(_ alternateGroup:OperationGroupOfTwo<OtherInputOne, OutputOne, OtherInputTwo, OutputTwo>) ->OperationGroupOfTwo<Void, OutputOne, Void, OutputTwo> {
        let compoundOperation = Operation<Void, (OutputOne, OutputTwo)>.async {
            _, completion in
            self.start {
                result in
                do {
                    completion((try result.0(), try result.1()), nil)
                } catch {
                    alternateGroup.start {
                        alternateResult in
                        do {
                            completion((try alternateResult.0(), try alternateResult.1()), nil)
                        } catch {
                            completion(nil, error)
                        }
                    }
                }
            }
        }
        return OperationGroupOfTwo<Void, OutputOne, Void, OutputTwo>(operation: compoundOperation)
    }
}

/// An Operation Group consists of one or more Operations that already have their input provided, but which have not yet been started. When an Operation Group is started, all the comprised Operations are run asynchronously and in parallel; when they have _all_ finished executing, a tuple containing all of their results (or errors) is returned to a completion closure. Operation Groups can also be chained with subsequent Operations using the 'then' method, or can be combined using the 'or' method with another Operation Group that runs if any of the first Group's Operations throw an error. Operation Groups can also be added together using the 'and' method to create larger groups of Operations to run in parallel. Since Operation Groups already have the inputs provided for all of their comprised Operations, they don't require any additional input to start running, just a completion closure.
struct OperationGroupOfThree<InputOne, OutputOne, InputTwo, OutputTwo, InputThree, OutputThree> {
    fileprivate let operationOne:Operation<InputOne, OutputOne>!
    fileprivate let inputOne:InputOne!
    fileprivate let operationTwo:Operation<InputTwo, OutputTwo>!
    fileprivate let inputTwo:InputTwo!
    fileprivate let operationThree:Operation<InputThree, OutputThree>!
    fileprivate let inputThree:InputThree!
    private let condensedOperation:Operation <Void, (OutputOne, OutputTwo, OutputThree)>?
    
    /// Initializes the Operation Group with the coorect number of contained Operations and input values for those Operations
    /// - returns: An Operation Group containing the provided Operations
    init(operationOne:Operation<InputOne, OutputOne>, inputOne:InputOne, operationTwo:Operation<InputTwo, OutputTwo>, inputTwo:InputTwo, operationThree:Operation<InputThree, OutputThree>, inputThree:InputThree) {
        self.operationOne = operationOne
        self.inputOne = inputOne
        self.operationTwo = operationTwo
        self.inputTwo = inputTwo
        self.operationThree = operationThree
        self.inputThree = inputThree
        self.condensedOperation = nil
    }
    
    /// Initializes the Operation Group with a single compound Operation, used internally when combining two Operation Groups with the 'or' method
    /// - returns: An Operation Group containing an Operation that will try multiple alternative Operation Groups when executed until one Group succeeds or they all fail.
    private init(operation:Operation <Void, (OutputOne, OutputTwo, OutputThree)>) {
        self.operationOne = nil
        self.inputOne = nil
        self.operationTwo = nil
        self.inputTwo = nil
        self.operationThree = nil
        self.inputThree = nil
        self.condensedOperation = operation
    }
    
    /// Combines this Operation Group with provided additionalOperationGroup to create a new Operation Group that contains all the Operations from both.
    ///
    /// - parameter additionalOperationGroup: Another Operation Group containing one or more Operations that should run in parallel with this Operation Group's Operations.
    ///
    /// - returns: A new Operation Group that contains all the Operations from this Operation Group plus all the Operations from the additionalOperationGroup
    func and<NextInput, NextOutput>(_ additionalOperationGroup:OperationGroupOfOne<NextInput, NextOutput>) -> OperationGroupOfFour<InputOne, OutputOne, InputTwo, OutputTwo, InputThree, OutputThree, NextInput, NextOutput> {
        return OperationGroupOfFour<InputOne, OutputOne, InputTwo, OutputTwo, InputThree, OutputThree, NextInput, NextOutput>(operationOne:operationOne, inputOne:inputOne, operationTwo:operationTwo, inputTwo:inputTwo, operationThree:operationThree, inputThree:inputThree, operationFour:additionalOperationGroup.operation, inputFour:additionalOperationGroup.input)
    }
    
    /// Combines this Operation Group with provided additionalOperationGroup to create a new Operation Group that contains all the Operations from both.
    ///
    /// - parameter additionalOperationGroup: Another Operation Group containing one or more Operations that should run in parallel with this Operation Group's Operations.
    ///
    /// - returns: A new Operation Group that contains all the Operations from this Operation Group plus all the Operations from the additionalOperationGroup
    func and<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo>(_ additionalOperationGroup:OperationGroupOfTwo<NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo>) -> OperationGroupOfFive<InputOne, OutputOne, InputTwo, OutputTwo, InputThree, OutputThree, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo> {
        return OperationGroupOfFive<InputOne, OutputOne, InputTwo, OutputTwo, InputThree, OutputThree, NextInputOne, NextOutputOne, NextInputTwo, NextOutputTwo>(operationOne:operationOne, inputOne:inputOne, operationTwo:operationTwo, inputTwo:inputTwo, operationThree:operationThree, inputThree:inputThree, operationFour:additionalOperationGroup.operationOne, inputFour:additionalOperationGroup.inputOne, operationFive:additionalOperationGroup.operationTwo, inputFive:additionalOperationGroup.inputTwo)
    }
    
    /// Executes all the Operations contained in this Operation Group in parallel on background threads using the inputs previously provided. When all Operations have finished running, the completion closure is called and passed a tuple containing the results from each contained Operation.  The results are each passed in the form of a throwing closure which, when executed will either return the actual result value if it exists, or will throw the error that was generated by the Operation when it ran.
    ///
    /// - parameter completion: A closure that is called when all the Operations in this Operation Group have finished executing. The completion closure is passed a tuple containing the results from each contained Operation.  The results are each passed in the form of a throwing closure which, when executed will either return the actual result value if it exists, or will throw the error that was generated by the Operation when it ran.
    func start(completion:@escaping ((@escaping () throws -> OutputOne, @escaping () throws -> OutputTwo, @escaping () throws -> OutputThree))->()) {
        if let condensedOperation = condensedOperation {
            condensedOperation.start {
                do {
                    let result = try $0()
                    completion(({result.0}, {result.1}, {result.2}))
                } catch {
                    completion(({ throw(error) }, { throw(error) }, { throw(error) }))
                }
            }
            return
        }
        
        DispatchQueue.global().async {
            var resultOne:(() throws -> OutputOne)?
            var resultTwo:(() throws -> OutputTwo)?
            var resultThree:(() throws -> OutputThree)?
            
            let wait = DispatchSemaphore(value: 0)
            
            DispatchQueue.global().async {
                self.operationOne.start(withInput: self.inputOne) {
                    resultOne = $0
                    wait.signal()
                }
            }
            
            DispatchQueue.global().async {
                self.operationTwo.start(withInput: self.inputTwo) {
                    resultTwo = $0
                    wait.signal()
                }
            }
            
            DispatchQueue.global().async {
                self.operationThree.start(withInput: self.inputThree) {
                    resultThree = $0
                    wait.signal()
                }
            }
            
            (1...3).forEach { _ in _ = wait.wait(timeout: DispatchTime.distantFuture) }
            
            DispatchQueue.main.async {
                completion((resultOne!, resultTwo!, resultThree!))
            }
        }
    }
    
    /// Composes this Operation Group with the supplied nextOperation and returns new Operation that runs the Operation Group, passes its resulting output to the nextOperation, and executes the nextOperation, finally returning its result.
    /// - parameter nextOperation: The Operation that should be composed with this Operation Group and run using the tuple output from this Group as its input
    ///
    /// - returns: A new Operation that has a Void Input type (because Operation Groups are pre-populated with their Input), and returns the output of the nextOperation parameter
    func then<NextOutput>(_ nextOperation:Operation<(OutputOne, OutputTwo, OutputThree), NextOutput>) -> Operation<Void, NextOutput> {
        return Operation.async {
            _, completion in
            self.start {
                do {
                    nextOperation.start(withInput: (try $0(), try $1(), try $2())) {
                        result in
                        do {
                            completion(try result(), nil)
                        } catch {
                            completion(nil, error)
                        }
                    }
                } catch {
                    completion(nil, error)
                }
            }
        }
    }
    
    /// Creates a new Operation Group that has the same Output types as the current Operation Group and the alternateGroup parameter.  The new Operation Group will first execute all of its own Operations, and if they all succeed it will return a tuple of their Outputs as a result. However if it fails, instead of throwing an error it will then execute the alternateGroup, return that result if successful, or otherwise throw the error that caused it to fail. Any number of Operation Groups with the same number and types of Outputs can be combined as alternates using this method.
    ///
    /// - parameter alternateGroup: An Operation Group that has the same number and types of Output should run if the current Operation Group fails.
    ///
    /// - returns: A new Operation Group with Void Input Types but the same number and types of Output as the current Operation Group and the alternateGroup parameter
    func or<OtherInputOne, OtherInputTwo, OtherInputThree>(_ alternateGroup:OperationGroupOfThree<OtherInputOne, OutputOne, OtherInputTwo, OutputTwo, OtherInputThree, OutputThree>) ->OperationGroupOfThree<Void, OutputOne, Void, OutputTwo, Void, OutputThree> {
        let compoundOperation = Operation<Void, (OutputOne, OutputTwo, OutputThree)>.async {
            _, completion in
            self.start {
                result in
                do {
                    completion((try result.0(), try result.1(), try result.2()), nil)
                } catch {
                    alternateGroup.start {
                        alternateResult in
                        do {
                            completion((try alternateResult.0(), try alternateResult.1(), try alternateResult.2()), nil)
                        } catch {
                            completion(nil, error)
                        }
                    }
                }
            }
        }
        return OperationGroupOfThree<Void, OutputOne, Void, OutputTwo, Void, OutputThree>(operation: compoundOperation)
    }
}

/// An Operation Group consists of one or more Operations that already have their input provided, but which have not yet been started. When an Operation Group is started, all the comprised Operations are run asynchronously and in parallel; when they have _all_ finished executing, a tuple containing all of their results (or errors) is returned to a completion closure. Operation Groups can also be chained with subsequent Operations using the 'then' method, or can be combined using the 'or' method with another Operation Group that runs if any of the first Group's Operations throw an error. Operation Groups can also be added together using the 'and' method to create larger groups of Operations to run in parallel. Since Operation Groups already have the inputs provided for all of their comprised Operations, they don't require any additional input to start running, just a completion closure.
struct OperationGroupOfFour<InputOne, OutputOne, InputTwo, OutputTwo, InputThree, OutputThree, InputFour, OutputFour> {
    fileprivate let operationOne:Operation<InputOne, OutputOne>!
    fileprivate let inputOne:InputOne!
    fileprivate let operationTwo:Operation<InputTwo, OutputTwo>!
    fileprivate let inputTwo:InputTwo!
    fileprivate let operationThree:Operation<InputThree, OutputThree>!
    fileprivate let inputThree:InputThree!
    fileprivate let operationFour:Operation<InputFour, OutputFour>!
    fileprivate let inputFour:InputFour!
    private let condensedOperation:Operation <Void, (OutputOne, OutputTwo, OutputThree, OutputFour)>?
    
    /// Initializes the Operation Group with the coorect number of contained Operations and input values for those Operations
    /// - returns: An Operation Group containing the provided Operations
    init(operationOne:Operation<InputOne, OutputOne>, inputOne:InputOne, operationTwo:Operation<InputTwo, OutputTwo>, inputTwo:InputTwo, operationThree:Operation<InputThree, OutputThree>, inputThree:InputThree, operationFour:Operation<InputFour, OutputFour>, inputFour:InputFour) {
        self.operationOne = operationOne
        self.inputOne = inputOne
        self.operationTwo = operationTwo
        self.inputTwo = inputTwo
        self.operationThree = operationThree
        self.inputThree = inputThree
        self.operationFour = operationFour
        self.inputFour = inputFour
        self.condensedOperation = nil
    }
    
    /// Initializes the Operation Group with a single compound Operation, used internally when combining two Operation Groups with the 'or' method
    /// - returns: An Operation Group containing an Operation that will try multiple alternative Operation Groups when executed until one Group succeeds or they all fail.
    private init(operation:Operation <Void, (OutputOne, OutputTwo, OutputThree, OutputFour)>) {
        self.operationOne = nil
        self.inputOne = nil
        self.operationTwo = nil
        self.inputTwo = nil
        self.operationThree = nil
        self.inputThree = nil
        self.operationFour = nil
        self.inputFour = nil
        self.condensedOperation = operation
    }
    
    /// Combines this Operation Group with provided additionalOperationGroup to create a new Operation Group that contains all the Operations from both.
    ///
    /// - parameter additionalOperationGroup: Another Operation Group containing one or more Operations that should run in parallel with this Operation Group's Operations.
    ///
    /// - returns: A new Operation Group that contains all the Operations from this Operation Group plus all the Operations from the additionalOperationGroup
    func and<NextInput, NextOutput>(_ additionalOperationGroup:OperationGroupOfOne<NextInput, NextOutput>) -> OperationGroupOfFive<InputOne, OutputOne, InputTwo, OutputTwo, InputThree, OutputThree, InputFour, OutputFour, NextInput, NextOutput> {
        return OperationGroupOfFive<InputOne, OutputOne, InputTwo, OutputTwo, InputThree, OutputThree, InputFour, OutputFour, NextInput, NextOutput>(operationOne:operationOne, inputOne:inputOne, operationTwo:operationTwo, inputTwo:inputTwo, operationThree:operationThree, inputThree:inputThree, operationFour:operationFour, inputFour:inputFour, operationFive:additionalOperationGroup.operation, inputFive:additionalOperationGroup.input)
    }
    
    /// Executes all the Operations contained in this Operation Group in parallel on background threads using the inputs previously provided. When all Operations have finished running, the completion closure is called and passed a tuple containing the results from each contained Operation.  The results are each passed in the form of a throwing closure which, when executed will either return the actual result value if it exists, or will throw the error that was generated by the Operation when it ran.
    ///
    /// - parameter completion: A closure that is called when all the Operations in this Operation Group have finished executing. The completion closure is passed a tuple containing the results from each contained Operation.  The results are each passed in the form of a throwing closure which, when executed will either return the actual result value if it exists, or will throw the error that was generated by the Operation when it ran.
    func start(completion:@escaping ((@escaping () throws -> OutputOne, @escaping () throws -> OutputTwo, @escaping () throws -> OutputThree, @escaping () throws -> OutputFour))->()) {
        if let condensedOperation = condensedOperation {
            condensedOperation.start {
                do {
                    let result = try $0()
                    completion(({result.0}, {result.1}, {result.2}, {result.3}))
                } catch {
                    completion(({ throw(error) }, { throw(error) }, { throw(error) }, { throw(error) }))
                }
            }
            return
        }
        
        DispatchQueue.global().async {
            var resultOne:(() throws -> OutputOne)?
            var resultTwo:(() throws -> OutputTwo)?
            var resultThree:(() throws -> OutputThree)?
            var resultFour:(() throws -> OutputFour)?
            
            let wait = DispatchSemaphore(value: 0)
            
            DispatchQueue.global().async {
                self.operationOne.start(withInput: self.inputOne) {
                    resultOne = $0
                    wait.signal()
                }
            }
            
            DispatchQueue.global().async {
                self.operationTwo.start(withInput: self.inputTwo) {
                    resultTwo = $0
                    wait.signal()
                }
            }
            
            DispatchQueue.global().async {
                self.operationThree.start(withInput: self.inputThree) {
                    resultThree = $0
                    wait.signal()
                }
            }
            
            DispatchQueue.global().async {
                self.operationFour.start(withInput: self.inputFour) {
                    resultFour = $0
                    wait.signal()
                }
            }
            
            (1...4).forEach { _ in _ = wait.wait(timeout: DispatchTime.distantFuture) }
            
            DispatchQueue.main.async {
                completion((resultOne!, resultTwo!, resultThree!, resultFour!))
            }
        }
    }
    
    /// Composes this Operation Group with the supplied nextOperation and returns new Operation that runs the Operation Group, passes its resulting output to the nextOperation, and executes the nextOperation, finally returning its result.
    /// - parameter nextOperation: The Operation that should be composed with this Operation Group and run using the tuple output from this Group as its input
    ///
    /// - returns: A new Operation that has a Void Input type (because Operation Groups are pre-populated with their Input), and returns the output of the nextOperation parameter
    func then<NextOutput>(_ nextOperation:Operation<(OutputOne, OutputTwo, OutputThree, OutputFour), NextOutput>) -> Operation<Void, NextOutput> {
        return Operation.async {
            _, completion in
            self.start {
                do {
                    nextOperation.start(withInput: (try $0(), try $1(), try $2(), try $3())) {
                        result in
                        do {
                            completion(try result(), nil)
                        } catch {
                            completion(nil, error)
                        }
                    }
                } catch {
                    completion(nil, error)
                }
            }
        }
    }
    
    /// Creates a new Operation Group that has the same Output types as the current Operation Group and the alternateGroup parameter.  The new Operation Group will first execute all of its own Operations, and if they all succeed it will return a tuple of their Outputs as a result. However if it fails, instead of throwing an error it will then execute the alternateGroup, return that result if successful, or otherwise throw the error that caused it to fail. Any number of Operation Groups with the same number and types of Outputs can be combined as alternates using this method.
    ///
    /// - parameter alternateGroup: An Operation Group that has the same number and types of Output should run if the current Operation Group fails.
    ///
    /// - returns: A new Operation Group with Void Input Types but the same number and types of Output as the current Operation Group and the alternateGroup parameter
    func or<OtherInputOne, OtherInputTwo, OtherInputThree, OtherInputFour>(_ alternateGroup:OperationGroupOfFour<OtherInputOne, OutputOne, OtherInputTwo, OutputTwo, OtherInputThree, OutputThree, OtherInputFour, OutputFour>) ->OperationGroupOfFour<Void, OutputOne, Void, OutputTwo, Void, OutputThree, Void, OutputFour> {
        let compoundOperation = Operation<Void, (OutputOne, OutputTwo, OutputThree, OutputFour)>.async {
            _, completion in
            self.start {
                result in
                do {
                    completion((try result.0(), try result.1(), try result.2(), try result.3()), nil)
                } catch {
                    alternateGroup.start {
                        alternateResult in
                        do {
                            completion((try alternateResult.0(), try alternateResult.1(), try alternateResult.2(), try alternateResult.3()), nil)
                        } catch {
                            completion(nil, error)
                        }
                    }
                }
            }
        }
        return OperationGroupOfFour<Void, OutputOne, Void, OutputTwo, Void, OutputThree, Void, OutputFour>(operation: compoundOperation)
    }
}

/// An Operation Group consists of one or more Operations that already have their input provided, but which have not yet been started. When an Operation Group is started, all the comprised Operations are run asynchronously and in parallel; when they have _all_ finished executing, a tuple containing all of their results (or errors) is returned to a completion closure. Operation Groups can also be chained with subsequent Operations using the 'then' method, or can be combined using the 'or' method with another Operation Group that runs if any of the first Group's Operations throw an error. Operation Groups can also be added together using the 'and' method to create larger groups of Operations to run in parallel. Since Operation Groups already have the inputs provided for all of their comprised Operations, they don't require any additional input to start running, just a completion closure.
struct OperationGroupOfFive<InputOne, OutputOne, InputTwo, OutputTwo, InputThree, OutputThree, InputFour, OutputFour, InputFive, OutputFive> {
    fileprivate let operationOne:Operation<InputOne, OutputOne>!
    fileprivate let inputOne:InputOne!
    fileprivate let operationTwo:Operation<InputTwo, OutputTwo>!
    fileprivate let inputTwo:InputTwo!
    fileprivate let operationThree:Operation<InputThree, OutputThree>!
    fileprivate let inputThree:InputThree!
    fileprivate let operationFour:Operation<InputFour, OutputFour>!
    fileprivate let inputFour:InputFour!
    fileprivate let operationFive:Operation<InputFive, OutputFive>!
    fileprivate let inputFive:InputFive!
    private let condensedOperation:Operation <Void, (OutputOne, OutputTwo, OutputThree, OutputFour, OutputFive)>?
    
    /// Initializes the Operation Group with the coorect number of contained Operations and input values for those Operations
    /// - returns: An Operation Group containing the provided Operations
    init(operationOne:Operation<InputOne, OutputOne>, inputOne:InputOne, operationTwo:Operation<InputTwo, OutputTwo>, inputTwo:InputTwo, operationThree:Operation<InputThree, OutputThree>, inputThree:InputThree, operationFour:Operation<InputFour, OutputFour>, inputFour:InputFour, operationFive:Operation<InputFive, OutputFive>, inputFive:InputFive) {
        self.operationOne = operationOne
        self.inputOne = inputOne
        self.operationTwo = operationTwo
        self.inputTwo = inputTwo
        self.operationThree = operationThree
        self.inputThree = inputThree
        self.operationFour = operationFour
        self.inputFour = inputFour
        self.operationFive = operationFive
        self.inputFive = inputFive
        self.condensedOperation = nil
    }
    
    /// Initializes the Operation Group with a single compound Operation, used internally when combining two Operation Groups with the 'or' method
    /// - returns: An Operation Group containing an Operation that will try multiple alternative Operation Groups when executed until one Group succeeds or they all fail.
    private init(operation:Operation <Void, (OutputOne, OutputTwo, OutputThree, OutputFour, OutputFive)>) {
        self.operationOne = nil
        self.inputOne = nil
        self.operationTwo = nil
        self.inputTwo = nil
        self.operationThree = nil
        self.inputThree = nil
        self.operationFour = nil
        self.inputFour = nil
        self.operationFive = nil
        self.inputFive = nil
        self.condensedOperation = operation
    }
    
    /// Executes all the Operations contained in this Operation Group in parallel on background threads using the inputs previously provided. When all Operations have finished running, the completion closure is called and passed a tuple containing the results from each contained Operation.  The results are each passed in the form of a throwing closure which, when executed will either return the actual result value if it exists, or will throw the error that was generated by the Operation when it ran.
    ///
    /// - parameter completion: A closure that is called when all the Operations in this Operation Group have finished executing. The completion closure is passed a tuple containing the results from each contained Operation.  The results are each passed in the form of a throwing closure which, when executed will either return the actual result value if it exists, or will throw the error that was generated by the Operation when it ran.
    func start(completion:@escaping ((@escaping () throws -> OutputOne, @escaping () throws -> OutputTwo, @escaping () throws -> OutputThree, @escaping () throws -> OutputFour, @escaping () throws -> OutputFive))->()) {
        if let condensedOperation = condensedOperation {
            condensedOperation.start {
                do {
                    let result = try $0()
                    completion(({result.0}, {result.1}, {result.2}, {result.3}, {result.4}))
                } catch {
                    completion(({ throw(error) }, { throw(error) }, { throw(error) }, { throw(error) }, { throw(error) }))
                }
            }
            return
        }
        
        DispatchQueue.global().async {
            var resultOne:(() throws -> OutputOne)?
            var resultTwo:(() throws -> OutputTwo)?
            var resultThree:(() throws -> OutputThree)?
            var resultFour:(() throws -> OutputFour)?
            var resultFive:(() throws -> OutputFive)?
            
            let wait = DispatchSemaphore(value: 0)
            
            DispatchQueue.global().async {
                self.operationOne.start(withInput: self.inputOne) {
                    resultOne = $0
                    wait.signal()
                }
            }
            
            DispatchQueue.global().async {
                self.operationTwo.start(withInput: self.inputTwo) {
                    resultTwo = $0
                    wait.signal()
                }
            }
            
            DispatchQueue.global().async {
                self.operationThree.start(withInput: self.inputThree) {
                    resultThree = $0
                    wait.signal()
                }
            }
            
            DispatchQueue.global().async {
                self.operationFour.start(withInput: self.inputFour) {
                    resultFour = $0
                    wait.signal()
                }
            }
            
            DispatchQueue.global().async {
                self.operationFive.start(withInput: self.inputFive) {
                    resultFive = $0
                    wait.signal()
                }
            }
            
            (1...5).forEach { _ in _ = wait.wait(timeout: DispatchTime.distantFuture) }
            
            DispatchQueue.main.async {
                completion((resultOne!, resultTwo!, resultThree!, resultFour!, resultFive!))
            }
        }
    }
    
    /// Composes this Operation Group with the supplied nextOperation and returns new Operation that runs the Operation Group, passes its resulting output to the nextOperation, and executes the nextOperation, finally returning its result.
    /// - parameter nextOperation: The Operation that should be composed with this Operation Group and run using the tuple output from this Group as its input
    ///
    /// - returns: A new Operation that has a Void Input type (because Operation Groups are pre-populated with their Input), and returns the output of the nextOperation parameter
    func then<NextOutput>(_ nextOperation:Operation<(OutputOne, OutputTwo, OutputThree, OutputFour, OutputFive), NextOutput>) -> Operation<Void, NextOutput> {
        return Operation.async {
            _, completion in
            self.start {
                do {
                    nextOperation.start(withInput: (try $0(), try $1(), try $2(), try $3(), try $4())) {
                        result in
                        do {
                            completion(try result(), nil)
                        } catch {
                            completion(nil, error)
                        }
                    }
                } catch {
                    completion(nil, error)
                }
            }
        }
    }
    
    /// Creates a new Operation Group that has the same Output types as the current Operation Group and the alternateGroup parameter.  The new Operation Group will first execute all of its own Operations, and if they all succeed it will return a tuple of their Outputs as a result. However if it fails, instead of throwing an error it will then execute the alternateGroup, return that result if successful, or otherwise throw the error that caused it to fail. Any number of Operation Groups with the same number and types of Outputs can be combined as alternates using this method.
    ///
    /// - parameter alternateGroup: An Operation Group that has the same number and types of Output should run if the current Operation Group fails.
    ///
    /// - returns: A new Operation Group with Void Input Types but the same number and types of Output as the current Operation Group and the alternateGroup parameter
    func or<OtherInputOne, OtherInputTwo, OtherInputThree, OtherInputFour, OtherInputFive>(_ alternateGroup:OperationGroupOfFive<OtherInputOne, OutputOne, OtherInputTwo, OutputTwo, OtherInputThree, OutputThree, OtherInputFour, OutputFour, OtherInputFive, OutputFive>) ->OperationGroupOfFive<Void, OutputOne, Void, OutputTwo, Void, OutputThree, Void, OutputFour, Void, OutputFive> {
        let compoundOperation = Operation <Void, (OutputOne, OutputTwo, OutputThree, OutputFour, OutputFive)>.async {
            _, completion in
            self.start {
                result in
                do {
                    completion((try result.0(), try result.1(), try result.2(), try result.3(), try result.4()), nil)
                } catch {
                    alternateGroup.start {
                        alternateResult in
                        do {
                            completion((try alternateResult.0(), try alternateResult.1(), try alternateResult.2(), try alternateResult.3(), try alternateResult.4()), nil)
                        } catch {
                            completion(nil, error)
                        }
                    }
                }
            }
        }
        return OperationGroupOfFive<Void, OutputOne, Void, OutputTwo, Void, OutputThree, Void, OutputFour, Void, OutputFive>(operation: compoundOperation)
    }
}
