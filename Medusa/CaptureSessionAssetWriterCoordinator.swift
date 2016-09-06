//
//  CaptureSessionAssetWriterCoordinator.swift
//  Medusa
//
//  Created by Limon on 2016/6/13.
//  Copyright © 2016年 Medusa. All rights reserved.
//

import AVFoundation

public func ==(lhs: RecordingStatus, rhs: RecordingStatus) -> Bool {
    return lhs.hashValue == rhs.hashValue
}

public enum RecordingStatus: Hashable {

    case Idle(error: NSError?)
    case StartingRecording
    case Recording
    case Pause
    case Pausing
    case StoppingRecording

    public var hashValue: Int {
        switch self {
        case .Idle:
            return 10000
        case .StartingRecording:
            return 20000
        case .Recording:
            return 30000
        case .Pause:
            return 40000
        case .Pausing:
            return 50000
        case .StoppingRecording:
            return 60000
        }
    }
}

public final class CaptureSessionAssetWriterCoordinator: CaptureSessionCoordinator {

    public var segmentsTransition = true

    public var presetName = AVAssetExportPresetHighestQuality

    private let videoDataOutput: AVCaptureVideoDataOutput
    private let audioDataOutput: AVCaptureAudioDataOutput

    private var videoConnection: AVCaptureConnection!
    private var audioConnection: AVCaptureConnection!

    private var outputVideoFormatDescription: CMFormatDescriptionRef?
    private var outputAudioFormatDescription: CMFormatDescriptionRef?

    private var assetWriterCoordinator: AssetWriterCoordinator?

    private var segments = [Segment]()

    private var attributes: Attributes

    public private(set) var recordingStatus: RecordingStatus = .Idle(error: nil) {

        didSet(oldStatus) {

            let currentStatus = recordingStatus

            guard currentStatus != oldStatus else { return }

            let delegateCallbackQueue = dispatch_get_main_queue()

            let clearAction = { [weak self] in

                guard let strongSelf = self else { return }

                strongSelf.removeSegments()

                strongSelf.attributes._destinationURL = strongSelf.attributes.destinationURL

                strongSelf.assetWriterCoordinator = nil
            }

            if case .Idle(let error) = currentStatus where error != nil {

                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        clearAction()
                        self.delegate?.coordinator(self, didFinishRecordingToOutputFileURL: nil, error: error)
                    }
                }

                return
            }

