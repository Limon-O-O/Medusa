//
//  AssetWriterCoordinator.swift
//  Medusa
//
//  Created by Limon on 6/14/16.
//  Copyright © 2016 Medusa. All rights reserved.
//

import AVFoundation

protocol AssetWriterCoordinatorDelegate: class {

    func writerCoordinatorDidFinishPreparing(_ coordinator: AssetWriterCoordinator)

    func writerCoordinatorDidFinishRecording(_ coordinator: AssetWriterCoordinator, seconds: Float)

    func writerCoordinatorDidRecording(_ coordinator: AssetWriterCoordinator, seconds: Float)

    func writerCoordinator(_ coordinator: AssetWriterCoordinator, didFailWithError error: NSError?)
}

func ==(lhs: WriterStatus, rhs: WriterStatus) -> Bool {
    return lhs.hashValue == rhs.hashValue
}

enum WriterStatus: Hashable {
    case idle
    case preparingToRecord
    case recording
    case finishingRecordingPart1    // waiting for inflight buffers to be appended
    case finishingRecordingPart2    // calling finish writing on the asset writer
    case finished                   // terminal state
    case failed(error: NSError?)     // terminal state

    var hashValue: Int {
        switch self {
        case .idle:
            return 10000
        case .preparingToRecord:
            return 20000
        case .recording:
            return 30000
        case .finishingRecordingPart1:
            return 40000
        case .finishingRecordingPart2:
            return 50000
        case .finished:
            return 60000
        case .failed:
            return 70000

        }
    }
}

class AssetWriterCoordinator {

    var URL: Foundation.URL

    weak var delegate: AssetWriterCoordinatorDelegate?

    private let outputFileType: String

    fileprivate let writingQueue: DispatchQueue

    fileprivate var assetWriter: AVAssetWriter?

    fileprivate var assetWriterPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var videoTrackSettings: [String: AnyObject]?
    private var audioTrackSettings: [String: AnyObject]?

    fileprivate var assetWriterVideoInput: AVAssetWriterInput?
    fileprivate var assetWriterAudioInput: AVAssetWriterInput?

    private weak var videoTrackSourceFormatDescription: CMFormatDescription?
    private weak var audioTrackSourceFormatDescription: CMFormatDescription?

    fileprivate var didStartedSession = false

    fileprivate lazy var context: CIContext = {
        let eaglContext = EAGLContext(api: .openGLES2)
        let options = [kCIContextWorkingColorSpace: NSNull()]
        return CIContext(eaglContext: eaglContext!, options: options)
    }()

    fileprivate let genericRGBColorspace = CGColorSpaceCreateDeviceRGB()

    fileprivate var currentTimeStamp: CMTime = kCMTimeZero

    fileprivate var wrtingStartTime: CMTime = kCMTimeZero

    fileprivate var recordingSeconds: Float {
        let diff = CMTimeSubtract(currentTimeStamp, wrtingStartTime)
        let seconds = CMTimeGetSeconds(diff)
        return Float(seconds)
    }

    fileprivate var writerStatus: WriterStatus = .idle {

        willSet(newStatus) {

            guard newStatus != writerStatus else { return }

            let clearAction = {
                self.assetWriter = nil
                self.assetWriterVideoInput = nil
                self.assetWriterAudioInput = nil
                self.assetWriterPixelBufferAdaptor = nil
            }

            DispatchQueue.main.async {

                autoreleasepool {

                    switch newStatus {

                    case .failed(let error):

                        clearAction()
                        FileManager.med_removeExistingFile(at: self.URL)

                        self.delegate?.writerCoordinator(self, didFailWithError: error)

                    case .finished:
                        clearAction()
                        self.delegate?.writerCoordinatorDidFinishRecording(self, seconds: self.recordingSeconds)

                    case .recording:
                        self.delegate?.writerCoordinatorDidFinishPreparing(self)

                    default:
                        break
                    }
                }

            }
        }
    }

    init(URL: Foundation.URL, fileType outputFileType: String) {
        self.URL = URL
        self.writingQueue = DispatchQueue(label: "top.limon.assetwriter.writing", attributes: [])
        self.outputFileType = outputFileType
    }

    deinit {
        print("AssetWriterCoordinator Deinit")
    }

