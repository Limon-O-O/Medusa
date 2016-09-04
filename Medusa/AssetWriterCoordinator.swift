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

    func writerCoordinatorDidFinishRecording(coordinator: AssetWriterCoordinator, seconds: Float)

    func writerCoordinatorDidRecording(coordinator: AssetWriterCoordinator, seconds: Float)

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

    var URL: NSURL

    weak var delegate: AssetWriterCoordinatorDelegate?

    private let outputFileType: String

    private let writingQueue: dispatch_queue_t

    private var assetWriter: AVAssetWriter?

    private var assetWriterPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var videoTrackSettings: [String: AnyObject]?
    private var audioTrackSettings: [String: AnyObject]?

    private var assetWriterVideoInput: AVAssetWriterInput?
    private var assetWriterAudioInput: AVAssetWriterInput?

    private weak var videoTrackSourceFormatDescription: CMFormatDescriptionRef?
    private weak var audioTrackSourceFormatDescription: CMFormatDescriptionRef?

    private var didStartedSession = false

    private lazy var context: CIContext = {
        let eaglContext = EAGLContext(API: .OpenGLES2)
        let options = [kCIContextWorkingColorSpace: NSNull()]
        return CIContext(EAGLContext: eaglContext, options: options)
    }()

    private let genericRGBColorspace = CGColorSpaceCreateDeviceRGB()

    private var currentTimeStamp: CMTime = kCMTimeZero

    private var wrtingStartTime: CMTime = kCMTimeZero

    private var recordingSeconds: Float {
        let diff = CMTimeSubtract(currentTimeStamp, wrtingStartTime)
        let seconds = CMTimeGetSeconds(diff)
        return Float(seconds)
    }

    private var writerStatus: WriterStatus = .Idle {

        willSet(newStatus) {

            guard newStatus != writerStatus else { return }

            let clearAction = {
                self.assetWriter = nil
                self.assetWriterVideoInput = nil
                self.assetWriterAudioInput = nil
                self.assetWriterPixelBufferAdaptor = nil
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
                        self.delegate?.writerCoordinatorDidFinishRecording(self, seconds: self.recordingSeconds)

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

    func appendVideoSampleBuffer(sampleBuffer: CMSampleBufferRef, outputImage: CIImage) {
        appendSampleBuffer(sampleBuffer, outputImage: outputImage, ofMediaType: AVMediaTypeVideo)
    }

    func appendAudioSampleBuffer(sampleBuffer: CMSampleBufferRef) {
        appendSampleBuffer(sampleBuffer, outputImage: nil, ofMediaType: AVMediaTypeAudio)
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

                    let assetWriter = try AVAssetWriter(URL: self.URL, fileType: self.outputFileType)
                    self.assetWriter = assetWriter

                    if let videoTrackSourceFormatDescription = self.videoTrackSourceFormatDescription, videoTrackSettings = self.videoTrackSettings {

                        self.assetWriterVideoInput = self.makeAssetWriterVideoInput(withSourceFormatDescription: videoTrackSourceFormatDescription, settings: videoTrackSettings)

                        if let videoInput = self.assetWriterVideoInput {

                            let videoWidth = Int32(videoTrackSettings[AVVideoWidthKey] as! Int)
                            let videoHeight = Int32(videoTrackSettings[AVVideoHeightKey] as! Int)
                            let videoDimensions = CMVideoDimensions(width: videoWidth, height: videoHeight)

                            self.assetWriterPixelBufferAdaptor = self.makePixelBufferAdaptor(assetWriterInput: videoInput, videoDimensions: videoDimensions)

                            if assetWriter.canAddInput(videoInput) {
                                assetWriter.addInput(videoInput)
                            }
                        }

                    }

                    if let audioTrackSourceFormatDescription = self.audioTrackSourceFormatDescription, audioTrackSettings = self.audioTrackSettings {

                        let assetWriterAudioInput = self.makeAssetWriterAudioInput(withSourceFormatDescription: audioTrackSourceFormatDescription, settings: audioTrackSettings)

                        if let unwrappedAssetWriterAudioInput = assetWriterAudioInput where assetWriter.canAddInput(unwrappedAssetWriterAudioInput) {
                            assetWriter.addInput(unwrappedAssetWriterAudioInput)
                            self.assetWriterAudioInput = unwrappedAssetWriterAudioInput
                        }
                    }

                    guard assetWriter.startWriting() else {
                        // `error` is non-nil when startWriting returns false.
                        throw assetWriter.error!
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

                self.assetWriter?.finishWritingWithCompletionHandler {

                    objc_sync_enter(self)

                    if let error = self.assetWriter?.error {
                        print(error)
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

// MARK: - Private Methods

extension AssetWriterCoordinator {

    private func appendSampleBuffer(sampleBuffer: CMSampleBufferRef, outputImage: CIImage?, ofMediaType mediaType: String) {

        guard let assetWriter = assetWriter where assetWriter.status == .Writing else { return }

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

                var success: Bool?

                if mediaType == AVMediaTypeVideo {

                    guard let assetWriterPixelBufferAdaptor = self.assetWriterPixelBufferAdaptor, pixelBufferPool = assetWriterPixelBufferAdaptor.pixelBufferPool where assetWriterPixelBufferAdaptor.assetWriterInput.readyForMoreMediaData else { return }

                    let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                    if !self.didStartedSession {
                        assetWriter.startSessionAtSourceTime(timeStamp)
                        self.didStartedSession = true
                        self.wrtingStartTime = timeStamp
                    }

                    guard self.didStartedSession else { return }

                    var outputRenderBuffer: CVPixelBuffer?

                    let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputRenderBuffer)

                    if let pixelBuffer = outputRenderBuffer where status == 0 {

                        // Render 'image' to the given CVPixelBufferRef.
                        self.context.render(outputImage!, toCVPixelBuffer: pixelBuffer, bounds: outputImage!.extent, colorSpace: self.genericRGBColorspace)

                        self.currentTimeStamp = timeStamp

                        success = assetWriterPixelBufferAdaptor.appendPixelBuffer(pixelBuffer, withPresentationTime: timeStamp)

//                        success = self.assetWriterVideoInput?.appendSampleBuffer(sampleBuffer)

                        self.delegate?.writerCoordinatorDidRecording(self, seconds: self.recordingSeconds)

                    } else {
                        print("Unable to obtain a pixel buffer from the pool.")
                    }

                } else if mediaType == AVMediaTypeAudio && self.didStartedSession {

                    guard let assetWriterAudioInput = self.assetWriterAudioInput where assetWriterAudioInput.readyForMoreMediaData else { return }

                    success = assetWriterAudioInput.appendSampleBuffer(sampleBuffer)
                }

                objc_sync_enter(self)
                if let unwrappedSuccess = success where !unwrappedSuccess {
                    self.writerStatus = .Failed(error: assetWriter.error)
                    print(assetWriter.error)
                }
                objc_sync_exit(self)

            }
        }
    }

    private func makePixelBufferAdaptor(assetWriterInput input: AVAssetWriterInput, videoDimensions: CMVideoDimensions) -> AVAssetWriterInputPixelBufferAdaptor {

        let pixelBufferWidth = min(videoDimensions.height, videoDimensions.width)
        let pixelBufferHeight = max(videoDimensions.height, videoDimensions.width)

        // Use BGRA for the video in order to get realtime encoding.
        let sourcePixelBufferAttributes: [String: AnyObject] = [
            String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA),
            String(kCVPixelBufferWidthKey): Int(pixelBufferWidth),
            String(kCVPixelBufferHeightKey): Int(pixelBufferHeight),
            String(kCVPixelFormatOpenGLESCompatibility): kCFBooleanTrue
        ]

        return AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
    }

    private func makeAssetWriterVideoInput(withSourceFormatDescription videoFormatDescription: CMFormatDescriptionRef, settings videoSettings: [String: AnyObject]) -> AVAssetWriterInput? {

        guard let assetWriter = self.assetWriter where assetWriter.canApplyOutputSettings(videoSettings, forMediaType: AVMediaTypeVideo) else { return nil }

        let videoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings, sourceFormatHint: videoFormatDescription)

        videoInput.expectsMediaDataInRealTime = true

        // videoConnection.videoOrientation = .Portrait, so videoInput.transform = CGAffineTransformIdentity
        videoInput.transform = CGAffineTransformIdentity

        return videoInput
    }

    private func makeAssetWriterAudioInput(withSourceFormatDescription audioFormatDescription: CMFormatDescriptionRef, settings audioSettings: [String: AnyObject]) -> AVAssetWriterInput? {

        guard let assetWriter = self.assetWriter where assetWriter.canApplyOutputSettings(audioSettings, forMediaType: AVMediaTypeAudio) else { return nil }

        let audioInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioSettings, sourceFormatHint: audioFormatDescription)
        audioInput.expectsMediaDataInRealTime = true

        return audioInput
    }
}

