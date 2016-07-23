//
//  AssetWriterCoordinator.swift
//  Medusa
//
//  Created by Limon on 6/14/16.
//  Copyright © 2016 Medusa. All rights reserved.
//

import AVFoundation


protocol AssetWriterCoordinatorDelegate: class {

    func writerCoordinatorDidFinishPreparing(coordinator: AssetWriterCoordinator)

    func writerCoordinatorDidFinishRecording(coordinator: AssetWriterCoordinator)

    func writerCoordinator(coordinator: AssetWriterCoordinator, didFailWithError error: NSError?)
}


func ==(lhs: WriterStatus, rhs: WriterStatus) -> Bool {
    return lhs.hashValue == rhs.hashValue
}

enum WriterStatus: Hashable {
    case Idle
    case PreparingToRecord
    case Recording
    case FinishingRecordingPart1    // waiting for inflight buffers to be appended
    case FinishingRecordingPart2    // calling finish writing on the asset writer
    case Finished                   // terminal state
    case Failed(error: NSError?)     // terminal state

    var hashValue: Int {
        switch self {
        case .Idle:
            return 10000
        case .PreparingToRecord:
            return 20000
        case .Recording:
            return 30000
        case .FinishingRecordingPart1:
            return 40000
        case .FinishingRecordingPart2:
            return 50000
        case .Finished:
            return 60000
        case .Failed:
            return 70000

        }
    }
}


class AssetWriterCoordinator {

    weak var delegate: AssetWriterCoordinatorDelegate?

    var URL: NSURL
    private let outputFileType: String
    private var assetWriter: AVAssetWriter?
    private var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor?
    private let writingQueue: dispatch_queue_t

    private weak var videoTrackSourceFormatDescription: CMFormatDescriptionRef?
    private var videoTrackSettings: [String: AnyObject]?
    private var assetWriterVideoInput: AVAssetWriterInput?

    private weak var audioTrackSourceFormatDescription: CMFormatDescriptionRef?
    private var audioTrackSettings: [String: AnyObject]?
    private var assetWriterAudioInput: AVAssetWriterInput?

    private var didStartedSession = false

    private var currentSampleTime: CMTime = kCMTimeNegativeInfinity

    private var writerStatus: WriterStatus = .Idle {

        willSet(newStatus) {

            guard newStatus != writerStatus else { return }

            let clearAction = {
                self.assetWriter = nil
                self.assetWriterVideoInput = nil
                self.assetWriterAudioInput = nil
                self.assetWriterPixelBufferInput = nil
            }

            dispatch_async(dispatch_get_main_queue()) {

                autoreleasepool {

                    switch newStatus {

                    case .Failed(let error):

                        clearAction()
                        NSFileManager.med_removeExistingFile(byURL: self.URL)

                        self.delegate?.writerCoordinator(self, didFailWithError: error)

                    case .Finished:
                        clearAction()
                        self.delegate?.writerCoordinatorDidFinishRecording(self)

                    case .Recording:
                        self.delegate?.writerCoordinatorDidFinishPreparing(self)

                    default:
                        break
                    }
                }

            }
        }
    }

    init(URL: NSURL, fileType outputFileType: String) {
        self.URL = URL
        self.writingQueue = dispatch_queue_create("top.limon.assetwriter.writing", DISPATCH_QUEUE_SERIAL)
        self.outputFileType = outputFileType
    }

    deinit {
        print("AssetWriterCoordinator Deinit")
    }

    func appendVideoSampleBuffer(sampleBuffer: CMSampleBufferRef) {
        appendSampleBuffer(sampleBuffer, ofMediaType: AVMediaTypeVideo)
    }

    func appendAudioSampleBuffer(sampleBuffer: CMSampleBufferRef) {
        appendSampleBuffer(sampleBuffer, ofMediaType: AVMediaTypeAudio)
    }

    func addAudioTrackWithSourceFormatDescription(formatDescription: CMFormatDescriptionRef, settings audioSettings: [String: AnyObject]) {

        objc_sync_enter(self)

        guard writerStatus == .Idle else { return }

        audioTrackSourceFormatDescription = formatDescription

        audioTrackSettings = audioSettings

        objc_sync_exit(self)

    }

    func addVideoTrackWithSourceFormatDescription(formatDescription: CMFormatDescriptionRef, settings videoSettings: [String: AnyObject]) {

        objc_sync_enter(self)

        guard writerStatus == .Idle else { return }

        videoTrackSourceFormatDescription = formatDescription

        videoTrackSettings = videoSettings

        objc_sync_exit(self)
    }