    func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer, outputImage: CIImage) {
        appendSampleBuffer(sampleBuffer, outputImage: outputImage, ofMediaType: AVMediaTypeVideo)
    }

    func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        appendSampleBuffer(sampleBuffer, outputImage: nil, ofMediaType: AVMediaTypeAudio)
    }

    func addAudioTrackWithSourceFormatDescription(_ formatDescription: CMFormatDescription, settings audioSettings: [String: AnyObject]) {

        objc_sync_enter(self)

        guard writerStatus == .idle else { return }

        audioTrackSourceFormatDescription = formatDescription

        audioTrackSettings = audioSettings

        objc_sync_exit(self)
    }

    func addVideoTrackWithSourceFormatDescription(_ formatDescription: CMFormatDescription, settings videoSettings: [String: AnyObject]) {

        objc_sync_enter(self)

        guard writerStatus == .idle else { return }

        videoTrackSourceFormatDescription = formatDescription

        videoTrackSettings = videoSettings

        objc_sync_exit(self)
    }

    func prepareToRecord() {

        objc_sync_enter(self)
        guard writerStatus == .idle else { return }
        writerStatus = .preparingToRecord
        objc_sync_exit(self)

        DispatchQueue.global(qos: DispatchQoS.QoSClass.utility).async {
            autoreleasepool {

                do {

                    // Remove file if necessary. AVAssetWriter will not overwrite an existing file.
                    FileManager.med_removeExistingFile(at: self.URL)

                    let assetWriter = try AVAssetWriter(outputURL: self.URL, fileType: self.outputFileType)
                    self.assetWriter = assetWriter

                    if let videoTrackSourceFormatDescription = self.videoTrackSourceFormatDescription, let videoTrackSettings = self.videoTrackSettings {

                        self.assetWriterVideoInput = self.makeAssetWriterVideoInput(withSourceFormatDescription: videoTrackSourceFormatDescription, settings: videoTrackSettings)

                        if let videoInput = self.assetWriterVideoInput {

                            let videoWidth = Int32(videoTrackSettings[AVVideoWidthKey] as! Int)
                            let videoHeight = Int32(videoTrackSettings[AVVideoHeightKey] as! Int)
                            let videoDimensions = CMVideoDimensions(width: videoWidth, height: videoHeight)

                            self.assetWriterPixelBufferAdaptor = self.makePixelBufferAdaptor(assetWriterInput: videoInput, videoDimensions: videoDimensions)

                            if assetWriter.canAdd(videoInput) {
                                assetWriter.add(videoInput)
                            }
                        }

                    }

                    if let audioTrackSourceFormatDescription = self.audioTrackSourceFormatDescription, let audioTrackSettings = self.audioTrackSettings {

                        let assetWriterAudioInput = self.makeAssetWriterAudioInput(withSourceFormatDescription: audioTrackSourceFormatDescription, settings: audioTrackSettings)

                        if let unwrappedAssetWriterAudioInput = assetWriterAudioInput , assetWriter.canAdd(unwrappedAssetWriterAudioInput) {
                            assetWriter.add(unwrappedAssetWriterAudioInput)
                            self.assetWriterAudioInput = unwrappedAssetWriterAudioInput
                        }
                    }

                    guard assetWriter.startWriting() else {
                        // `error` is non-nil when startWriting returns false.
                        throw assetWriter.error!
                    }

                    objc_sync_enter(self)
                    self.writerStatus = .recording
                    objc_sync_exit(self)

                } catch let error as NSError {
                    objc_sync_enter(self)
                    self.writerStatus = .failed(error: error)
                    objc_sync_exit(self)
                }
            }
        }
    }

    func finishRecording() {

        objc_sync_enter(self)
        guard writerStatus == .recording else { return }
        writerStatus = .finishingRecordingPart1
        objc_sync_exit(self)

        writingQueue.async {

            autoreleasepool {

                objc_sync_enter(self)
                // We may have transitioned to an error state as we appended inflight buffers. In that case there is nothing to do now.
                guard self.writerStatus == .finishingRecordingPart1 else { return }

                // It is not safe to call -[AVAssetWriter finishWriting*] concurrently with -[AVAssetWriterInput appendSampleBuffer:]
                // We transition to MovieRecorderStatusFinishingRecordingPart2 while on _writingQueue, which guarantees that no more buffers will be appended.
                self.writerStatus = .finishingRecordingPart2
                objc_sync_exit(self)

                self.assetWriter?.finishWriting {

                    objc_sync_enter(self)

                    if let error = self.assetWriter?.error {
                        print(error)
                        self.writerStatus = .failed(error: error as NSError?)
                    } else {
                        self.writerStatus = .finished
                    }

                    objc_sync_exit(self)
                }

            }

        }

    }

}

// MARK: - Private Methods

extension AssetWriterCoordinator {

