//
//  Renderable.swift
//  Picasso
//
//  Created by Limon on 2016/8/13.
//  Copyright © 2016年 Picasso. All rights reserved.
//

import UIKit

public protocol Renderable {
    var view: UIView { get }
    var context: CIContext { get }
    func renderImage(image: CIImage)
}