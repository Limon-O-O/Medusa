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
    case Resume
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
        case .Resume:
            return 50000
        case .StoppingRecording:
            return 60000
        }
    }
}


public final class CaptureSessionAssetWriterCoordinator: CaptureSessionCoordinator {

    private let videoDataOutput: AVCaptureVideoDataOutput
    private let audioDataOutput: AVCaptureAudioDataOutput

    private var videoConnection: AVCaptureConnection!
    private var audioConnection: AVCaptureConnection!

    private var outputVideoFormatDescription: CMFormatDescriptionRef?
    private var outputAudioFormatDescription: CMFormatDescriptionRef?

    private var assetWriterCoordinator: AssetWriterCoordinator?

    private var segments = [Segment]()

    private var attributes: Attributes?

    private var recordingStatus: RecordingStatus = .Idle(error: nil) {

        willSet(newStatus) {

            let oldStatus = recordingStatus

            guard newStatus != oldStatus else { return }

            let delegateCallbackQueue = dispatch_get_main_queue()

            if case .Idle(let error) = newStatus where error != nil {

                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        self.delegate?.coordinator(self, didFinishRecordingToOutputFileURL: self.assetWriterCoordinator?.URL, error: error)
                        self.assetWriterCoordinator = nil
                    }
                }

                return
            }

