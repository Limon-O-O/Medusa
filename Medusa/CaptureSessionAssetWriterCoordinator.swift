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

    case idle(error: NSError?)
    case startingRecording
    case recording
    case pause
    case pausing
    case stoppingRecording

    public var hashValue: Int {
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
}

public final class CaptureSessionAssetWriterCoordinator: CaptureSessionCoordinator {

    public var segmentsTransition = true

    public var presetName = AVAssetExportPresetHighestQuality

    fileprivate let videoDataOutput: AVCaptureVideoDataOutput
    fileprivate let audioDataOutput: AVCaptureAudioDataOutput

    fileprivate var videoConnection: AVCaptureConnection!
    fileprivate var audioConnection: AVCaptureConnection!

    fileprivate var outputVideoFormatDescription: CMFormatDescription?
    fileprivate var outputAudioFormatDescription: CMFormatDescription?

    fileprivate var assetWriterCoordinator: AssetWriterCoordinator?

    fileprivate var segments = [Segment]()

    fileprivate var attributes: Attributes

    public fileprivate(set) var recordingStatus: RecordingStatus = .idle(error: nil) {

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

                delegateCallbackQueue.async {
                    autoreleasepool {
                        clearAction()
                        self.delegate?.coordinator(self, didFinishRecordingToOutputFileURL: nil, error: error)
                    }
                }

                return
            }

            switch (oldStatus, currentStatus) {

            // Click Record Action
            case (.idle, .startingRecording):
                delegateCallbackQueue.async {
                    self.delegate?.coordinatorWillBeginRecording(self)
                }

            // Click Stop Record Action
            case (.recording, .stoppingRecording):
                delegateCallbackQueue.async {
                    self.delegate?.coordinatorWillDidFinishRecording(self)
                }

            // Start Recording
            case (.startingRecording, .recording):
                delegateCallbackQueue.async {
                    self.delegate?.coordinatorDidBeginRecording(self)
                }

            // Stop Recording
            case (.stoppingRecording, .idle):
                delegateCallbackQueue.async { [weak self] in
                    autoreleasepool {

                        guard let strongSelf = self else { return }

                        let finish = {
                            clearAction()
                            strongSelf.recordingStatus = .idle(error: nil)
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

                            FileManager.med_moveItem(at: strongSelf.segments[0].URL, toURL: strongSelf.attributes.destinationURL)
                            finish()

                        } else {
                            finish()
                        }

                    }
                }

            // Pausing -> StoppingRecording
            case (.pausing, .stoppingRecording):
                delegateCallbackQueue.async {

                    autoreleasepool { [weak self] in

                        guard let strongSelf = self else { return }

                        if strongSelf.segments.count == 1 {

                            FileManager.med_moveItem(at: strongSelf.segments[0].URL, toURL: strongSelf.attributes.destinationURL)
                            strongSelf.segments.removeAll()

                            self?.recordingStatus = .idle(error: nil)

                        } else if strongSelf.segments.count > 1 {

                            self?.exportSegmentsAsynchronously() { error in
                                strongSelf.removeSegments()
                                self?.recordingStatus = .idle(error: error)
                            }
                        }
                    }
                }

            // Click Pause
            case (.recording, .pause):
                delegateCallbackQueue.async {
                    self.delegate?.coordinatorWillPauseRecording(self)
                }

            // Did Pause
            case (.pause, .pausing):
                delegateCallbackQueue.async {
                    self.delegate?.coordinatorDidPauseRecording(self, segments: self.segments)
                    self.assetWriterCoordinator = nil
                }

            default:
                print("Unknow RecordingStatus: \(oldStatus) -> \(currentStatus)")
            }

        }
    }

    public init(sessionPreset: String, attributes: Attributes, position: AVCaptureDevicePosition = .back) throws {

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

        let (videoConnection, audioConnection) = try fetchConnections(fromVideoDataOutput: videoDataOutput, andAudioDataOutput: audioDataOutput)

        self.videoConnection = videoConnection
        self.audioConnection = audioConnection

        let videoDataOutputQueue = DispatchQueue(label: "top.limon.capturesession.videodata", attributes: [])
        let audioDataOutputQueue = DispatchQueue(label: "top.limon.capturesession.audiodata", attributes: [])

        videoDataOutputQueue.setTarget(queue: DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.high))

        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        audioDataOutput.setSampleBufferDelegate(self, queue: audioDataOutputQueue)
    }
}

