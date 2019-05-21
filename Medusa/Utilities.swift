//
//  Utilities.swift
//  MED
//
//  Created by Limon on 6/16/16.
//  Copyright © 2016 MED. All rights reserved.
//

import AVFoundation

extension Med where Base: AVCaptureDeviceInput {

    static func captureDeviceInput(withPosition position: AVCaptureDevice.Position) throws -> AVCaptureDeviceInput {
        guard let captureDevice = position == .back ? AVCaptureDevice.med.CaptureDevice.back.value : AVCaptureDevice.med.CaptureDevice.front.value,
            let captureDeviceInput = try? AVCaptureDeviceInput(device: captureDevice) else { throw MedusaError.captureDeviceError }
        return captureDeviceInput
    }

    static func audioDeviceInput() throws -> AVCaptureDeviceInput {
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
            let audioDeviceInput = try? AVCaptureDeviceInput(device: audioDevice) else { throw MedusaError.audioDeviceError }
        return audioDeviceInput
    }
}

extension Med where Base: AVCaptureDevice {

    fileprivate enum CaptureDevice {

        case back
        case front

        var value: AVCaptureDevice? {
            switch self {
            case .back:
                return AVCaptureDevice.med.device(withPosition: .back)
            case .front:
                return AVCaptureDevice.med.device(withPosition: .front)
            }
        }
    }

    private static func device(withPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        return AVCaptureDevice.default(AVCaptureDevice.DeviceType.builtInWideAngleCamera, for: .video, position: position)
    }
}

extension Med where Base: FileManager {

    static func freeDiskSpace(min: UInt64 = 30) -> Bool {
        do {
            let attribute = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            let freesize = attribute[FileAttributeKey.systemFreeSize] as? UInt64 ?? 0
            let minSzie: UInt64 = min * 1024 * 1024
            return freesize > minSzie
        } catch {
            return false
        }
    }

    static func removeExistingFile(at URL: Foundation.URL) {
        let fileManager = FileManager.default
        let outputPath = URL.path
        if fileManager.fileExists(atPath: outputPath) {
            do {
                try fileManager.removeItem(at: URL)
            } catch {
                med_print(error.localizedDescription)
            }
        }
    }

    static func moveItem(at sourceURL: Foundation.URL, toURL dstURL: Foundation.URL) {

        removeExistingFile(at: dstURL)

        let fileManager = FileManager.default
        let dstPath = sourceURL.path
        if fileManager.fileExists(atPath: dstPath) {
            do {
                try fileManager.moveItem(at: sourceURL, to: dstURL)
            } catch {
                med_print(error.localizedDescription)
            }
        }
    }
}
