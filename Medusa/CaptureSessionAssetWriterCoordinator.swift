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
    case StoppingRecording

    public var hashValue: Int {
        switch self {
        case .Idle:
            return 10000
        case .StartingRecording:
            return 20000
        case .Recording:
            return 30000
        case .StoppingRecording:
            return 40000
        }
    }
}

public final class CaptureSessionAssetWriterCoordinator: CaptureSessionCoordinator {

    public var recordingURL: NSURL

    private let videoDataOutput: AVCaptureVideoDataOutput
    private let audioDataOutput: AVCaptureAudioDataOutput

    private var videoConnection: AVCaptureConnection!
    private var audioConnection: AVCaptureConnection!

    private let videoCompressionSettings: [String: AnyObject]
    private let audioCompressionSettings: [String: AnyObject]

    private var outputVideoFormatDescription: CMFormatDescriptionRef?
    private var outputAudioFormatDescription: CMFormatDescriptionRef?

    private var assetWriterCoordinator: AssetWriterCoordinator?

    private var recordingStatus: RecordingStatus = .Idle(error: nil) {

        willSet(newStatus) {

            let oldStatus = recordingStatus

            guard newStatus != oldStatus else { return }

            let delegateCallbackQueue = dispatch_get_main_queue()

            if case .Idle(let error) = newStatus where error != nil {

                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        self.delegate?.coordinator(self, didFinishRecordingToOutputFileURL: self.recordingURL, error: error)
                    }
                }

                return
            }

            switch (oldStatus, newStatus) {
            case (.Idle, .StartingRecording):

                // "Click Record Action"
                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        self.delegate?.coordinatorWillBeginRecording(self)
                    }
                }

            case (.Recording, .StoppingRecording):

                // "Click Stop Record Action"
                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        self.delegate?.coordinatorWillDidFinishRecording(self)
                    }
                }

            case (.StartingRecording, .Recording):
                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        self.delegate?.coordinatorDidBeginRecording(self)
                    }
                }

            case (.StoppingRecording, .Idle(let error)) where error == nil:

                dispatch_async(delegateCallbackQueue) {
                    autoreleasepool {
                        self.delegate?.coordinator(self, didFinishRecordingToOutputFileURL: self.recordingURL, error: nil)
                    }
                }

            default:
                print("Unknow RecordingStatus")
            }

        }
    }


    public init(sessionPreset: String, size: CGSize, recordingURL: NSURL, position: AVCaptureDevicePosition = .Back) throws {

        videoDataOutput = {
            $0.videoSettings = nil
            $0.alwaysDiscardsLateVideoFrames = false
            return $0
        }(AVCaptureVideoDataOutput())

        audioDataOutput = AVCaptureAudioDataOutput()

        let codecSettings = [AVVideoAverageBitRateKey: 2000000, AVVideoMaxKeyFrameIntervalKey: 24]

        videoCompressionSettings = [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoCompressionPropertiesKey: codecSettings,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]

        audioCompressionSettings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000
        ]

        self.recordingURL = recordingURL

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

    public override func startRecording() {

        super.startRecording()

        synchronized(self) {

            guard case .Idle = recordingStatus else { return }

            recordingStatus = .StartingRecording
        }

        assetWriterCoordinator = AssetWriterCoordinator(URL: recordingURL)

        if let outputAudioFormatDescription = outputAudioFormatDescription {
            assetWriterCoordinator?.addAudioTrackWithSourceFormatDescription(outputAudioFormatDescription, settings: audioCompressionSettings)
        }

        if let outputVideoFormatDescription = outputVideoFormatDescription {
            assetWriterCoordinator?.addVideoTrackWithSourceFormatDescription(outputVideoFormatDescription, settings: videoCompressionSettings)
        }

        assetWriterCoordinator?.delegate = self

        // asynchronous, will call us back with recorderDidFinishPreparing: or recorder:didFailWithError: when done
        assetWriterCoordinator?.prepareToRecord()
    }

    public override func stopRecording() {

        super.stopRecording()

        guard recordingStatus == .Recording else { return }

        recordingStatus = .StoppingRecording
        assetWriterCoordinator?.finishRecording()
    }

    public override func swapCaptureDevicePosition() throws {

        try super.swapCaptureDevicePosition()

        // reset

        outputAudioFormatDescription = nil
        outputVideoFormatDescription = nil

        (videoConnection, audioConnection) = try fetchConnections(fromVideoDataOutput: videoDataOutput, andAudioDataOutput: audioDataOutput)
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
            assetWriterCoordinator = nil
            recordingStatus = .Idle(error: error)
        }
    }

    func writerCoordinatorDidFinishRecording(coordinator: AssetWriterCoordinator) {

        synchronized(self) {
            guard recordingStatus == .StoppingRecording else { return }
        }

        synchronized(self) {
            assetWriterCoordinator = nil
            recordingStatus = .Idle(error: nil)
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

                // TODO: outputVideoFormatDescription should be updated whenever video configuration is changed (frame rate, etc.)
                // Currently we don't use the outputVideoFormatDescription in IDAssetWriterRecoredSession

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


