//
//  UserPostCell.swift
//  SwiftOpsExample
//
//  Created by Hall, Daniel on 9/15/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import Foundation
import UIKit

class UserPostTableViewCell : UITableViewCell {
    @IBOutlet var usernameLabel:UILabel!
    @IBOutlet var userImageView:UIImageView!
    @IBOutlet var titleLabel:UILabel!
    @IBOutlet var bodyLabel:UILabel!
    
    var imageOperation:CancelableOperation?
    
    override func prepareForReuse() {
        userImageView.image = nil
    }
}