            switch (oldStatus, currentStatus) {

            // Click Record Action
            case (.Idle, .StartingRecording):
                dispatch_async(delegateCallbackQueue) {
                    self.delegate?.coordinatorWillBeginRecording(self)
                }

            // Click Stop Record Action
            case (.Recording, .StoppingRecording):
                dispatch_async(delegateCallbackQueue) {
                    self.delegate?.coordinatorWillDidFinishRecording(self)
                }

            // Start Recording
            case (.StartingRecording, .Recording):
                dispatch_async(delegateCallbackQueue) {
                    self.delegate?.coordinatorDidBeginRecording(self)
                }

            // Stop Recording
            case (.StoppingRecording, .Idle):
                dispatch_async(delegateCallbackQueue) { [weak self] in
                    autoreleasepool {

                        guard let strongSelf = self else { return }

                        let finish = {
                            clearAction()
                            strongSelf.recordingStatus = .Idle(error: nil)
                            strongSelf.delegate?.coordinator(strongSelf, didFinishRecordingToOutputFileURL: strongSelf.attributes.destinationURL, error: nil)
                        }

                        if strongSelf.segments.count > 1 {

                            self?.exportSegmentsAsynchronously() { error in
                                if let error = error {
                                    strongSelf.delegate?.coordinator(strongSelf, didFinishRecordingToOutputFileURL: nil, error: error)
                                } else {
                                    finish()
                                }
                            }

                        } else if strongSelf.segments.count == 1 {

                            NSFileManager.med_moveItem(atURL: strongSelf.segments[0].URL, toURL: strongSelf.attributes.destinationURL)
                            finish()

                        } else {
                            finish()
                        }

                    }
                }

            // Pausing -> StoppingRecording
            case (.Pausing, .StoppingRecording):
                dispatch_async(delegateCallbackQueue) {

                    autoreleasepool { [weak self] in

                        guard let strongSelf = self else { return }

                        if strongSelf.segments.count == 1 {

                            NSFileManager.med_moveItem(atURL: strongSelf.segments[0].URL, toURL: strongSelf.attributes.destinationURL)
                            strongSelf.segments.removeAll()

                            self?.recordingStatus = .Idle(error: nil)

                        } else if strongSelf.segments.count > 1 {

                            self?.exportSegmentsAsynchronously() { error in
                                strongSelf.removeSegments()
                                self?.recordingStatus = .Idle(error: error)
                            }
                        }
                    }
                }

            // Click Pause
            case (.Recording, .Pause):
                dispatch_async(delegateCallbackQueue) {
                    self.delegate?.coordinatorWillPauseRecording(self)
                }

            // Did Pause
            case (.Pause, .Pausing):
                dispatch_async(delegateCallbackQueue) {
                    self.delegate?.coordinatorDidPauseRecording(self, segments: self.segments)
                    self.assetWriterCoordinator = nil
                }

            default:
                print("Unknow RecordingStatus: \(oldStatus) -> \(currentStatus)")
            }

        }
    }

    public init(sessionPreset: String, attributes: Attributes, position: AVCaptureDevicePosition = .Back) throws {

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

        (videoConnection, audioConnection) = try fetchConnections(fromVideoDataOutput: videoDataOutput, andAudioDataOutput: audioDataOutput)

        let videoDataOutputQueue = dispatch_queue_create("top.limon.capturesession.videodata", DISPATCH_QUEUE_SERIAL)
        let audioDataOutputQueue = dispatch_queue_create("top.limon.capturesession.audiodata", DISPATCH_QUEUE_SERIAL)

        dispatch_set_target_queue(videoDataOutputQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0))

        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        audioDataOutput.setSampleBufferDelegate(self, queue: audioDataOutputQueue)
    }
}

// MARK: - Public Methods

extension CaptureSessionAssetWriterCoordinator {

    public func startRecording() {

        objc_sync_enter(self)

        switch recordingStatus {
        case .Idle, .Pausing:
            let newURL = makeNewFileURL()
            let segment = Segment(URL: newURL, seconds: 0.0)
            segments.append(segment)
            attributes._destinationURL = newURL
        default:
            return
        }

        recordingStatus = .StartingRecording

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
        assetWriterCoordinator?.prepareToRecord()
    }

    public func stopRecording() {

        objc_sync_enter(self)
        guard recordingStatus == .Pausing || recordingStatus == .Recording else { return }
        recordingStatus = .StoppingRecording
        objc_sync_exit(self)

        assetWriterCoordinator?.finishRecording()
    }

    public func pause() {

        objc_sync_enter(self)
        guard recordingStatus == .Recording else { return }
        recordingStatus = .Pause
        objc_sync_exit(self)

        assetWriterCoordinator?.finishRecording()
    }

    public override func swapCaptureDevicePosition() throws {

        try super.swapCaptureDevicePosition()

        // reset
        do {
            (outputVideoFormatDescription, outputAudioFormatDescription) = (nil, nil)
            (videoConnection, audioConnection) = try fetchConnections(fromVideoDataOutput: videoDataOutput, andAudioDataOutput: audioDataOutput)
        }
    }

    public func removeLastSegment() {
        guard let lastSegment = segments.last else { return }
        NSFileManager.med_removeExistingFile(byURL: lastSegment.URL)
        segments.removeLast()
    }

}

// MARK: - AssetWriterCoordinatorDelegate

extension CaptureSessionAssetWriterCoordinator: AssetWriterCoordinatorDelegate {

    func writerCoordinatorDidFinishPreparing(coordinator: AssetWriterCoordinator) {

        objc_sync_enter(self)
        guard recordingStatus == .StartingRecording else { return }
        recordingStatus = .Recording
        objc_sync_exit(self)
    }

