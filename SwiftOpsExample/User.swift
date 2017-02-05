//
//  User.swift
//  SwiftOpsExample
//
//  Created by Daniel Hall on 9/16/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import Foundation
import UIKit

struct User {
    let userID:UInt
    let name:String
    let username:String
    let email:String
    
    static func fromDictionary(_ dictionary:[String:AnyObject]) throws -> User {
        if let userID = dictionary["id"] as? NSNumber, let name = dictionary["name"] as? String, let username = dictionary["username"] as? String, let email = dictionary["email"] as? String {
            return User(userID: userID.uintValue, name: name, username: username, email: email)
        }
        throw SimpleError(message:"User.fromDictionary received an invalid dictionary to parse")
    }
}


extension User {
    struct Operations {
        
        private static var usersCache:[User]?
        
        private static var usersFromCache = Operation<Void, [User]>.sync {
            if let users = usersCache, users.count > 0 {
                return users
            }
            throw SimpleError(message:"No cached Users")
        }
        
        private static var cacheUsers = Operation<[User], [User]>.sync {
            usersCache = $0
            return $0
        }
        
        private static var usersFromJSON = Operation<JSON, [User]>.sync {
            do {
                switch $0 {
                case .Array(let contents) :
                    return try contents.map { try User.fromDictionary($0) }
                case .Dictionary(let contents) :
                    return try [User.fromDictionary(contents)]                }
            } catch {
                throw(error)
            }
        }
        
        // First try to get users from cache, if that fails retrieve them from server. Cache any successful results right before returning them.
        static var fetchAllUsers =
            usersFromCache.or(
                URLRequest.Operations.urlRequestFromString
                    .using(input: "http://jsonplaceholder.typicode.com/users/")
                    .then(Data.Operations.dataFromURLRequest)
                    .then(JSON.Operations.jsonFromData)
                    .then(User.Operations.usersFromJSON)
            ).then(cacheUsers)
        
        static var userPortraitURLFromNameString = Operation<String, String>.sync {
            "https://robohash.org/" + $0.replacingOccurrences(of:" ", with:"")
        }
        
        static var userPortraitImageFromNameString:Operation<String, UIImage> = {
            let getURLRequestFromUser = userPortraitURLFromNameString.then(URLRequest.Operations.urlRequestFromString)
            let getImageFromCacheOrEndpoint = UIImage.Operations.cachedImageFromURLRequest.or(Data.Operations.dataFromURLRequest.then(UIImage.Operations.imageFromData))
            let imageAndURLRequestTuple = getURLRequestFromUser.then(getImageFromCacheOrEndpoint).and(getURLRequestFromUser) // Creates an operation that gets the image, and combines that result with the result of getting the URLRequest for this particular user's portrait image into a tuple, i.e. (Image, URLRequest).  This is because the next operation in the chain takes a (Image, URLRequest) tuple and caches the image in the first position of the tuple using the URL string from the URLRequest in the second position of the tuple as a key
            return imageAndURLRequestTuple.then(UIImage.Operations.cacheImageForURLRequest) // This returns a result and also caches it on the way out
        }()
    }
}
