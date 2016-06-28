//
//  CaptureSessionCoordinator.swift
//  Medusa
//
//  Created by Limon on 2016/6/13.
//  Copyright © 2016年 Medusa. All rights reserved.
//

import AVFoundation


public enum MedusaError: ErrorType {
    case CaptureDeviceError
    case AudioDeviceError
}


public protocol CaptureSessionCoordinatorDelegate: class {

    func coordinatorWillBeginRecording(coordinator: CaptureSessionCoordinator)

    func coordinatorDidBeginRecording(coordinator: CaptureSessionCoordinator)

    func coordinatorWillDidFinishRecording(coordinator: CaptureSessionCoordinator)

    func coordinator(coordinator: CaptureSessionCoordinator, didFinishRecordingToOutputFileURL outputFileURL: NSURL?, error: NSError?)
}

public extension CaptureSessionCoordinatorDelegate {

    public func coordinatorWillBeginRecording(coordinator: CaptureSessionCoordinator) {}

    public func coordinatorWillDidFinishRecording(coordinator: CaptureSessionCoordinator) {}
}


public class CaptureSessionCoordinator: NSObject {

    public var captureDevice: AVCaptureDevice

    public let captureSession: AVCaptureSession

    public let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue: dispatch_queue_t

    public weak var delegate: CaptureSessionCoordinatorDelegate?

    private var captureDeviceInput: AVCaptureDeviceInput

    private var audioDeviceInput: AVCaptureDeviceInput


    public init(sessionPreset: String, position: AVCaptureDevicePosition = .Back) throws {

        captureDeviceInput = try AVCaptureDeviceInput.med_captureDeviceInput(byPosition: position)

        audioDeviceInput = try AVCaptureDeviceInput.med_audioDeviceInput()

        let captureSession: AVCaptureSession = {
            $0.sessionPreset = sessionPreset
            return $0
        }(AVCaptureSession())

        self.captureSession  = captureSession
        self.captureDevice   = captureDeviceInput.device
        self.sessionQueue    = dispatch_queue_create("top.limon.capturepipeline.session", DISPATCH_QUEUE_SERIAL)
        self.previewLayer    = AVCaptureVideoPreviewLayer(session: captureSession)

        super.init()

        try addInput(captureDeviceInput, toCaptureSession: captureSession)
        try addInput(audioDeviceInput, toCaptureSession: captureSession)
    }
}


// MARK: Public Methods

extension CaptureSessionCoordinator {

    public func startRunning() {
        dispatch_sync(sessionQueue) {
            self.captureSession.startRunning()
        }
    }

    public func stopRunning() {
        dispatch_sync(sessionQueue) {
            self.captureSession.stopRunning()
        }
    }

    public func swapCaptureDevicePosition() throws {

        let newPosition = captureDevice.position == .Back ? AVCaptureDevicePosition.Front : .Back

        let newCaptureDeviceInput = try AVCaptureDeviceInput.med_captureDeviceInput(byPosition: newPosition)
        let newAudioDeviceInput = try AVCaptureDeviceInput.med_audioDeviceInput()

        captureSession.beginConfiguration()

        captureSession.removeInput(captureDeviceInput)
        captureSession.removeInput(audioDeviceInput)

        try addInput(newCaptureDeviceInput, toCaptureSession: captureSession)
        try addInput(newAudioDeviceInput, toCaptureSession: captureSession)

        captureSession.commitConfiguration()

        captureDeviceInput = newCaptureDeviceInput
        audioDeviceInput = newAudioDeviceInput
        captureDevice = captureDeviceInput.device
    }

    public func addOutput(output: AVCaptureOutput, toCaptureSession captureSession: AVCaptureSession) throws {
        guard captureSession.canAddOutput(output) else { throw MedusaError.CaptureDeviceError }
        captureSession.addOutput(output)
    }

    public func addInput(input: AVCaptureDeviceInput, toCaptureSession captureSession: AVCaptureSession) throws {
        guard captureSession.canAddInput(input) else { throw MedusaError.CaptureDeviceError }
        captureSession.addInput(input)
    }
}