    func writerCoordinator(coordinator: AssetWriterCoordinator, didFailWithError error: NSError?) {

        objc_sync_enter(self)
        recordingStatus = .Idle(error: error)
        objc_sync_exit(self)
    }

    func writerCoordinatorDidRecording(coordinator: AssetWriterCoordinator, seconds: Float) {
        dispatch_async(dispatch_get_main_queue()) {
            self.delegate?.coordinatorDidRecording(self, seconds: seconds)
        }
    }

    func writerCoordinatorDidFinishRecording(coordinator: AssetWriterCoordinator, seconds: Float) {

        if !segments.isEmpty {
            segments[segments.count - 1].seconds = seconds
        }

        if recordingStatus == .StoppingRecording {

            objc_sync_enter(self)
            recordingStatus = .Idle(error: nil)
            objc_sync_exit(self)

        } else if self.recordingStatus == .Pause {

            objc_sync_enter(self)
            recordingStatus = .Pausing
            objc_sync_exit(self)

        }

    }
}

// MARK: - SampleBufferDelegate Methods

extension CaptureSessionAssetWriterCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {

    public func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {

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

            delegate?.coordinatorVideoDataOutput(didOutputSampleBuffer: sampleBuffer, completionHandler: { [weak self] image in

                guard let strongSelf = self else { return }

                if strongSelf.recordingStatus == .Recording {
                    strongSelf.assetWriterCoordinator?.appendVideoSampleBuffer(sampleBuffer, outputImage: image)
                }
            })

        } else if connection == audioConnection {

            outputAudioFormatDescription = formatDescription

            if recordingStatus == .Recording {
                assetWriterCoordinator?.appendAudioSampleBuffer(sampleBuffer)
            }

        }
    }
}

// MARK: - Private Methods

extension CaptureSessionAssetWriterCoordinator {

    private func fetchConnections(fromVideoDataOutput videoDataOutput: AVCaptureVideoDataOutput, andAudioDataOutput audioDataOutput: AVCaptureAudioDataOutput) throws -> (videoConnection: AVCaptureConnection!, audioConnection: AVCaptureConnection!) {

        guard let unwrappedVideoConnection = videoDataOutput.connectionWithMediaType(AVMediaTypeVideo) else {
            throw MedusaError.CaptureDeviceError
        }

        guard let unwrappedAudioConnection = audioDataOutput.connectionWithMediaType(AVMediaTypeAudio) else {
            throw MedusaError.AudioDeviceError
        }

        if unwrappedVideoConnection.supportsVideoStabilization {
            unwrappedVideoConnection.preferredVideoStabilizationMode = .Auto
        }

        // Up Orientation
        unwrappedVideoConnection.videoOrientation = .Portrait

        // Flip Horizontal
        if captureDevice.position == .Front && unwrappedVideoConnection.supportsVideoMirroring && unwrappedVideoConnection.supportsVideoOrientation {
            unwrappedVideoConnection.videoMirrored = true
            unwrappedVideoConnection.automaticallyAdjustsVideoMirroring = true
            unwrappedVideoConnection.videoOrientation = .Portrait
        }

        return (videoConnection: unwrappedVideoConnection, audioConnection: unwrappedAudioConnection)

    }

    private func exportSegmentsAsynchronously(completionHandler: (error: NSError?) -> Void) {
        Exporter.shareInstance.exportSegmentsAsynchronously(segments, to: attributes.destinationURL, transition: segmentsTransition, presetName: presetName, fileFormat: attributes.mediaFormat.fileFormat, completionHandler: completionHandler)
    }

    private func removeSegments() {
        segments.forEach {
            NSFileManager.med_removeExistingFile(byURL: $0.URL)
        }

        segments.removeAll()
    }

    private func makeNewFileURL() -> NSURL {

        let suffix = "-medusa_segment\(segments.count)"

        let destinationPath = String(attributes.destinationURL.absoluteString.characters.dropLast(attributes.mediaFormat.filenameExtension.characters.count))

        let newAbsoluteString = destinationPath + suffix + attributes.mediaFormat.filenameExtension

        return  NSURL(string: newAbsoluteString)!
    }
}

