//
//  Utilities.swift
//  MED
//
//  Created by Limon on 6/16/16.
//  Copyright © 2016 MED. All rights reserved.
//

import AVFoundation

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


extension NSFileManager {

    class func med_moveItem(atURL sourceURL: NSURL, toURL dstURL: NSURL) {

        NSFileManager.med_removeExistingFile(byURL: dstURL)

        let fileManager = NSFileManager.defaultManager()

        if let dstPath = sourceURL.path where fileManager.fileExistsAtPath(dstPath) {
            do {
                try fileManager.moveItemAtURL(sourceURL, toURL: dstURL)
            } catch let error as NSError {
                print("[Medusa] \((#file as NSString).lastPathComponent)[\(#line)], \(#function): \(error.localizedDescription)")
            }
        }
    }

    class func med_removeExistingFile(byURL URL: NSURL) {
        let fileManager = NSFileManager.defaultManager()
        if let outputPath = URL.path where fileManager.fileExistsAtPath(outputPath) {
            do {
                try fileManager.removeItemAtURL(URL)
            } catch let error as NSError {
                print("[Medusa] \((#file as NSString).lastPathComponent)[\(#line)], \(#function): \(error.localizedDescription)")
            }
        }
    }

}