//
//  Post.swift
//  SwiftOpsExample
//
//  Created by Daniel Hall on 9/16/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import Foundation

struct Post {
    let postID:UInt
    let userID:UInt
    let title:String
    let body:String
    
    static func fromDictionary(_ dictionary:[String:AnyObject]) throws -> Post {
        if let postID = dictionary["id"] as? NSNumber, let userID = dictionary["userId"] as? NSNumber, let title = dictionary["title"] as? String, let body = dictionary["body"] as? String {
            return Post(postID:postID.uintValue, userID:userID.uintValue, title:title.uppercased(), body:body)
        }
        throw SimpleError(message:"Post.fromDictionary received an invalid dictionary to parse")
    }
}

extension Post {
    struct PostOperations {
        
        static private var postsCache:[Post]?
        
        static var postsFromJSON = Operation<JSON, [Post]>.sync {
            do {
                switch $0 {
                case .Array(let contents) :
                    return try contents.map { try Post.fromDictionary($0) }
                case .Dictionary(let contents) :
                    return try [Post.fromDictionary(contents)]
                }
            } catch {
                throw(error)
            }
        }
        
        private static var postsFromCache = Operation<Void, [Post]>.sync {
            if let posts = postsCache, posts.count > 0 {
                return posts
            }
            throw SimpleError(message:"No cached Posts")
        }
        
        private static var cachePosts = Operation<[Post], [Post]>.sync {
            postsCache = $0
            return $0
        }
        
        // First try to get posts from cache, if that fails retrieve them from server. Cache any successful results right before returning them.
        static var fetchAllPosts =
            postsFromCache.or(
                URLRequest.operations.urlRequestFromString
                    .using(input: "http://jsonplaceholder.typicode.com/posts/")
                    .then(Data.operations.dataFromURLRequest)
                    .then(JSON.operations.jsonFromData)
                    .then(Post.operations.postsFromJSON)
            ).then(cachePosts)
    }
    
    static var operations:PostOperations.Type { return PostOperations.self }
}