            switch (oldStatus, newStatus) {

            // "Click Record Action"
            case (.Idle, .StartingRecording):
                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        self.delegate?.coordinatorWillBeginRecording(self)
                    }
                }

            // "Click Stop Record Action"
            case (.Recording, .StoppingRecording):
                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        self.delegate?.coordinatorWillDidFinishRecording(self)
                    }
                }

            // "Start Recording"
            case (.StartingRecording, .Recording):
                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        self.delegate?.coordinatorDidBeginRecording(self)
                    }
                }

            // "Stop Recording"
            case (.StoppingRecording, .Idle):
                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        self.delegate?.coordinator(self, didFinishRecordingToOutputFileURL: self.assetWriterCoordinator?.URL, error: nil)
                        self.assetWriterCoordinator = nil
                    }
                }

            // "Click Pause"
            case (.Recording, .Pause):
                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        print("Click Pause")
                    }
                }

            // "Did Pause"
            case (.Pause, .Idle):
                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        print("Did Pause")
                        self.assetWriterCoordinator = nil
                    }
                }

            default:
                print("Unknow RecordingStatus")
            }

        }
    }


    public override init(sessionPreset: String, position: AVCaptureDevicePosition = .Back) throws {

        videoDataOutput = {
            $0.videoSettings = nil
            $0.alwaysDiscardsLateVideoFrames = false
            return $0
        }(AVCaptureVideoDataOutput())

        audioDataOutput = AVCaptureAudioDataOutput()

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


// MARK: Public Methods

extension CaptureSessionAssetWriterCoordinator {

    public func startRecording(byAttributes attributes: Attributes) {

        synchronized(self) {
            guard case .Idle = recordingStatus else { return }
            recordingStatus = .StartingRecording
        }

        self.attributes = attributes

        assetWriterCoordinator = AssetWriterCoordinator(URL: attributes.recordingURL, fileType: attributes.fileType)

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

        guard recordingStatus == .Recording else { return }

        recordingStatus = .StoppingRecording
        self.assetWriterCoordinator?.finishRecording()
    }

    public func pause() {

        guard recordingStatus == .Recording else { return }

        endSegment()
    }

    public func resume() {

        guard let attributes = self.attributes else { return }

        let absoluteString = attributes.recordingURL.absoluteString
        var newAbsoluteString: String?

        if let startIndex = absoluteString.med_find(".", options: .BackwardsSearch) {

            let suffix = "---medusa_segment"
            let filePath = absoluteString[absoluteString.startIndex..<absoluteString.startIndex.advancedBy(startIndex)]
            let fileExtension = absoluteString[absoluteString.startIndex.advancedBy(startIndex)..<absoluteString.endIndex]

            newAbsoluteString = filePath + suffix + fileExtension
        }

        let newURL = NSURL(string: newAbsoluteString!)!

        print(newURL.absoluteString)

        let newAttributes = Attributes(recordingURL: newURL, fileType: attributes.fileType, videoCompressionSettings: attributes.videoCompressionSettings, audioCompressionSettings: attributes.audioCompressionSettings)

        startRecording(byAttributes: newAttributes)
    }

    public override func swapCaptureDevicePosition() throws {

        try super.swapCaptureDevicePosition()

        // reset

        outputAudioFormatDescription = nil
        outputVideoFormatDescription = nil

        (videoConnection, audioConnection) = try fetchConnections(fromVideoDataOutput: videoDataOutput, andAudioDataOutput: audioDataOutput)
    }

    private func endSegment() {

        let segment = Segment(URL: assetWriterCoordinator!.URL)
        segments.append(segment)

        synchronized(self) {
            recordingStatus = .Pause
        }

        assetWriterCoordinator?.finishRecording()
    }

    private func nextFileURL() {

    }

    private func segmentURLForFilename() {

    }
}


// MARK: AssetWriterCoordinatorDelegate

extension CaptureSessionAssetWriterCoordinator: AssetWriterCoordinatorDelegate {

    func writerCoordinatorDidFinishPreparing(coordinator: AssetWriterCoordinator) {

        synchronized(self) {
            guard recordingStatus == .StartingRecording else { return }
            recordingStatus = .Recording
        }
    }

    func writerCoordinator(coordinator: AssetWriterCoordinator, didFailWithError error: NSError?) {

        synchronized(self) {
            recordingStatus = .Idle(error: error)
        }
    }

    private func removeExistingFile(byURL URL: NSURL) {
        let fileManager = NSFileManager.defaultManager()
        if let outputPath = URL.path where fileManager.fileExistsAtPath(outputPath) {
            let _ = try? fileManager.removeItemAtURL(URL)
        }
    }

    func writerCoordinatorDidFinishRecording(coordinator: AssetWriterCoordinator) {

        if recordingStatus == .StoppingRecording {

            let segment = Segment(URL: assetWriterCoordinator!.URL)
            segments.append(segment)

            let asset = assetRepresentingSegments(segments)

            let documentsDirectory = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)[0] as NSURL
            let filePath = documentsDirectory.URLByAppendingPathComponent("rendered-audioxxx.mp4")

            removeExistingFile(byURL: filePath)

            if let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) {

                exportSession.canPerformMultiplePassesOverSourceMediaData = true
                exportSession.outputURL = filePath
                exportSession.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration)
                exportSession.outputFileType = AVFileTypeMPEG4
                exportSession.exportAsynchronouslyWithCompletionHandler {
                    _ in

                    print("finished: \(filePath) :  \(exportSession.status == .Failed)")
                    self.assetWriterCoordinator?.URL = filePath

                    synchronized(self) {
                        guard self.recordingStatus == .StoppingRecording else { return }
                        self.recordingStatus = .Idle(error: nil)
                    }
                }
            }

        } else if self.recordingStatus == .Pause {
            self.recordingStatus = .Idle(error: nil)
        }

    }
}


// MARK: SampleBufferDelegate Methods

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

                outputVideoFormatDescription = formatDescription;

                synchronized(self) {
                    if recordingStatus == .Recording {
                        assetWriterCoordinator?.appendVideoSampleBuffer(sampleBuffer)
                    }
                }

            }

        } else if connection == audioConnection {

            outputAudioFormatDescription = formatDescription

            synchronized(self) {
                if recordingStatus == .Recording {
                    assetWriterCoordinator?.appendAudioSampleBuffer(sampleBuffer)
                }
            }

        }
    }
}


// MARK: Private Methods

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

        return (videoConnection: unwrappedVideoConnection, audioConnection: unwrappedAudioConnection)

    }
}

