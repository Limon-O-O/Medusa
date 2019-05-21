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

    private let focusView = FocusOverlay(frame: CGRect(x: 0.0, y: 0.0, width: 80.0, height: 80.0))

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
        isUserInteractionEnabled = true

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(changeVideoZoomFactor(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        tapGesture.require(toFail: doubleTap)

        addSubview(focusView)
        focusView.isHidden = true
    }

    @objc private func changeVideoZoomFactor(_ gesture: UITapGestureRecognizer) {

        guard let device = cameraDevice else { return }

        do {
            try device.lockForConfiguration()
        } catch {
            return
        }

        if device.videoZoomFactor == 1.0 {
            device.ramp(toVideoZoomFactor: 1.8, withRate: 10.0)
        } else {
            device.ramp(toVideoZoomFactor: 1.0, withRate: 10.0)
        }

        device.unlockForConfiguration()
    }

    @objc private func focus(_ gesture: UITapGestureRecognizer) {

        let point = gesture.location(in: self)
        let focusPoint = CGPoint(x: point.y / bounds.size.height, y: 1.0 - point.x / bounds.size.width);

        guard focusCamera(to: focusPoint) else { return }

        focusView.isHidden = false
        focusView.center = point
        focusView.alpha = 0.0
        focusView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)

        bringSubviewToFront(focusView)

        UIView.animateKeyframes(withDuration: 0.8, delay: 0.0, options: UIView.KeyframeAnimationOptions(), animations: {

            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.15, animations: { () -> Void in
                self.focusView.alpha = 1.0
                self.focusView.transform = CGAffineTransform.identity
            })

            UIView.addKeyframe(withRelativeStartTime: 0.80, relativeDuration: 0.20, animations: { () -> Void in
                self.focusView.alpha = 0.0
                self.focusView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            })

        }, completion: { _ in
            self.focusView.isHidden = true
        })
    }

    private func focusCamera(to point: CGPoint) -> Bool {

        guard let device = cameraDevice else { return false }

        do {
            try device.lockForConfiguration()
        } catch {
            return false
        }

        if device.isFocusModeSupported(.continuousAutoFocus) {
            device.focusMode = .continuousAutoFocus
        }

        if device.isFocusPointOfInterestSupported {
            device.focusPointOfInterest = point
        }

        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        
        if device.isExposurePointOfInterestSupported {
            device.exposurePointOfInterest = point
        }
        
        device.unlockForConfiguration()
        
        return true
    }
}

