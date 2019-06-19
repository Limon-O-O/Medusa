//
//  CaptureSessionAssetWriterCoordinator.swift
//  Medusa
//
//  Created by Limon on 2016/6/13.
//  Copyright © 2016年 Medusa. All rights reserved.
//

import AVFoundation

public enum RecordingStatus: Equatable {

    case idle(error: Error?)
    case startingRecording
    case recording
    case pause
    case pausing
    case stoppingRecording

    private var hashValue: Int {
        switch self {
        case .idle:
            return 10000
        case .startingRecording:
            return 20000
        case .recording:
            return 30000
        case .pause:
            return 40000
        case .pausing:
            return 50000
        case .stoppingRecording:
            return 60000
        }
    }

    public static func ==(lhs: RecordingStatus, rhs: RecordingStatus) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
}

public final class CaptureSessionAssetWriterCoordinator: CaptureSessionCoordinator {

    public var segmentsTransition = true

    public var presetName = AVAssetExportPresetHighestQuality

    public var captureVideoOrientation: AVCaptureVideoOrientation {
        return videoConnection?.videoOrientation ?? .portrait
    }

    private let videoDataOutput: AVCaptureVideoDataOutput
    private let audioDataOutput: AVCaptureAudioDataOutput

    private var videoConnection: AVCaptureConnection!
    private var audioConnection: AVCaptureConnection!

    private var outputVideoFormatDescription: CMFormatDescription?
    private var outputAudioFormatDescription: CMFormatDescription?

    private var assetWriterCoordinator: AssetWriterCoordinator?

    private var segments = [Segment]()

    private var attributes: Attributes

    private var isCancelRecording: Bool = false

    public private(set) var recordingStatus: RecordingStatus = .idle(error: nil) {

        didSet(oldStatus) {

            let currentStatus = recordingStatus

            guard currentStatus != oldStatus else { return }

            let delegateCallbackQueue = DispatchQueue.main

            let clearAction = { [weak self] in

                guard let strongSelf = self else { return }

                strongSelf.removeSegments()

                strongSelf.attributes._destinationURL = strongSelf.attributes.destinationURL

                strongSelf.assetWriterCoordinator = nil
            }

            if case .idle(let error) = currentStatus, error != nil {

                delegateCallbackQueue.async { [weak self] in
                    guard let sSelf = self else { return }
                    autoreleasepool { [weak sSelf] in
                        guard let ssSelf = sSelf else { return }
                        clearAction()
                        if !ssSelf.isCancelRecording {
                            ssSelf.delegate?.coordinator(ssSelf, didFinishRecordingToOutputFileURL: nil, error: error)
                        }
                    }
                }

                return
            }

            switch (oldStatus, currentStatus) {

            // Click Record Action
            case (.idle, .startingRecording):
                delegateCallbackQueue.async { [weak self] in
                    guard let sSelf = self else { return }
                    sSelf.delegate?.coordinatorWillBeginRecording(sSelf)
                }

            // Click Stop Record Action
            case (.recording, .stoppingRecording):
                delegateCallbackQueue.async { [weak self] in
                    guard let sSelf = self else { return }
                    sSelf.delegate?.coordinatorWillDidFinishRecording(sSelf)
                }

            // Start Recording
            case (.startingRecording, .recording):
                delegateCallbackQueue.async { [weak self] in
                    guard let sSelf = self else { return }
                    sSelf.delegate?.coordinatorDidBeginRecording(sSelf)
                }

            // Stop Recording
            case (.stoppingRecording, .idle):
                delegateCallbackQueue.async { [weak self] in
                    guard let sSelf = self else { return }
                    autoreleasepool { [weak sSelf] in

                        guard let ssSelf = sSelf else { return }

                        let finish: () -> Void = { [weak ssSelf] in
                            guard let sssSelf = ssSelf else { return }
                            clearAction()
                            sssSelf.recordingStatus = .idle(error: nil)
                            if !sssSelf.isCancelRecording {
                                sssSelf.delegate?.coordinator(sssSelf, didFinishRecordingToOutputFileURL: sssSelf.attributes.destinationURL, error: nil)
                            }
                        }

                        if ssSelf.isCancelRecording {
                            finish()
                            return
                        }

                        if ssSelf.segments.count > 1 {
                            ssSelf.exportSegmentsAsynchronously() { [weak ssSelf] error in
                                guard let sssSelf = ssSelf else { return }
                                if let error = error {
                                    sssSelf.delegate?.coordinator(sssSelf, didFinishRecordingToOutputFileURL: nil, error: error)
                                } else {
                                    finish()
                                }
                            }

                        } else if ssSelf.segments.count == 1 {
                            FileManager.med.moveItem(at: ssSelf.segments[0].URL, toURL: ssSelf.attributes.destinationURL)
                            finish()
                        } else {
                            finish()
                        }
                    }
                }

            // Pausing -> StoppingRecording
            case (.pausing, .stoppingRecording):
                delegateCallbackQueue.async { [weak self] in

                    guard let sSelf = self else { return }

                    autoreleasepool { [weak sSelf] in

                        guard let ssSelf = sSelf else { return }

                        if ssSelf.segments.count == 1 {

                            FileManager.med.moveItem(at: ssSelf.segments[0].URL, toURL: ssSelf.attributes.destinationURL)
                            ssSelf.segments.removeAll()

                            ssSelf.recordingStatus = .idle(error: nil)

                        } else if ssSelf.segments.count > 1 {

                            ssSelf.exportSegmentsAsynchronously() { [weak ssSelf] error in
                                guard let sssSelf = ssSelf else { return }
                                sssSelf.removeSegments()
                                sssSelf.recordingStatus = .idle(error: error)
                            }
                        }
                    }
                }

            // Click Pause
            case (.recording, .pause):
                delegateCallbackQueue.async { [weak self] in
                    guard let sSelf = self else { return }
                    sSelf.delegate?.coordinatorWillPauseRecording(sSelf)
                }

            // Did Pause
            case (.pause, .pausing):
                delegateCallbackQueue.async { [weak self] in
                    guard let sSelf = self else { return }
                    sSelf.delegate?.coordinatorDidPauseRecording(sSelf, segments: sSelf.segments)
                    sSelf.assetWriterCoordinator = nil
                }

            default:
                med_print("Unknow RecordingStatus: \(oldStatus) -> \(currentStatus)")
            }

        }
    }