    fileprivate func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, outputImage: CIImage?, ofMediaType mediaType: String) {

        guard let assetWriter = assetWriter, assetWriter.status == .writing else { return }

        if writerStatus.hashValue < WriterStatus.recording.hashValue {
            print("Not ready to record yet")
            return
        }

        writingQueue.async {

            autoreleasepool {

                // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
                // Because of this we are lenient when samples are appended and we are no longer recording.
                // Instead of throwing an exception we just release the sample buffers and return.
                if self.writerStatus.hashValue > WriterStatus.finishingRecordingPart1.hashValue {
                    return
                }

                var success: Bool?

                if mediaType == AVMediaTypeVideo {

                    guard let assetWriterPixelBufferAdaptor = self.assetWriterPixelBufferAdaptor, let pixelBufferPool = assetWriterPixelBufferAdaptor.pixelBufferPool, assetWriterPixelBufferAdaptor.assetWriterInput.isReadyForMoreMediaData else { return }

                    let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                    if !self.didStartedSession {
                        assetWriter.startSession(atSourceTime: timeStamp)
                        self.didStartedSession = true
                        self.wrtingStartTime = timeStamp
                    }

                    guard self.didStartedSession else { return }

                    var outputRenderBuffer: CVPixelBuffer?

                    let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputRenderBuffer)

                    if let pixelBuffer = outputRenderBuffer, status == 0 {

                        // Render 'image' to the given CVPixelBufferRef.
                        self.context.render(outputImage!, to: pixelBuffer, bounds: outputImage!.extent, colorSpace: self.genericRGBColorspace)

                        self.currentTimeStamp = timeStamp

                        success = assetWriterPixelBufferAdaptor.append(pixelBuffer, withPresentationTime: timeStamp)

//                        success = self.assetWriterVideoInput?.appendSampleBuffer(sampleBuffer)

                        self.delegate?.writerCoordinatorDidRecording(self, seconds: self.recordingSeconds)

                    } else {
                        print("Unable to obtain a pixel buffer from the pool.")
                    }

                } else if mediaType == AVMediaTypeAudio && self.didStartedSession {

                    guard let assetWriterAudioInput = self.assetWriterAudioInput, assetWriterAudioInput.isReadyForMoreMediaData else { return }

                    success = assetWriterAudioInput.append(sampleBuffer)
                }

                objc_sync_enter(self)
                if let unwrappedSuccess = success, !unwrappedSuccess {
                    self.writerStatus = .failed(error: assetWriter.error as NSError?)
                    print(assetWriter.error)
                }
                objc_sync_exit(self)

            }
        }
    }

    fileprivate func makePixelBufferAdaptor(assetWriterInput input: AVAssetWriterInput, videoDimensions: CMVideoDimensions) -> AVAssetWriterInputPixelBufferAdaptor {

        let pixelBufferWidth = min(videoDimensions.height, videoDimensions.width)
        let pixelBufferHeight = max(videoDimensions.height, videoDimensions.width)

        // Use BGRA for the video in order to get realtime encoding.
        let sourcePixelBufferAttributes: [String: AnyObject] = [
            String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA) as AnyObject,
            String(kCVPixelBufferWidthKey): Int(pixelBufferWidth) as AnyObject,
            String(kCVPixelBufferHeightKey): Int(pixelBufferHeight) as AnyObject,
            String(kCVPixelFormatOpenGLESCompatibility): kCFBooleanTrue
        ]

        return AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
    }

    fileprivate func makeAssetWriterVideoInput(withSourceFormatDescription videoFormatDescription: CMFormatDescription, settings videoSettings: [String: AnyObject]) -> AVAssetWriterInput? {

        guard let assetWriter = self.assetWriter, assetWriter.canApply(outputSettings: videoSettings, forMediaType: AVMediaTypeVideo) else { return nil }

        let videoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings, sourceFormatHint: videoFormatDescription)

        videoInput.expectsMediaDataInRealTime = true

        // videoConnection.videoOrientation = .Portrait, so videoInput.transform = CGAffineTransformIdentity
        videoInput.transform = CGAffineTransform.identity

        return videoInput
    }

    fileprivate func makeAssetWriterAudioInput(withSourceFormatDescription audioFormatDescription: CMFormatDescription, settings audioSettings: [String: AnyObject]) -> AVAssetWriterInput? {

        guard let assetWriter = self.assetWriter, assetWriter.canApply(outputSettings: audioSettings, forMediaType: AVMediaTypeAudio) else { return nil }

        let audioInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioSettings, sourceFormatHint: audioFormatDescription)
        audioInput.expectsMediaDataInRealTime = true

        return audioInput
    }
}

