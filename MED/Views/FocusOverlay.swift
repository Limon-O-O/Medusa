//
//  FocusOverlay.swift
//  VideoRecorderExample
//
//  Created by Limon on 6/15/16.
//  Copyright © 2016 VideoRecorder. All rights reserved.
//

import UIKit

class FocusOverlay: UIView {

    var topLeftCornerLines = [UIView]()
    var topRightCornerLines = [UIView]()
    var bottomLeftCornerLines = [UIView]()
    var bottomRightCornerLines = [UIView]()

    let cornerDepth: CGFloat = 3
    let cornerWidth: CGFloat = 20
    let lineWidth: CGFloat = 1

    init() {
        super.init(frame: CGRect.zero)
        createLines()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        createLines()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        createLines()
    }

    override func layoutSubviews() {

        let corners = [topLeftCornerLines, topRightCornerLines, bottomLeftCornerLines, bottomRightCornerLines]
        for i in 0..<corners.count {
            let corner = corners[i]
            var horizontalFrame: CGRect
            var verticalFrame: CGRect

            switch (i) {
            case 0:
                verticalFrame = CGRect(x: -cornerDepth, y:  -cornerDepth, width:  cornerDepth, height:  cornerWidth)
                horizontalFrame = CGRect(x: -cornerDepth, y:  -cornerDepth, width:  cornerWidth, height:  cornerDepth)
                break
            case 1:
                verticalFrame = CGRect(x: bounds.width, y:  -cornerDepth, width:  cornerDepth, height:  cornerWidth)
                horizontalFrame = CGRect(x: bounds.width + cornerDepth - cornerWidth, y:  -cornerDepth, width:  cornerWidth, height:  cornerDepth)
                break
            case 2:
                verticalFrame = CGRect(x: -cornerDepth, y:  bounds.height + cornerDepth - cornerWidth, width:  cornerDepth, height:  cornerWidth)
                horizontalFrame = CGRect(x: -cornerDepth, y:  bounds.height, width:  cornerWidth, height:  cornerDepth)
                break
            case 3:
                verticalFrame = CGRect(x: bounds.width, y:  bounds.height + cornerDepth - cornerWidth, width:  cornerDepth, height:  cornerWidth)
                horizontalFrame = CGRect(x: bounds.width + cornerDepth - cornerWidth, y:  bounds.height, width:  cornerWidth, height:  cornerDepth)
                break
            default:
                verticalFrame = CGRect.zero
                horizontalFrame = CGRect.zero
                break
            }

            corner[0].frame = verticalFrame
            corner[1].frame = horizontalFrame
        }
    }

    func createLines() {

        topLeftCornerLines = [createLine(), createLine()]
        topRightCornerLines = [createLine(), createLine()]
        bottomLeftCornerLines = [createLine(), createLine()]
        bottomRightCornerLines = [createLine(), createLine()]

        isUserInteractionEnabled = false
    }

    func createLine() -> UIView {
        let line = UIView()
        line.backgroundColor = UIColor.white
        addSubview(line)
        return line
    }
}


