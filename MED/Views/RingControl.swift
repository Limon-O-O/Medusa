//
//  RingControl.swift
//  VideoRecorderExample
//
//  Created by Limon on 6/15/16.
//  Copyright © 2016 VideoRecorder. All rights reserved.
//

import UIKit

@IBDesignable
class RingControl: UIControl {

    enum TouchStatus {
        case Began
        case Press
        case End
    }

    var toucheActions: ((status: TouchStatus) -> Void)?

    private let innerRing = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addViews()

        addTargetForAnimation()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        addViews()

        addTargetForAnimation()
    }

    private func addViews() {

        backgroundColor = UIColor.clearColor()

        let circlePath = UIBezierPath(ovalInRect: CGRect(origin: CGPointZero, size: frame.size))
        let outerRing = CAShapeLayer()
        outerRing.path = circlePath.CGPath
        outerRing.fillColor = UIColor.clearColor().CGColor
        outerRing.strokeColor = UIColor.whiteColor().CGColor
        outerRing.lineWidth = 4.0

        let ringSpace: CGFloat = 12.0
        let innerRingWH: CGFloat = frame.width - ringSpace

        innerRing.userInteractionEnabled = false
        innerRing.frame.size = CGSize(width: innerRingWH, height: innerRingWH)
        innerRing.center = CGPoint(x: frame.width/2, y: frame.width/2)

        innerRing.backgroundColor = UIColor.redColor()
        innerRing.layer.masksToBounds = true
        innerRing.layer.cornerRadius = innerRingWH / 2.0

        layer.addSublayer(outerRing)
        addSubview(innerRing)
    }

}


// MARK: Add Targets

extension RingControl {

    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        super.touchesBegan(touches, withEvent: event)
        toucheActions?(status: .Began)
    }

    override func touchesMoved(touches: Set<UITouch>, withEvent event: UIEvent?) {
        super.touchesMoved(touches, withEvent: event)

        let validFrame = CGRect(x: -frame.size.width/2, y: -frame.size.height/2, width: frame.size.width*2, height: frame.size.width*2)

        if let location = touches.first?.locationInView(self) where CGRectContainsPoint(validFrame, location) {

            toucheActions?(status: .Press)

        } else {

            toucheActions?(status: .End)
        }
    }

    override func touchesEnded(touches: Set<UITouch>, withEvent event: UIEvent?) {
        super.touchesEnded(touches, withEvent: event)

        toucheActions?(status: .End)
    }
}

extension RingControl {

    @nonobjc static let eye_scaleToSmall = "scaleToSmall"
    @nonobjc static let eye_scaleAnimationWithSpring = "scaleAnimationWithSpring"
    @nonobjc static let eye_scaleToDefault = "scaleToDefault"

    func removeAnimatedTarget() {
        removeTarget(self, action: Selector(RingControl.eye_scaleToSmall), forControlEvents: .TouchDown)
        removeTarget(self, action: Selector(RingControl.eye_scaleAnimationWithSpring), forControlEvents: .TouchUpInside)
        removeTarget(self, action: Selector(RingControl.eye_scaleToDefault), forControlEvents: .TouchDragExit)
    }

    func addTargetForAnimation() {
        addTarget(self, action: Selector(RingControl.eye_scaleToSmall), forControlEvents: .TouchDown)
        addTarget(self, action: Selector(RingControl.eye_scaleAnimationWithSpring), forControlEvents: .TouchUpInside)
        addTarget(self, action: Selector(RingControl.eye_scaleToDefault), forControlEvents: .TouchDragExit)
    }

    @objc private func scaleToSmall() {

        UIView.animateWithDuration(0.2) {
            self.innerRing.transform = CGAffineTransformMakeScale(0.8, 0.8)
        }
    }

    @objc private func scaleAnimationWithSpring() {
        UIView.animateWithDuration(0.26, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 10, options: .CurveEaseInOut, animations: {
            self.innerRing.transform = CGAffineTransformIdentity
        }, completion: nil)
    }

    @objc private func scaleToDefault() {
        UIView.animateWithDuration(0.2, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: .CurveEaseInOut, animations: {
            self.innerRing.transform = CGAffineTransformIdentity
        }, completion: nil)
    }
}