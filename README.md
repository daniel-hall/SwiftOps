# SwiftOps
A dead-simple microframework for turning your functions into chainable, groupable, branching operations

## Installation
SwiftOps will support Swift Package Manager in the near future.  Until then, you can install the framework simply by downloading the single `SwiftOps.swift` files and adding it to your project.

## Usage

### Creating Operations

An Operation is a wrapper around a function that contains information about how the function should be executed (asynchronously, on the main thread, etc.), methods to chain functions together (when they are also wrapped in Operations), and a mechanism to cancel the function or chain of functions even after they have started execution.

Operation is defined as a generic struct type with two generic parameters: an InputType and an OutputType, i.e. Operation\<InputType, OutputType\>. So, an operation that wraps a function with the signature `(String)->Date` would have the type `Operation<String, Date>`.  

To create an Operation, call the static construction method that matches how the Operation should be dispatched / executed.

- `Operation.sync(function: (InputType) throws -> OutputType)`: The **sync** construction method will create an Operation that runs synchronously (returns in the same frame it was called) on whatever the current thread is that the Operation is started on. (Completion closures are always called back on the main thread)

- `Operation.async(function: (InputType, (OutputType?, Error?) -> ()) -> ())`: The **async** construction method will create an Operation that runs asynchronously (calls back with a result at some point in the future after it is called). It is guaranteed to not run on the main thread, and will run either on the thread is is started from (if already a background thread), or a new background thread if it is started from the main thread. This type of operation takes a function which accepts two parameters: first, an input value and second, a completion closure which expects an optional output value or an optional error. The function would do its asynchronous work, and then call the completion parameter with either the result or any error that was encountered.

- `Operation.ui(function: (InputType) throws -> OutputType)`: The **ui** construction method will create an Operation that is guaranteed to be dispatched to and execute on the main thread, even if chained together with other Operations that are running in the background.

#### Example

The following code creates a synchronous operation that converts a string into a date:

	let dateFromStringOperation = Operation<String, Date>.sync {
	   let dateFormatter = DateFormatter()
		   dateFormatter.dateFormat = "MM/DD/yyyy"
	
	   if let date = dateFormatter.date(from: string) {
	       return date
	   } else {
	       throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Date could not be parsed from string"])
	   }
	}


### Combining Operations

Operations can be combined in several useful ways to create complex and sophisticated logic from small, modular, testable pieces.

- `operation.then(nextOperation)`: the **then** method will combine the operation on the left with the supplied operation parameter so that: 1) first the operation on the left is executed with the input it receives 2a) if the execution is successful, the result is passed on as the input to the supplied operation parameter, which is then executed. 2b) if the left operation results in an error, the second operation is skipped and the error is passed through.  
	  
	Note that this requires that the second operation have as its `InputType` the `OutputType` from the first operation.


- `operation.or(alternateOperation)`: the **or** method will combine the operation on the left with the supplied operation parameter so that: 1) first the operation on the left is executed with the input it receives 2a) if the execution results in an error, instead of passing the error on, the supplied “alternateOperation” parameter will be called with the same input that was received by the first operation.  If the second operation succeeds, the result will be passed on  2b) if the execution of the first operation succeeds, the alternate operation provided as a parameter is skipped and the result is just passed through.  
	  
	Note that this requires that the second operation have the same `InputType` and `OutputType` as the first operation.


- `operation.and(additionalOperation)`: the **and** method will combine the operation on the left with the supplied operation parameter so that: 1) both operations are executed in parallel on separate threads using the same input 2a) if and when both operations complete successfully, their results will be combined into a tuple output and passed on 2b) if either or both operations fail, then the error will be passed on instead of a result.

	  
	Note that this requires that the second operation have the same `InputType` as the first operation, since they will both be started on their separate threads using the same input value. 



