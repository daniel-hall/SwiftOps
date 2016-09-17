//
//  SampleOperations.swift
//  SwiftOpsExample
//
//  Created by Daniel Hall on 9/13/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import Foundation
import UIKit

extension URLRequest {
    struct URLRequestOperations {
    static var urlRequestFromString = Operation<String, URLRequest>.sync {
            if let url = URL(string: $0) {
                return URLRequest(url: url)
            } else {
                throw SimpleError(message:"urlRequestFromString Operation received invalid String as input")
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


extension UIImage {
    struct UIImageOperations {
        
        private static var imageCache = NSCache<NSString, UIImage>()
        
        static var imageFromData = Operation<Data, UIImage>.ui {
            if let image = UIImage(data: $0) {
                return image
            }
            throw SimpleError(message: "UIImageOperations.imageFromData operation could not create image from the supplied Data")
        }
        
        static var cachedImageFromString = Operation<String, UIImage>.sync {
            guard let image = imageCache.object(forKey:$0 as NSString) else {
                throw SimpleError(message:"Image not found in cache for key \($0)")
            }
            return image
        }
        
        static var cachedImageFromURLRequest = Operation<URLRequest, String>.sync {
            guard let url = $0.url else {
                throw SimpleError(message:"URLRequest did not include valid URL")
            }
            return url.absoluteString
            }.then(cachedImageFromString)
        
        static var cacheImageUsingString = Operation<(UIImage, String), UIImage>.sync {
            imageCache.setObject($0.0, forKey:$0.1 as NSString)
            return $0.0
        }
        
        static var cacheImageForURLRequest = Operation<(UIImage, URLRequest), (UIImage, String)>.sync {
            guard let url = $0.1.url else {
                throw SimpleError(message:"URLRequest did not include valid URL")
            }
            return ($0.0, url.absoluteString)
        }.then(cacheImageUsingString)
    }
    
    static var operations:UIImageOperations.Type { return UIImageOperations.self }
}


enum JSON {
    case Array(contents:[[String:AnyObject]])
    case Dictionary(contenst:[String:AnyObject])
}

extension JSON {
    
    //Define some Operations for this type
    struct JSONOperations {
        static var jsonFromData = Operation<Data, JSON>.sync {
            let result = try JSONSerialization.jsonObject(with: $0, options: [])
            if let result = result as? [[String:AnyObject]] {
                return JSON.Array(contents: result)
            } else if let result = result as? [String:AnyObject] {
                return JSON.Dictionary(contenst: result)
            } else {
                throw SimpleError(message:"jsonFromData Operation received invalid Data as input")
            }
        }
    }
    
    //Add a new static var on the type as a shortcut to the Operations
    static var operations:JSONOperations.Type { return JSONOperations.self }
}





