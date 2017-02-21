//
//  UserTests.swift
//  SwiftOpsExample
//
//  Created by Daniel Hall on 9/16/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import XCTest
@testable import SwiftOpsExample

class UserTests: XCTestCase {
    
    func testUserPortraitURLFromName() {
        let input = "Pat Kline"
        let expected = "https://robohash.org/PatKline"
        XCTAssertEqual(User.Operations.userPortraitURLFromNameString.value(forInput:input), expected)
    }
    
    
}
