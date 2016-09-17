//
//  PostViewModel.swift
//  SwiftOpsExample
//
//  Created by Daniel Hall on 9/16/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import Foundation


struct PostViewModel {
    let title:String
    let body:String
    let username:String
    
    init?(title:String, body:String, username:String?) {
        guard let username = username else {
            return nil
        }
        self.title = title
        self.body = body
        self.username = username
    }
}

extension PostViewModel {
    struct PostViewModelOperations {
        
        private static var postViewModelsCache:[PostViewModel]?
        
        private static var postViewModelsFromCache = Operation<Void, [PostViewModel]>.sync {
            if let postViewModels = postViewModelsCache, postViewModels.count > 0 {
                return postViewModels
            }
            throw SimpleError(message:"No cached PostViewModels")
        }
        
        private static var cachePostViewModels = Operation<[PostViewModel], [PostViewModel]>.sync {
            postViewModelsCache = $0
            return $0
        }

        
        static var postViewModelsFromPostsAndUsers = Operation<([Post], [User?]), [PostViewModel]>.sync {
            zip($0.0, $0.1).flatMap { PostViewModel(title:$0.0.title, body:$0.0.body, username:$0.1?.username) } //Excludes posts with no matching user
        }
        
        static var fetchPostViewModels:Operation<Void, [PostViewModel]> = {
            let mapUserIDs:Operation<[Post], [UInt]> = mapProperty(closure: { $0.userID }) // Create an array of user IDs from an array of Posts
            let usersFromID:Operation<([UInt], [User]), [User?]> = mapToInstancesWithMatchingProperty { uint in return { return $0.userID == uint ? $0 : nil } } // Create an array of Users that have a userID which matches the source array of UInts
            
            let getPostUserIDs = Post.operations.fetchAllPosts.then(mapUserIDs) // An operation that maps all posts to just an array of the user IDs that posted them
            let usersMatchingPosts = getPostUserIDs.and(User.operations.fetchAllUsers) // Combine both operations into a single group of two which will run in parallel
                .then(usersFromID) // When the result of both parallel options come back as a tuple ([UInt], [User]), combine them into a single array of users where each user has a userID matching the UInt value from the first array (or is nil if no match)
            
            // First try to retrieve PostViewModels from cache, if that fails, create them from Posts and Users. When we have a successful result from either source, save them to cache.
            return postViewModelsFromCache.or(Post.operations.fetchAllPosts.and(usersMatchingPosts).then(PostViewModel.operations.postViewModelsFromPostsAndUsers)).then(cachePostViewModels)
        }()
    }
    
    static var operations:PostViewModelOperations.Type { return PostViewModelOperations.self }
}
