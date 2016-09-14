//
//  ViewController.swift
//  SwiftOpsExample
//
//  Created by Daniel Hall on 9/13/16.
//  Copyright © 2016 Daniel Hall. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        Comment.operations.fetchAllComments.start {
            print(try? $0())
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

