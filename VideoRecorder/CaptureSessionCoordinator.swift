//
//  CaptureSessionCoordinator.swift
//  VideoRecorderExample
//
//  Created by Limon on 2016/6/13.
//  Copyright © 2016年 VideoRecorder. All rights reserved.
//

import AVFoundation


public protocol CaptureSessionCoordinatorDelegate: class {

    func coordinatorWillBeginRecording(coordinator: CaptureSessionCoordinator)

    func coordinatorDidBeginRecording(coordinator: CaptureSessionCoordinator)

    func coordinatorWillDidFinishRecording(coordinator: CaptureSessionCoordinator)

    func coordinator(coordinator: CaptureSessionCoordinator, didFinishRecordingToOutputFileURL outputFileURL: NSURL, error: NSError?)
}

public extension CaptureSessionCoordinatorDelegate {

    public func coordinatorWillBeginRecording(coordinator: CaptureSessionCoordinator) {}

    public func coordinatorWillDidFinishRecording(coordinator: CaptureSessionCoordinator) {}
}


public enum VideoRecorderError: ErrorType {
    case CameraDeviceError
    case AudioDeviceError
}


public class CaptureSessionCoordinator: NSObject {

    public let cameraDevice: AVCaptureDevice

    public let captureSession: AVCaptureSession

    public let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue: dispatch_queue_t

    public weak var delegate: CaptureSessionCoordinatorDelegate?


    public init(sessionPreset: String) throws {

         let cameraDeviceInput: AVCaptureDeviceInput = try {

            guard let cameraDevice = AVCaptureDevice.devicesWithMediaType(AVMediaTypeVideo).first as? AVCaptureDevice, cameraDeviceInput = try? AVCaptureDeviceInput(device: cameraDevice) else { throw VideoRecorderError.CameraDeviceError }

            return cameraDeviceInput
        }()

        let audioDeviceInput: AVCaptureDeviceInput = try {

            guard let audioDevice = AVCaptureDevice.devicesWithMediaType(AVMediaTypeAudio).first as? AVCaptureDevice,
                audioDeviceInput = try? AVCaptureDeviceInput(device: audioDevice) else { throw VideoRecorderError.AudioDeviceError }

            return audioDeviceInput
        }()

        let captureSession: AVCaptureSession = {
            $0.sessionPreset = sessionPreset
            return $0
        }(AVCaptureSession())

        self.captureSession = captureSession
        self.cameraDevice   = cameraDeviceInput.device
        self.sessionQueue   = dispatch_queue_create("top.limon.capturepipeline.session", DISPATCH_QUEUE_SERIAL)
        self.previewLayer   = AVCaptureVideoPreviewLayer(session: captureSession)

        super.init()

        try addInput(cameraDeviceInput, toCaptureSession: captureSession)
        try addInput(audioDeviceInput, toCaptureSession: captureSession)
    }

}


// MARK: Public Methods

extension CaptureSessionCoordinator {

    public func startRecording() {}

    public func stopRecording() {}

    public func startRunning() {
        dispatch_sync(sessionQueue) {
            self.captureSession.startRunning()
        }
    }

    public func stopRunning() {
        dispatch_sync(sessionQueue) {
            self.stopRecording()
            self.captureSession.stopRunning()
        }
    }

    public func addOutput(output: AVCaptureOutput, toCaptureSession captureSession: AVCaptureSession) throws {
        guard captureSession.canAddOutput(output) else { throw VideoRecorderError.CameraDeviceError }
        captureSession.addOutput(output)
    }

    public func addInput(input: AVCaptureDeviceInput, toCaptureSession captureSession: AVCaptureSession) throws {
        guard captureSession.canAddInput(input) else { throw VideoRecorderError.CameraDeviceError }
        captureSession.addInput(input)
    }
}


// MARK: Helper

func synchronized<T>(lock: AnyObject, @noescape closure: () throws -> T) rethrows -> T {
    objc_sync_enter(lock)
    defer {
        objc_sync_exit(lock)
    }
    return try closure()
}