    func prepareToRecord() {

        objc_sync_enter(self)
        guard writerStatus == .Idle else { return }
        writerStatus = .PreparingToRecord
        objc_sync_exit(self)

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)) {
            autoreleasepool {

                do {

                    // Remove file if necessary. AVAssetWriter will not overwrite an existing file.
                    NSFileManager.med_removeExistingFile(byURL: self.URL)

                    self.assetWriter = try AVAssetWriter(URL: self.URL, fileType: self.outputFileType)
                    // Set this to make sure that a functional movie is produced, even if the recording is cut off mid-stream. Only the last second should be lost in that case.
                    self.assetWriter?.movieFragmentInterval = CMTimeMakeWithSeconds(1.0, 1000)

                    if let videoTrackSourceFormatDescription = self.videoTrackSourceFormatDescription, videoTrackSettings = self.videoTrackSettings {

                        self.assetWriterVideoInput = self.makeAssetWriterVideoInput(withSourceFormatDescription: videoTrackSourceFormatDescription, settings: videoTrackSettings)

                        if let videoInput = self.assetWriterVideoInput {
                            // TODO: Replace videoTrackSettings?
                            self.assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: videoTrackSettings)
                        }

                    }

                    if let audioTrackSourceFormatDescription = self.audioTrackSourceFormatDescription, audioTrackSettings = self.audioTrackSettings {
                        self.assetWriterAudioInput = self.makeAssetWriterAudioInput(withSourceFormatDescription: audioTrackSourceFormatDescription, settings: audioTrackSettings)
                    }

                    guard self.assetWriter!.startWriting() else {
                        // `error` is non-nil when startWriting returns false.
                        throw self.assetWriter!.error!
                    }

                    objc_sync_enter(self)
                    self.writerStatus = .Recording
                    objc_sync_exit(self)

                } catch let error as NSError {
                    objc_sync_enter(self)
                    self.writerStatus = .Failed(error: error)
                    objc_sync_exit(self)
                }
            }
        }
    }

    func finishRecording() {

        objc_sync_enter(self)
        guard writerStatus == .Recording else { return }
        writerStatus = .FinishingRecordingPart1
        objc_sync_exit(self)

        dispatch_async(writingQueue) {

            autoreleasepool {

                objc_sync_enter(self)
                // We may have transitioned to an error state as we appended inflight buffers. In that case there is nothing to do now.
                guard self.writerStatus == .FinishingRecordingPart1 else { return }

                // It is not safe to call -[AVAssetWriter finishWriting*] concurrently with -[AVAssetWriterInput appendSampleBuffer:]
                // We transition to MovieRecorderStatusFinishingRecordingPart2 while on _writingQueue, which guarantees that no more buffers will be appended.
                self.writerStatus = .FinishingRecordingPart2
                objc_sync_exit(self)

                if self.assetWriter?.status == .Some(.Writing) {
                    self.assetWriterVideoInput?.markAsFinished()
                    self.assetWriterAudioInput?.markAsFinished()
                }

                self.assetWriter?.finishWritingWithCompletionHandler {

                    objc_sync_enter(self)

                    if let error = self.assetWriter?.error {
                        self.writerStatus = .Failed(error: error)
                    } else {
                        self.writerStatus = .Finished
                    }

                    objc_sync_exit(self)
                }

            }

        }

    }

}


// MARK: Private Methods

extension AssetWriterCoordinator {

    private func appendSampleBuffer(sampleBuffer: CMSampleBufferRef, ofMediaType mediaType: String) {

        guard let assetWriter = assetWriter else { return }

        if writerStatus.hashValue < WriterStatus.Recording.hashValue {
            print("Not ready to record yet")
            return
        }

        dispatch_async(writingQueue) {

            autoreleasepool {

                // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
                // Because of this we are lenient when samples are appended and we are no longer recording.
                // Instead of throwing an exception we just release the sample buffers and return.
                if self.writerStatus.hashValue > WriterStatus.FinishingRecordingPart1.hashValue {
                    return
                }

                guard let assetWriterPixelBufferInput = self.assetWriterPixelBufferInput else { return }

                self.currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)

                if !self.didStartedSession && mediaType == AVMediaTypeVideo {
                    assetWriter.startSessionAtSourceTime(self.currentSampleTime)
                    self.didStartedSession = true
                }

                guard let input = (mediaType == AVMediaTypeVideo ? self.assetWriterVideoInput : self.assetWriterAudioInput) where input.readyForMoreMediaData && self.didStartedSession else { return }

                var newPixelBuffer: CVPixelBuffer? = nil

                CVPixelBufferPoolCreatePixelBuffer(nil, assetWriterPixelBufferInput.pixelBufferPool!, &newPixelBuffer)

                let success = assetWriterPixelBufferInput.appendPixelBuffer(newPixelBuffer!, withPresentationTime: self.currentSampleTime)

//                let success = input.appendSampleBuffer(sampleBuffer)

                objc_sync_enter(self)
                if !success {
                    self.writerStatus = .Failed(error: assetWriter.error)
                }
                objc_sync_exit(self)

            }
        }

    }

    private func makeAssetWriterVideoInput(withSourceFormatDescription videoFormatDescription: CMFormatDescriptionRef, settings videoSettings: [String: AnyObject]) -> AVAssetWriterInput? {

        guard let assetWriter = self.assetWriter where assetWriter.canApplyOutputSettings(videoSettings, forMediaType: AVMediaTypeVideo) else { return nil }

        let videoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings, sourceFormatHint: videoFormatDescription)
        videoInput.expectsMediaDataInRealTime = true
        videoInput.transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2)) // portrait orientation

        if assetWriter.canAddInput(videoInput) {
            assetWriter.addInput(videoInput)
            return videoInput
        }

        return nil
    }

    private func makeAssetWriterAudioInput(withSourceFormatDescription audioFormatDescription: CMFormatDescriptionRef, settings audioSettings: [String: AnyObject]) -> AVAssetWriterInput? {

        guard let assetWriter = self.assetWriter where assetWriter.canApplyOutputSettings(audioSettings, forMediaType: AVMediaTypeAudio) else { return nil }

        let audioInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioSettings, sourceFormatHint: audioFormatDescription)
        audioInput.expectsMediaDataInRealTime = true

        if assetWriter.canAddInput(audioInput) {
            assetWriter.addInput(audioInput)
            return audioInput
        }
        return nil
    }
}