    public init(sessionPreset: AVCaptureSession.Preset, attributes: Attributes, position: AVCaptureDevice.Position = .back, videoOrientation: AVCaptureVideoOrientation = .portrait) throws {

        videoDataOutput = {

            /* 
             To receive samples in a default uncompressed format, set this property to nil.
             More infos: print(CMSampleBufferGetFormatDescription(sampleBuffer))
            */
            $0.videoSettings = nil
            $0.alwaysDiscardsLateVideoFrames = false
            return $0

        }(AVCaptureVideoDataOutput())

        audioDataOutput = AVCaptureAudioDataOutput()

        self.attributes = attributes

        try super.init(sessionPreset: sessionPreset, position: position)

        try addOutput(videoDataOutput, toCaptureSession: captureSession)
        try addOutput(audioDataOutput, toCaptureSession: captureSession)

        let (videoConnection, audioConnection) = try fetchConnections(from: captureDevice, fromVideoDataOutput: videoDataOutput, videoOrientation: videoOrientation, andAudioDataOutput: audioDataOutput)

        self.videoConnection = videoConnection
        self.audioConnection = audioConnection

        let videoDataOutputQueue = DispatchQueue(label: "top.limon.capturesession.videodata", attributes: [])
        let audioDataOutputQueue = DispatchQueue(label: "top.limon.capturesession.audiodata", attributes: [])

        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        audioDataOutput.setSampleBufferDelegate(self, queue: audioDataOutputQueue)
    }

    public override func swapCaptureDevicePosition() throws {
        try super.swapCaptureDevicePosition()

        // reset
        do {
            (outputVideoFormatDescription, outputAudioFormatDescription) = (nil, nil)

            let (videoConnection, audioConnection) = try fetchConnections(from: captureDevice, fromVideoDataOutput: videoDataOutput, videoOrientation: self.videoConnection.videoOrientation, andAudioDataOutput: audioDataOutput)
            self.videoConnection = videoConnection
            self.audioConnection = audioConnection
        }
    }

