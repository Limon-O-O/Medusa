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
        case began
        case press
        case end
    }

    var toucheActions: ((_ status: TouchStatus) -> Void)?

    fileprivate var touchStatus: TouchStatus = .end {
        willSet {
            guard touchStatus != newValue else { return }
            toucheActions?(newValue)
        }
    }

    fileprivate let innerRing = UIView()

    fileprivate var previousTimestamp: TimeInterval = 0.0

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

    fileprivate func addViews() {

        backgroundColor = UIColor.clear

        let circlePath = UIBezierPath(ovalIn: CGRect(origin: CGPoint.zero, size: frame.size))
        let outerRing = CAShapeLayer()
        outerRing.path = circlePath.cgPath
        outerRing.fillColor = UIColor.clear.cgColor
        outerRing.strokeColor = UIColor.white.cgColor
        outerRing.lineWidth = 4.0

        let ringSpace: CGFloat = 12.0
        let innerRingWH: CGFloat = frame.width - ringSpace

        innerRing.isUserInteractionEnabled = false
        innerRing.frame.size = CGSize(width: innerRingWH, height: innerRingWH)
        innerRing.center = CGPoint(x: frame.width/2, y: frame.width/2)

        innerRing.backgroundColor = UIColor.red
        innerRing.layer.masksToBounds = true
        innerRing.layer.cornerRadius = innerRingWH / 2.0

        layer.addSublayer(outerRing)
        addSubview(innerRing)
    }

}


// MARK: - Add Targets

extension RingControl {

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)

        guard let touch = touches.first else { return }

        touchStatus = .began
        previousTimestamp = touch.timestamp
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)

        guard let touch = touches.first else { return }

        let currentTimestamp = touch.timestamp

        let validFrame = CGRect(x: -frame.size.width/2, y: -frame.size.height/2, width: frame.size.width*2, height: frame.size.width*2)

        let location = touch.location(in: self)

        if validFrame.contains(location) {

            if currentTimestamp - previousTimestamp > 0.14 {
                touchStatus = .press
            }

        } else {
            touchStatus = .end
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        touchStatus = .end
    }

    override func touchesCancelled(_ touches: Set<UITouch>?, with event: UIEvent?) {
        super.touchesCancelled(touches!, with: event)
        touchStatus = .end
    }
}

extension RingControl {

    @nonobjc static let eye_scaleToSmall = "scaleToSmall"
    @nonobjc static let eye_scaleAnimationWithSpring = "scaleAnimationWithSpring"
    @nonobjc static let eye_scaleToDefault = "scaleToDefault"

    func removeAnimatedTarget() {
        removeTarget(self, action: Selector(RingControl.eye_scaleToSmall), for: .touchDown)
        removeTarget(self, action: Selector(RingControl.eye_scaleAnimationWithSpring), for: .touchUpInside)
        removeTarget(self, action: Selector(RingControl.eye_scaleToDefault), for: .touchDragExit)
    }

    func addTargetForAnimation() {
        addTarget(self, action: Selector(RingControl.eye_scaleToSmall), for: .touchDown)
        addTarget(self, action: Selector(RingControl.eye_scaleAnimationWithSpring), for: .touchUpInside)
        addTarget(self, action: Selector(RingControl.eye_scaleToDefault), for: .touchDragExit)
    }

    @objc fileprivate func scaleToSmall() {

        UIView.animate(withDuration: 0.2, animations: {
            self.innerRing.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        }) 
    }

    @objc fileprivate func scaleAnimationWithSpring() {
        UIView.animate(withDuration: 0.26, delay: 0.0, usingSpringWithDamping: 0.5, initialSpringVelocity: 10, options: UIViewAnimationOptions(), animations: {
            self.innerRing.transform = CGAffineTransform.identity
        }, completion: nil)
    }

    @objc fileprivate func scaleToDefault() {
        UIView.animate(withDuration: 0.2, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: UIViewAnimationOptions(), animations: {
            self.innerRing.transform = CGAffineTransform.identity
        }, completion: nil)
    }
}
