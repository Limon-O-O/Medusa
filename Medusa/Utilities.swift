//
//  Utilities.swift
//  MED
//
//  Created by Limon on 6/16/16.
//  Copyright © 2016 MED. All rights reserved.
//

import AVFoundation

extension AVCaptureDeviceInput {

    class func med_captureDeviceInput(withPosition position: AVCaptureDevicePosition) throws -> AVCaptureDeviceInput {

        guard let captureDevice = position == .back ? AVCaptureDevice.MEDCaptureDevice.back.device : AVCaptureDevice.MEDCaptureDevice.front.device,
            let captureDeviceInput = try? AVCaptureDeviceInput(device: captureDevice) else { throw MedusaError.captureDeviceError }

        return captureDeviceInput
    }

    class func med_audioDeviceInput() throws -> AVCaptureDeviceInput {

        guard let audioDevice = AVCaptureDevice.devices(withMediaType: AVMediaTypeAudio).first as? AVCaptureDevice,
            let audioDeviceInput = try? AVCaptureDeviceInput(device: audioDevice) else { throw MedusaError.audioDeviceError }

        return audioDeviceInput
    }
}

extension AVCaptureDevice {

    enum MEDCaptureDevice {

        case back
        case front

        var device: AVCaptureDevice? {
            switch self {
            case .back:
                return AVCaptureDevice.med_device(withPosition: .back)
            case .front:
                return AVCaptureDevice.med_device(withPosition: .front)
            }
        }
    }

    fileprivate class func med_device(withPosition position: AVCaptureDevicePosition) -> AVCaptureDevice? {
        guard let devices = devices(withMediaType: AVMediaTypeVideo) as? [AVCaptureDevice] else {
            return nil
        }
        return devices.filter { $0.position == position }.first
    }
}

extension FileManager {

    class func med_moveItem(at sourceURL: Foundation.URL, toURL dstURL: Foundation.URL) {

        FileManager.med_removeExistingFile(at: dstURL)

        let fileManager = FileManager.default
        let dstPath = sourceURL.path
        if fileManager.fileExists(atPath: dstPath) {
            do {
                try fileManager.moveItem(at: sourceURL, to: dstURL)
            } catch let error as NSError {
                print("[Medusa] \((#file as NSString).lastPathComponent)[\(#line)], \(#function): \(error.localizedDescription)")
            }
        }
    }

    class func med_removeExistingFile(at URL: Foundation.URL) {
        let fileManager = FileManager.default
        let outputPath = URL.path
        if fileManager.fileExists(atPath: outputPath) {
            do {
                try fileManager.removeItem(at: URL)
            } catch let error as NSError {
                print("[Medusa] \((#file as NSString).lastPathComponent)[\(#line)], \(#function): \(error.localizedDescription)")
            }
        }
    }

}
