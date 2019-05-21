//
//  CaptureSessionCoordinator.swift
//  Medusa
//
//  Created by Limon on 2016/6/13.
//  Copyright © 2016年 Medusa. All rights reserved.
//

import AVFoundation

public enum MedusaError: Error {
    case captureDeviceError
    case audioDeviceError
    case startWritingfailed
    case generateAssetWriterInputfailed
}

public protocol CaptureSessionCoordinatorDelegate: class {

    func coordinatorVideoDataOutput(didOutputSampleBuffer sampleBuffer: CMSampleBuffer, completionHandler: ((CMSampleBuffer, CIImage?) -> Void))

    func coordinatorWillBeginRecording(_ coordinator: CaptureSessionCoordinator)

    func coordinatorDidBeginRecording(_ coordinator: CaptureSessionCoordinator)

    func coordinatorWillPauseRecording(_ coordinator: CaptureSessionCoordinator)

    func coordinatorDidPauseRecording(_ coordinator: CaptureSessionCoordinator, segments: [Segment])

    func coordinatorWillDidFinishRecording(_ coordinator: CaptureSessionCoordinator)

    func coordinatorDidRecording(_ coordinator: CaptureSessionCoordinator, seconds: Float)

    func coordinator(_ coordinator: CaptureSessionCoordinator, didFinishRecordingToOutputFileURL outputFileURL: URL?, error: Error?)
}

extension CaptureSessionCoordinatorDelegate {

    public func coordinatorVideoDataOutput(didOutputSampleBuffer sampleBuffer: CMSampleBuffer, completionHandler: ((CMSampleBuffer, CIImage?) -> Void)) {}

    public func coordinatorWillBeginRecording(_ coordinator: CaptureSessionCoordinator) {}

    public func coordinatorWillPauseRecording(_ coordinator: CaptureSessionCoordinator) {}

    public func coordinatorDidPauseRecording(_ coordinator: CaptureSessionCoordinator, segments: [Segment]) {}

    public func coordinatorDidRecording(_ coordinator: CaptureSessionCoordinator, seconds: Float) {}

    public func coordinatorWillDidFinishRecording(_ coordinator: CaptureSessionCoordinator) {}
}

open class CaptureSessionCoordinator: NSObject {

    open var captureDevice: AVCaptureDevice

    public let captureSession: AVCaptureSession

    public let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue: DispatchQueue

    open weak var delegate: CaptureSessionCoordinatorDelegate?

    private var captureDeviceInput: AVCaptureDeviceInput

    private var audioDeviceInput: AVCaptureDeviceInput


    public init(sessionPreset: AVCaptureSession.Preset, position: AVCaptureDevice.Position = .back) throws {

        captureDeviceInput = try AVCaptureDeviceInput.med.captureDeviceInput(withPosition: position)

        audioDeviceInput = try AVCaptureDeviceInput.med.audioDeviceInput()

        let captureSession: AVCaptureSession = {
            $0.sessionPreset = sessionPreset
            return $0
        }(AVCaptureSession())

        self.captureSession  = captureSession
        self.captureDevice   = captureDeviceInput.device
        self.sessionQueue    = DispatchQueue(label: "top.limon.capturepipeline.session", attributes: [])
        self.previewLayer    = AVCaptureVideoPreviewLayer(session: captureSession)

        super.init()

        try addInput(captureDeviceInput, toCaptureSession: captureSession)
        try addInput(audioDeviceInput, toCaptureSession: captureSession)
    }

    open func swapCaptureDevicePosition() throws {

        let newPosition = captureDevice.position == .back ? AVCaptureDevice.Position.front : .back

        let newCaptureDeviceInput = try AVCaptureDeviceInput.med.captureDeviceInput(withPosition: newPosition)
        let newAudioDeviceInput = try AVCaptureDeviceInput.med.audioDeviceInput()

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
}

// MARK: - Public Methods

extension CaptureSessionCoordinator {

    public func startRunning() {
        if captureSession.isRunning { return }
        sessionQueue.sync {
            self.captureSession.startRunning()
        }
    }

    public func stopRunning() {
        if !captureSession.isRunning { return }
        sessionQueue.sync {
            self.captureSession.stopRunning()
        }
    }

    public func addOutput(_ output: AVCaptureOutput, toCaptureSession captureSession: AVCaptureSession) throws {
        guard captureSession.canAddOutput(output) else { throw MedusaError.captureDeviceError }
        captureSession.addOutput(output)
    }

    public func addInput(_ input: AVCaptureDeviceInput, toCaptureSession captureSession: AVCaptureSession) throws {
        guard captureSession.canAddInput(input) else { throw MedusaError.captureDeviceError }
        captureSession.addInput(input)
    }
}
