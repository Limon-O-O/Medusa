//
//  ViewController.swift
//  VideoRecorderExample
//
//  Created by Limon on 2016/6/13.
//  Copyright © 2016年 VideoRecorder. All rights reserved.
//

import UIKit
import VideoRecorder

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let st: CAAnimation = {
            $0.fromValue = 0.0
            return $0
        }(CABasicAnimation(keyPath: ""))

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

