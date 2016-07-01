//
//  Utilities.swift
//  MED
//
//  Created by Limon on 6/16/16.
//  Copyright © 2016 MED. All rights reserved.
//

import AVFoundation

// MARK: Helper

func synchronized<T>(lock: AnyObject, @noescape closure: () throws -> T) rethrows -> T {
    objc_sync_enter(lock)
    defer {
        objc_sync_exit(lock)
    }
    return try closure()
}

extension AVCaptureDeviceInput {

    class func med_captureDeviceInput(byPosition position: AVCaptureDevicePosition) throws -> AVCaptureDeviceInput {

        guard let captureDevice = position == .Back ? AVCaptureDevice.MEDCaptureDevice.Back.device : AVCaptureDevice.MEDCaptureDevice.Front.device,
            captureDeviceInput = try? AVCaptureDeviceInput(device: captureDevice) else { throw MedusaError.CaptureDeviceError }

        return captureDeviceInput
    }

    class func med_audioDeviceInput() throws -> AVCaptureDeviceInput {

        guard let audioDevice = AVCaptureDevice.devicesWithMediaType(AVMediaTypeAudio).first as? AVCaptureDevice,
            audioDeviceInput = try? AVCaptureDeviceInput(device: audioDevice) else { throw MedusaError.AudioDeviceError }

        return audioDeviceInput
    }
}

extension AVCaptureDevice {

    enum MEDCaptureDevice {

        case Back
        case Front

        var device: AVCaptureDevice? {
            switch self {
            case .Back:
                return AVCaptureDevice.med_deviceWithPosition(.Back)
            case .Front:
                return AVCaptureDevice.med_deviceWithPosition(.Front)
            }
        }
    }

    private class func med_deviceWithPosition(position: AVCaptureDevicePosition) -> AVCaptureDevice? {
        guard let devices = devicesWithMediaType(AVMediaTypeVideo) as? [AVCaptureDevice] else {
            return nil
        }
        return devices.filter { $0.position == position }.first
    }
}

extension String {
    func med_find(a: String, options: NSStringCompareOptions = .CaseInsensitiveSearch) -> Int? {
        guard let range = rangeOfString(a, options: options) else {
            return nil
        }
        return startIndex.distanceTo(range.startIndex)
    }
}
