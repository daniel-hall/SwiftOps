//
//  OperationTestingExtension.swift
//  SwiftOpsExample
//
//  Created by Daniel Hall on 9/16/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import Foundation
@testable import SwiftOpsExample

extension OperationProtocol {
    func value(forInput:InputType) -> OutputType? {
        if let me = self as? SwiftOpsExample.Operation<InputType, OutputType> {
            var value:OutputType?
            let wait = DispatchSemaphore(value: 0)
            me.start(withInput: forInput) {
                value = try? $0()
                wait.signal()
            }
            _ = wait.wait(timeout: DispatchTime.distantFuture)
            return value
        }
        return nil
    }
}

extension OperationProtocol where InputType == Void {
    func value() -> OutputType? {
        return value(forInput: ())
    }
}


