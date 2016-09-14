//
//  SampleOperations.swift
//  SwiftOpsExample
//
//  Created by Daniel Hall on 9/13/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import Foundation

enum JSON {
    case Array(contents:[[String:AnyObject]])
    case Dictionary(contenst:[String:AnyObject])
}

extension JSON {
    struct JSONOperations {
        static var jsonFromData = Operation<Data, JSON>.sync {
            let result = try JSONSerialization.jsonObject(with: $0, options: [])
            if let result = result as? [[String:AnyObject]] {
                return JSON.Array(contents: result)
            } else if let result = result as? [String:AnyObject] {
                return JSON.Dictionary(contenst: result)
            } else {
                throw NSError(domain: "SwiftOpsExample.danielhall.io", code: 0, userInfo: [NSLocalizedDescriptionKey : "jsonFromData Operation received invalid Data as input"])
            }
        }
    }
    
    static var operations:JSONOperations.Type { return JSONOperations.self }
}


extension URLRequest {
    struct URLRequestOperations {
    static var urlRequestFromString = Operation<String, URLRequest>.sync {
            if let url = URL(string: $0) {
                return URLRequest(url: url)
            } else {
                throw NSError(domain: "SwiftOpsExample.danielhall.io", code: 0, userInfo: [NSLocalizedDescriptionKey : "urlRequestFromString Operation received invalid String as input"])
            }
        }
    }
    
    static var operations:URLRequestOperations.Type { return URLRequestOperations.self }
}

extension Data {
    struct DataOperations {
        static var dataFromURLRequest = Operation<URLRequest, Data>.async {
            request, completion in
            let task = URLSession.shared.dataTask(with: request) {
                data, response, error in
                if let data = data {
                    completion(data, nil)
                } else {
                    completion(nil, error!)
                }
            }
            task.resume()
        }
    }
    
    static var operations:DataOperations.Type { return DataOperations.self }
}

struct Comment {
    let postID:UInt
    let commentID:UInt
    let name:String
    let email:String
    let body:String
    
    static func fromDictionary(_ dictionary:[String:AnyObject]) -> Comment? {
        if let postID = dictionary["postId"] as? NSNumber, let commentID = dictionary["id"] as? NSNumber, let name = dictionary["name"] as? String, let email = dictionary["email"] as? String, let body = dictionary["body"] as? String {
            return Comment(postID:postID.uintValue, commentID:commentID.uintValue, name:name, email:email, body:body)
        }
        return nil
    }
}

extension Comment {
    struct CommentOperations {
        static var commentsFromJSON = Operation<JSON, [Comment]>.sync {
            switch $0 {
            case .Array(let contents) :
                return contents.flatMap { Comment.fromDictionary($0) }
            case .Dictionary(let contents) :
                return [Comment.fromDictionary(contents)].flatMap { $0 }
            }
        }
        
        static var fetchAllComments =
            URLRequest.operations.urlRequestFromString
            .using(input: "http://jsonplaceholder.typicode.com/comments/")
            .then(Data.operations.dataFromURLRequest)
            .then(JSON.operations.jsonFromData)
            .then(Comment.operations.commentsFromJSON)
    }
    
    static var operations:CommentOperations.Type { return CommentOperations.self }
}