// MARK: - Public Methods

extension CaptureSessionAssetWriterCoordinator {

    public func startRecording() {

        objc_sync_enter(self)

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
        assetWriterCoordinator?.prepareToRecord()
    }

    public func stopRecording() {

        objc_sync_enter(self)
        guard recordingStatus == .pausing || recordingStatus == .recording else { return }
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

    public override func swapCaptureDevicePosition() throws {

        try super.swapCaptureDevicePosition()

        // reset
        do {
            (outputVideoFormatDescription, outputAudioFormatDescription) = (nil, nil)
            let (videoConnection, audioConnection) = try fetchConnections(fromVideoDataOutput: videoDataOutput, andAudioDataOutput: audioDataOutput)
            self.videoConnection = videoConnection
            self.audioConnection = audioConnection
        }
    }

    public func removeLastSegment() {
        guard let lastSegment = segments.last else { return }
        FileManager.med_removeExistingFile(at: lastSegment.URL)
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

    func writerCoordinator(_ coordinator: AssetWriterCoordinator, didFailWithError error: NSError?) {

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

    public func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {

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

                if strongSelf.recordingStatus == .recording {
                    strongSelf.assetWriterCoordinator?.appendVideoSampleBuffer(sampleBuffer, outputImage: image)
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

    fileprivate func fetchConnections(fromVideoDataOutput videoDataOutput: AVCaptureVideoDataOutput, andAudioDataOutput audioDataOutput: AVCaptureAudioDataOutput) throws -> (videoConnection: AVCaptureConnection, audioConnection: AVCaptureConnection) {

        guard let unwrappedVideoConnection = videoDataOutput.connection(withMediaType: AVMediaTypeVideo) else {
            throw MedusaError.captureDeviceError
        }

        guard let unwrappedAudioConnection = audioDataOutput.connection(withMediaType: AVMediaTypeAudio) else {
            throw MedusaError.audioDeviceError
        }

        if unwrappedVideoConnection.isVideoStabilizationSupported {
            unwrappedVideoConnection.preferredVideoStabilizationMode = .auto
        }

        // Up Orientation
        unwrappedVideoConnection.videoOrientation = .portrait

        // Flip Horizontal
        if captureDevice.position == .front && unwrappedVideoConnection.isVideoMirroringSupported && unwrappedVideoConnection.isVideoOrientationSupported {
            unwrappedVideoConnection.isVideoMirrored = true
            unwrappedVideoConnection.automaticallyAdjustsVideoMirroring = true
            unwrappedVideoConnection.videoOrientation = .portrait
        }

        return (videoConnection: unwrappedVideoConnection, audioConnection: unwrappedAudioConnection)

    }

    fileprivate func exportSegmentsAsynchronously(_ completionHandler: (_ error: NSError?) -> Void) {
        Exporter.shareInstance.exportSegmentsAsynchronously(segments, to: attributes.destinationURL, transition: segmentsTransition, presetName: presetName, fileFormat: attributes.mediaFormat.fileFormat, completionHandler: completionHandler)
    }

    fileprivate func removeSegments() {
        segments.forEach {
            FileManager.med_removeExistingFile(at: $0.URL)
        }

        segments.removeAll()
    }

    fileprivate func makeNewFileURL() -> URL {

        let suffix = "-medusa_segment\(segments.count)"

        let destinationPath = String(describing: attributes.destinationURL.absoluteString.characters.dropLast(attributes.mediaFormat.filenameExtension.characters.count))

        let newAbsoluteString = destinationPath + suffix + attributes.mediaFormat.filenameExtension

        return  URL(string: newAbsoluteString)!
    }
}