    public func configureVideoOrientation(by deviceOrientation: UIDeviceOrientation) throws {

        let videoOrientation: AVCaptureVideoOrientation

        switch deviceOrientation {
        case .landscapeLeft:
            videoOrientation = .landscapeLeft
        case .landscapeRight:
            videoOrientation = .landscapeRight
        default:
            videoOrientation = .portrait
        }

        // reset
        do {
            (outputVideoFormatDescription, outputAudioFormatDescription) = (nil, nil)
            let (videoConnection, audioConnection) = try fetchConnections(from: captureDevice, fromVideoDataOutput: videoDataOutput, videoOrientation: videoOrientation, andAudioDataOutput: audioDataOutput)
            self.videoConnection = videoConnection
            self.audioConnection = audioConnection
        }
    }

    deinit {
        med_print("CaptureSessionAssetWriterCoordinator Deinit")
    }
}

// MARK: - Public Methods

extension CaptureSessionAssetWriterCoordinator {

    public func startRecording(videoDimensions: CMVideoDimensions? = nil, deviceOrientation: UIDeviceOrientation) {

        objc_sync_enter(self)

        if let videoDimensions = videoDimensions {
            attributes.videoDimensions = videoDimensions
        }

        switch recordingStatus {
        case .idle, .pausing:
            let newURL = makeNewFileURL()
            let segment = Segment(URL: newURL, seconds: 0.0)
            segments.append(segment)
            attributes._destinationURL = newURL
        default:
            return
        }

        recordingStatus = .startingRecording

        objc_sync_exit(self)

        assetWriterCoordinator = AssetWriterCoordinator(URL: attributes._destinationURL, fileType: attributes.mediaFormat.fileFormat)

        if let outputVideoFormatDescription = outputVideoFormatDescription {
            assetWriterCoordinator?.addVideoTrackWithSourceFormatDescription(outputVideoFormatDescription, settings: attributes.videoCompressionSettings)
        }

        if let outputAudioFormatDescription = outputAudioFormatDescription {
            assetWriterCoordinator?.addAudioTrackWithSourceFormatDescription(outputAudioFormatDescription, settings: attributes.audioCompressionSettings)
        }

        assetWriterCoordinator?.delegate = self

        // asynchronous, will call us back with recorderDidFinishPreparing: or recorder:didFailWithError: when done
        assetWriterCoordinator?.prepareToRecord(devicePosition: captureDevice.position, deviceOrientation: deviceOrientation)
    }

    public func stopRecording(isCancel: Bool) {

        objc_sync_enter(self)
        guard recordingStatus == .pausing || recordingStatus == .recording else { return }
        isCancelRecording = isCancel
        recordingStatus = .stoppingRecording
        objc_sync_exit(self)

        assetWriterCoordinator?.finishRecording()
    }

    public func pause() {

        objc_sync_enter(self)
        guard recordingStatus == .recording else { return }
        recordingStatus = .pause
        objc_sync_exit(self)

        assetWriterCoordinator?.finishRecording()
    }

    public func removeLastSegment() {
        guard let lastSegment = segments.last else { return }
        FileManager.med.removeExistingFile(at: lastSegment.URL)
        segments.removeLast()
    }

}

// MARK: - AssetWriterCoordinatorDelegate

extension CaptureSessionAssetWriterCoordinator: AssetWriterCoordinatorDelegate {

    func writerCoordinatorDidFinishPreparing(_ coordinator: AssetWriterCoordinator) {

        objc_sync_enter(self)
        guard recordingStatus == .startingRecording else { return }
        recordingStatus = .recording
        objc_sync_exit(self)
    }

    func writerCoordinator(_ coordinator: AssetWriterCoordinator, didFailWithError error: Error?) {

        objc_sync_enter(self)
        recordingStatus = .idle(error: error)
        objc_sync_exit(self)
    }

    func writerCoordinatorDidRecording(_ coordinator: AssetWriterCoordinator, seconds: Float) {
        DispatchQueue.main.async {
            self.delegate?.coordinatorDidRecording(self, seconds: seconds)
        }
    }

