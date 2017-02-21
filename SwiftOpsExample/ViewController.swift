//
//  ViewController.swift
//  SwiftOpsExample
//
//  Created by Daniel Hall on 9/13/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import UIKit

class ViewController: UIViewController, UITableViewDataSource {

    // When outlets are hooked up, fetch the view models and reload the table when they arrive
    @IBOutlet private var tableView: UITableView! {
        didSet {
            PostViewModel.Operations.fetchPostViewModels.start {
                do {
                    self.postViewModels = try $0()
                    self.tableView.reloadData()
                } catch {
                    print(error)
                }
            }
        }
    }
    
    private var postViewModels:[PostViewModel]!
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UserPost", for: indexPath) as! UserPostTableViewCell
        cell.populateFromViewModel(viewModel: postViewModels[indexPath.row])
        return cell
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return postViewModels?.count ?? 0
    }
}


// MARK: UserPostTableViewCellExtension

// An extension method that populates this kind of cell with the view model we are using in this view controller
extension UserPostTableViewCell {
    func populateFromViewModel(viewModel:PostViewModel) {

        // In case this cell is being reused while still donwloading an image for a previous user, cancel the previous download operation
        imageOperationContext?.cancel()
                
        usernameLabel.text = viewModel.username
        titleLabel.text = viewModel.title
        bodyLabel.text = viewModel.body
        
        // Save this as a cancelable operation so if this cell is reused before the image is downloaded, we can cancel the previous download operation and just run the new one
        imageOperationContext = User.Operations.userPortraitImageFromNameString.start(withInput:viewModel.username) {
            do {
                self.userImageView.image = try $0()
            } catch {
                print(error)
            }
        }
    }
}

