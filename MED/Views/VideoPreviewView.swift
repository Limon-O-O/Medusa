//
//  VideoPreviewView.swift
//  VideoRecorderExample
//
//  Created by Limon on 6/15/16.
//  Copyright © 2016 VideoRecorder. All rights reserved.
//

import UIKit
import Medusa
import AVFoundation
import Picasso

class VideoPreviewView: Canvas {

    var cameraDevice: AVCaptureDevice?

    private let focusView = FocusOverlay(frame: CGRect(x: 0, y: 0, width: 80, height: 80))

    override init(frame: CGRect) {

        super.init(frame: frame)

        configure()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configure()
    }

    private func configure() {

        if let gestureRecognizers = gestureRecognizers {
            gestureRecognizers.forEach({ removeGestureRecognizer($0) })
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(focus(_:)))
        tapGesture.numberOfTapsRequired = 1
        addGestureRecognizer(tapGesture)
        userInteractionEnabled = true

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(changeVideoZoomFactor(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        tapGesture.requireGestureRecognizerToFail(doubleTap)

        addSubview(focusView)
        focusView.hidden = true
    }

    @objc private func changeVideoZoomFactor(gesture: UITapGestureRecognizer) {

        guard let device = cameraDevice else { return }

        do {
            try device.lockForConfiguration()
        } catch {
            return
        }

        if device.videoZoomFactor == 1.0 {
            device.rampToVideoZoomFactor(1.8, withRate: 10.0)
        } else {
            device.rampToVideoZoomFactor(1.0, withRate: 10.0)
        }

        device.unlockForConfiguration()
    }

    @objc private func focus(gesture: UITapGestureRecognizer) {

        let point = gesture.locationInView(self)
        let focusPoint = CGPointMake(point.y / bounds.size.height, 1 - point.x / bounds.size.width);

        guard focusCamera(to: focusPoint) else { return }

        focusView.hidden = false
        focusView.center = point
        focusView.alpha = 0
        focusView.transform = CGAffineTransformMakeScale(1.2, 1.2)

        bringSubviewToFront(focusView)

        UIView.animateKeyframesWithDuration(0.8, delay: 0, options: UIViewKeyframeAnimationOptions(), animations: {

            UIView.addKeyframeWithRelativeStartTime(0, relativeDuration: 0.15, animations: { () -> Void in
                self.focusView.alpha = 1
                self.focusView.transform = CGAffineTransformIdentity
            })

            UIView.addKeyframeWithRelativeStartTime(0.80, relativeDuration: 0.20, animations: { () -> Void in
                self.focusView.alpha = 0
                self.focusView.transform = CGAffineTransformMakeScale(0.8, 0.8)
            })

        }, completion: { _ in
            self.focusView.hidden = true
        })
    }

    private func focusCamera(to point: CGPoint) -> Bool {

        guard let device = cameraDevice else { return false }

        do {
            try device.lockForConfiguration()
        } catch {
            return false
        }

        if device.isFocusModeSupported(.ContinuousAutoFocus) {
            device.focusMode = .ContinuousAutoFocus
        }

        if device.focusPointOfInterestSupported {
            device.focusPointOfInterest = point
        }

        if device.isExposureModeSupported(.ContinuousAutoExposure) {
            device.exposureMode = .ContinuousAutoExposure
        }
        
        if device.exposurePointOfInterestSupported {
            device.exposurePointOfInterest = point
        }
        
        device.unlockForConfiguration()
        
        return true
    }
}

