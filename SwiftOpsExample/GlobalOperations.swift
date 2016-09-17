//
//  GlobalOperations.swift
//  SwiftOpsExample
//
//  Created by Daniel Hall on 9/16/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import Foundation

struct SimpleError : Error, CustomStringConvertible {
    let message:String
    
    var description: String {
        return "Error: \(message)"
    }
}

/// Creates an array of values by retrieving from a specified property from each instance in a a type in a source array
func mapProperty<InstanceType, PropertyType>(closure:@escaping (InstanceType)->PropertyType)-> Operation<[InstanceType], [PropertyType]> {
    return Operation.sync {
        $0.map(closure)
    }
}

// Takes two array, each with a different type, returns an array of the second type consisting of instances that have a property that matches a specified property on the source array
func mapToInstancesWithMatchingProperty<SourceInstanceType, DestinationInstanceType>(closure:@escaping (SourceInstanceType)->((DestinationInstanceType) -> DestinationInstanceType?))-> Operation<([SourceInstanceType], [DestinationInstanceType]), [DestinationInstanceType?]> {
    return Operation.sync {
        (source, destination) in
        source.map { destination.flatMap(closure($0)).first }
    }
}