    func writerCoordinatorDidFinishRecording(_ coordinator: AssetWriterCoordinator, seconds: Float) {

        if !segments.isEmpty {
            segments[segments.count - 1].seconds = seconds
        }

        if recordingStatus == .stoppingRecording {

            objc_sync_enter(self)
            recordingStatus = .idle(error: nil)
            objc_sync_exit(self)

        } else if self.recordingStatus == .pause {

            objc_sync_enter(self)
            recordingStatus = .pausing
            objc_sync_exit(self)

        }

    }
}

// MARK: - SampleBufferDelegate Methods

extension CaptureSessionAssetWriterCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)

        if connection == videoConnection {

            if outputVideoFormatDescription == nil {

                // Don't render the first sample buffer.
                // This gives us one frame interval (33ms at 30fps) for setupVideoPipelineWithInputFormatDescription: to complete.
                // Ideally this would be done asynchronously to ensure frames don't back up on slower devices.

                // outputVideoFormatDescription should be updated whenever video configuration is changed (frame rate, etc.)

                outputVideoFormatDescription = formatDescription

            } else {

                outputVideoFormatDescription = formatDescription
            }

            delegate?.coordinatorVideoDataOutput(didOutputSampleBuffer: sampleBuffer, completionHandler: { [weak self] buffer, image in

                guard let strongSelf = self else { return }

                if strongSelf.recordingStatus == .recording {
                    strongSelf.assetWriterCoordinator?.appendVideoSampleBuffer(buffer, outputImage: image)
                }
            })

        } else if connection == audioConnection {

            outputAudioFormatDescription = formatDescription

            if recordingStatus == .recording {
                assetWriterCoordinator?.appendAudioSampleBuffer(sampleBuffer)
            }

        }
    }
}

// MARK: - Private Methods

extension CaptureSessionAssetWriterCoordinator {

    private func fetchConnections(from captureDevice: AVCaptureDevice, fromVideoDataOutput videoDataOutput: AVCaptureVideoDataOutput, videoOrientation: AVCaptureVideoOrientation, andAudioDataOutput audioDataOutput: AVCaptureAudioDataOutput) throws -> (videoConnection: AVCaptureConnection, audioConnection: AVCaptureConnection) {

        guard let unwrappedVideoConnection = videoDataOutput.connection(with: AVMediaType.video) else {
            throw MedusaError.captureDeviceError
        }

        guard let unwrappedAudioConnection = audioDataOutput.connection(with: AVMediaType.audio) else {
            throw MedusaError.audioDeviceError
        }

        if unwrappedVideoConnection.isVideoStabilizationSupported {
            unwrappedVideoConnection.preferredVideoStabilizationMode = .standard
        }

        // Up Orientation
        //        unwrappedVideoConnection.videoOrientation = videoOrientation

        // Flip Horizontal
        if captureDevice.position == .front && unwrappedVideoConnection.isVideoMirroringSupported && unwrappedVideoConnection.isVideoOrientationSupported {
            unwrappedVideoConnection.isVideoMirrored = true
            //            unwrappedVideoConnection.automaticallyAdjustsVideoMirroring = true
            //            unwrappedVideoConnection.videoOrientation = videoOrientation
        }

        return (videoConnection: unwrappedVideoConnection, audioConnection: unwrappedAudioConnection)

    }

    private func exportSegmentsAsynchronously(_ completionHandler: (_ error: Error?) -> Void) {
        Exporter.shareInstance.exportSegmentsAsynchronously(segments, to: attributes.destinationURL, transition: segmentsTransition, presetName: presetName, fileFormat: attributes.mediaFormat.fileFormat, completionHandler: completionHandler)
    }

    private func removeSegments() {
        segments.forEach {
            FileManager.med.removeExistingFile(at: $0.URL)
        }

        segments.removeAll()
    }

    private func makeNewFileURL() -> Foundation.URL {

        let suffix = "-medusa_segment\(segments.count)"

        let destinationPath = String(attributes.destinationURL.absoluteString.dropLast(attributes.mediaFormat.filenameExtension.count))

        let newAbsoluteString = destinationPath + suffix + attributes.mediaFormat.filenameExtension

        return Foundation.URL(string: newAbsoluteString)!
    }
}

