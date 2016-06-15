//
//  AssetWriterCoordinator.swift
//  VideoRecorderExample
//
//  Created by Limon on 6/14/16.
//  Copyright © 2016 VideoRecorder. All rights reserved.
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

    private let URL: NSURL
    private var assetWriter: AVAssetWriter?
    private let writingQueue: dispatch_queue_t

    private weak var videoTrackSourceFormatDescription: CMFormatDescriptionRef?
    private var videoTrackSettings: [String: AnyObject]?
    private var videoInput: AVAssetWriterInput?

    private weak var audioTrackSourceFormatDescription: CMFormatDescriptionRef?
    private var audioTrackSettings: [String: AnyObject]?
    private var audioInput: AVAssetWriterInput?

    private var didStartedSession = false

    private var writerStatus: WriterStatus = .Idle {

        willSet(newStatus) {

            guard newStatus != writerStatus else { return }

            let clearAction = {
                self.assetWriter = nil
                self.videoInput = nil
                self.audioInput = nil
            }

            dispatch_async(dispatch_get_main_queue()) {

                autoreleasepool {

                    switch newStatus {

                    case .Failed(let error):
                        clearAction()

                        self.removeExistingFile(byURL: self.URL)

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

    init(URL: NSURL) {
        self.URL = URL
        self.writingQueue = dispatch_queue_create("top.limon.assetwriter.writing", DISPATCH_QUEUE_SERIAL)
    }

    func appendVideoSampleBuffer(sampleBuffer: CMSampleBufferRef) {
        appendSampleBuffer(sampleBuffer, ofMediaType: AVMediaTypeVideo)
    }

    func appendAudioSampleBuffer(sampleBuffer: CMSampleBufferRef) {
        appendSampleBuffer(sampleBuffer, ofMediaType: AVMediaTypeAudio)
    }

    func addAudioTrackWithSourceFormatDescription(formatDescription: CMFormatDescriptionRef, settings audioSettings: [String: AnyObject]) {
        synchronized(self) {

            guard audioTrackSourceFormatDescription == nil && writerStatus == .Idle else { return }

            audioTrackSourceFormatDescription = formatDescription

            audioTrackSettings = audioSettings
        }
    }

    func addVideoTrackWithSourceFormatDescription(formatDescription: CMFormatDescriptionRef, settings videoSettings: [String: AnyObject]) {

        synchronized(self) {

            guard videoTrackSourceFormatDescription == nil && writerStatus == .Idle else { return }

            videoTrackSourceFormatDescription = formatDescription

            videoTrackSettings = videoSettings
        }
    }

    func prepareToRecord() {

        synchronized(self) {
            guard writerStatus == .Idle else { return }
            writerStatus = .PreparingToRecord
        }

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)) {
            autoreleasepool {

                do {

                    // Remove file if necessary. AVAssetWriter will not overwrite an existing file.
                    self.removeExistingFile(byURL: self.URL)

                    self.assetWriter = try AVAssetWriter(URL: self.URL, fileType: AVFileTypeQuickTimeMovie)

                    if let videoTrackSourceFormatDescription = self.videoTrackSourceFormatDescription, videoTrackSettings = self.videoTrackSettings {
                        self.setupAssetWriterVideoInput(withSourceFormatDescription: videoTrackSourceFormatDescription, settings: videoTrackSettings)
                    }

                    if let audioTrackSourceFormatDescription = self.audioTrackSourceFormatDescription, audioTrackSettings = self.audioTrackSettings {
                        self.setupAssetWriterAudioInput(withSourceFormatDescription: audioTrackSourceFormatDescription, settings: audioTrackSettings)
                    }

                    guard self.assetWriter!.startWriting() else {
                        // `error` is non-nil when startWriting returns false.
                        throw self.assetWriter!.error!
                    }

                    synchronized(self) {
                        self.writerStatus = .Recording
                    }

                } catch let error as NSError {
                    self.writerStatus = .Failed(error: error)
                }
            }
        }
    }

    func finishRecording() {

        synchronized(self) {
            guard writerStatus == .Recording else { return }
            writerStatus = .FinishingRecordingPart1
        }

        dispatch_async(writingQueue) {

            autoreleasepool {

                synchronized(self) {

                    // We may have transitioned to an error state as we appended inflight buffers. In that case there is nothing to do now.
                    guard self.writerStatus == .FinishingRecordingPart1 else { return }

                    // It is not safe to call -[AVAssetWriter finishWriting*] concurrently with -[AVAssetWriterInput appendSampleBuffer:]
                    // We transition to MovieRecorderStatusFinishingRecordingPart2 while on _writingQueue, which guarantees that no more buffers will be appended.
                    self.writerStatus = .FinishingRecordingPart2
                }

                self.assetWriter?.finishWritingWithCompletionHandler {

                    synchronized(self) {

                        if let error = self.assetWriter?.error {
                            self.writerStatus = .Failed(error: error)
                        } else {
                            self.writerStatus = .Finished
                        }
                    }

                }

            }

        }

    }

}

// MARK: Private Methods

extension AssetWriterCoordinator {

    private func appendSampleBuffer(sampleBuffer: CMSampleBufferRef, ofMediaType mediaType: String) {

        guard let assetWriter = assetWriter else { return }

        synchronized(self){

            if writerStatus.hashValue < WriterStatus.Recording.hashValue {
                print("Not ready to record yet")
                return
            }
        }

        dispatch_async(writingQueue) {

            autoreleasepool {

                synchronized(self) {
                    // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
                    // Because of this we are lenient when samples are appended and we are no longer recording.
                    // Instead of throwing an exception we just release the sample buffers and return.
                    if self.writerStatus.hashValue > WriterStatus.FinishingRecordingPart1.hashValue {
                        return
                    }
                }

                if !self.didStartedSession && mediaType == AVMediaTypeVideo {
                    assetWriter.startSessionAtSourceTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                    self.didStartedSession = true
                }

                guard let input = (mediaType == AVMediaTypeVideo ? self.videoInput : self.audioInput) where input.readyForMoreMediaData else { return }

                let success = input.appendSampleBuffer(sampleBuffer)

                if !success {
                    self.writerStatus = .Failed(error: assetWriter.error)
                }

            }
        }

    }

    private func setupAssetWriterVideoInput(withSourceFormatDescription videoFormatDescription: CMFormatDescriptionRef, settings videoSettings: [String: AnyObject]) {

        guard let assetWriter = self.assetWriter where assetWriter.canApplyOutputSettings(videoSettings, forMediaType: AVMediaTypeVideo) else { return }

        videoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings, sourceFormatHint: videoFormatDescription)
        videoInput?.expectsMediaDataInRealTime = true
        videoInput?.transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2)) // portrait orientation

        if assetWriter.canAddInput(videoInput!) {
            assetWriter.addInput(videoInput!)
        }

    }

    private func setupAssetWriterAudioInput(withSourceFormatDescription audioFormatDescription: CMFormatDescriptionRef, settings audioSettings: [String: AnyObject]) {

        guard let assetWriter = self.assetWriter where assetWriter.canApplyOutputSettings(audioSettings, forMediaType: AVMediaTypeAudio) else { return }

        audioInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioSettings, sourceFormatHint: audioFormatDescription)
        audioInput?.expectsMediaDataInRealTime = true

        if assetWriter.canAddInput(audioInput!) {
            assetWriter.addInput(audioInput!)
        }
    }

    private func removeExistingFile(byURL URL: NSURL) {
        let fileManager = NSFileManager.defaultManager()
        if let outputPath = self.URL.path where fileManager.fileExistsAtPath(outputPath) {
            let _ = try? fileManager.removeItemAtURL(self.URL)
        }
    }
}



