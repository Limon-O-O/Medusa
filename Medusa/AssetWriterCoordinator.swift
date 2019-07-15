//
//  AssetWriterCoordinator.swift
//  Medusa
//
//  Created by Limon on 6/14/16.
//  Copyright © 2016 Medusa. All rights reserved.
//

import AVFoundation

public protocol AssetWriterCoordinatorDelegate: class {

    func writerCoordinatorDidFinishPreparing(_ coordinator: AssetWriterCoordinator)

    func writerCoordinatorDidFinishRecording(_ coordinator: AssetWriterCoordinator, seconds: Float)

    func writerCoordinatorDidRecording(_ coordinator: AssetWriterCoordinator, seconds: Float)

    func writerCoordinator(_ coordinator: AssetWriterCoordinator, didFailWithError error: Error?)
}

enum WriterStatus: Equatable {
    case idle
    case preparingToRecord
    case recording
    case finishingRecordingPart1    // waiting for inflight buffers to be appended
    case finishingRecordingPart2    // calling finish writing on the asset writer
    case finished                   // terminal state
    case failed(error: Error?)     // terminal state

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

    static func ==(lhs: WriterStatus, rhs: WriterStatus) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
}

public class AssetWriterCoordinator {

    var URL: Foundation.URL

    public weak var delegate: AssetWriterCoordinatorDelegate?

    private let outputFileType: AVFileType

    private let writingQueue: DispatchQueue

    private var assetWriter: AVAssetWriter?

    private var assetWriterPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var videoTrackSettings: [String: Any]?
    private var audioTrackSettings: [String: Any]?

    private var assetWriterVideoInput: AVAssetWriterInput?
    private var assetWriterAudioInput: AVAssetWriterInput?

    private var didStartedSession = false

    private lazy var context: CIContext = {
        let eaglContext = EAGLContext(api: .openGLES2)
        let options = [CIContextOption.workingColorSpace: NSNull()]
        return CIContext(eaglContext: eaglContext!, options: options)
    }()

    private let genericRGBColorspace = CGColorSpaceCreateDeviceRGB()

    private var currentTimeStamp: CMTime = CMTime.zero

    private var wrtingStartTime: CMTime = CMTime.zero

    private var recordingSeconds: Float {
        let diff = CMTimeSubtract(currentTimeStamp, wrtingStartTime)
        let seconds = CMTimeGetSeconds(diff)
        return Float(seconds)
    }

    private var writerStatus: WriterStatus = .idle {

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
                        FileManager.med.removeExistingFile(at: self.URL)

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

    public init(URL: Foundation.URL, fileType outputFileType: AVFileType) {
        self.URL = URL
        self.writingQueue = DispatchQueue(label: "top.limon.assetwriter.writing", attributes: [])
        self.outputFileType = outputFileType
    }

    deinit {
        med_print("AssetWriterCoordinator Deinit")
    }

    public func appendVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer, outputImage: CIImage?) {
        appendSampleBuffer(sampleBuffer, outputImage: outputImage, ofMediaType: AVMediaType.video)
    }

    public func appendAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        appendSampleBuffer(sampleBuffer, outputImage: nil, ofMediaType: AVMediaType.audio)
    }

    public func addAudioTrack(with audioSettings: [String: Any]) {

        objc_sync_enter(self)

        guard writerStatus == .idle else { return }

        audioTrackSettings = audioSettings

        objc_sync_exit(self)
    }

    public func addVideoTrack(with videoSettings: [String: Any]) {

        objc_sync_enter(self)

        guard writerStatus == .idle else { return }

        videoTrackSettings = videoSettings

        objc_sync_exit(self)
    }

    public func prepareToRecord(devicePosition: AVCaptureDevice.Position, deviceOrientation: UIDeviceOrientation) {

        objc_sync_enter(self)
        guard writerStatus == .idle else { return }
        writerStatus = .preparingToRecord
        objc_sync_exit(self)

        DispatchQueue.global(qos: DispatchQoS.QoSClass.utility).async {
            autoreleasepool {

                do {

                    // Remove file if necessary. AVAssetWriter will not overwrite an existing file.
                    FileManager.med.removeExistingFile(at: self.URL)

                    let assetWriter = try AVAssetWriter(outputURL: self.URL, fileType: self.outputFileType)
                    self.assetWriter = assetWriter

                    if let videoTrackSettings = self.videoTrackSettings {

                        self.assetWriterVideoInput = self.makeAssetWriterVideoInput(settings: videoTrackSettings, devicePosition: devicePosition, deviceOrientation: deviceOrientation)

                        if let videoInput = self.assetWriterVideoInput {

                            let videoWidth = Int32(videoTrackSettings[AVVideoWidthKey] as! Int)
                            let videoHeight = Int32(videoTrackSettings[AVVideoHeightKey] as! Int)
                            let videoDimensions = CMVideoDimensions(width: videoWidth, height: videoHeight)

                            self.assetWriterPixelBufferAdaptor = self.makePixelBufferAdaptor(assetWriterInput: videoInput, videoDimensions: videoDimensions)

                            if assetWriter.canAdd(videoInput) {
                                assetWriter.add(videoInput)
                            }
                        } else {
                            throw MedusaError.generateAssetWriterInputfailed
                        }
                    }

                    if let audioTrackSettings = self.audioTrackSettings {

                        let assetWriterAudioInput = self.makeAssetWriterAudioInput(settings: audioTrackSettings)

                        if let unwrappedAssetWriterAudioInput = assetWriterAudioInput , assetWriter.canAdd(unwrappedAssetWriterAudioInput) {
                            assetWriter.add(unwrappedAssetWriterAudioInput)
                            self.assetWriterAudioInput = unwrappedAssetWriterAudioInput
                        }
                    }

                    guard assetWriter.startWriting() else {
                        // `error` is non-nil when startWriting returns false.
                        throw assetWriter.error ?? MedusaError.startWritingfailed
                    }

                    objc_sync_enter(self)
                    self.writerStatus = .recording
                    objc_sync_exit(self)

                } catch {
                    objc_sync_enter(self)
                    self.writerStatus = .failed(error: error)
                    objc_sync_exit(self)
                }
            }
        }
    }

    public func cancelRecording() {
        objc_sync_enter(self)
        guard writerStatus == .recording else { return }
        writerStatus = .idle
        objc_sync_exit(self)
        guard let assetWriter = assetWriter, assetWriter.status == .writing else { return }
        writingQueue.async { [weak assetWriter] in
            guard let sAssetWriter = assetWriter else { return }
            sAssetWriter.cancelWriting()
        }
    }

    public func finishRecording() {

        objc_sync_enter(self)
        guard let _ = assetWriter, writerStatus == .recording else { return }
        writerStatus = .finishingRecordingPart1
        objc_sync_exit(self)

        writingQueue.async { [weak self] in
            guard let sSelf = self else { return }

            autoreleasepool { [weak sSelf] in

                guard let ssSelf = sSelf else { return }

                objc_sync_enter(ssSelf)
                // We may have transitioned to an error state as we appended inflight buffers. In that case there is nothing to do now.
                guard ssSelf.writerStatus == .finishingRecordingPart1 else { return }

                // It is not safe to call -[AVAssetWriter finishWriting*] concurrently with -[AVAssetWriterInput appendSampleBuffer:]
                // We transition to MovieRecorderStatusFinishingRecordingPart2 while on _writingQueue, which guarantees that no more buffers will be appended.
                ssSelf.writerStatus = .finishingRecordingPart2
                objc_sync_exit(ssSelf)

                ssSelf.assetWriter?.finishWriting { [weak ssSelf] in
                    guard let sssSelf = ssSelf else { return }
                    objc_sync_enter(sssSelf)

                    if let error = sssSelf.assetWriter?.error {
                        sssSelf.writerStatus = .failed(error: error)
                    } else {
                        sssSelf.writerStatus = .finished
                    }

                    objc_sync_exit(sssSelf)
                }
            }
        }
    }

}

// MARK: - Private Methods

extension AssetWriterCoordinator {

    private func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, outputImage: CIImage?, ofMediaType mediaType: AVMediaType) {

        guard let assetWriter = assetWriter, assetWriter.status == .writing else { return }

        if writerStatus.hashValue < WriterStatus.recording.hashValue {
            med_print("Not ready to record yet")
            return
        }

        writingQueue.async { [weak self] in
            guard let sSelf = self else { return }

            autoreleasepool { [weak sSelf] in

                guard let ssSelf = sSelf else { return }

                // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
                // Because of this we are lenient when samples are appended and we are no longer recording.
                // Instead of throwing an exception we just release the sample buffers and return.
                if ssSelf.writerStatus.hashValue > WriterStatus.finishingRecordingPart1.hashValue {
                    return
                }

                var success: Bool?

                if mediaType == AVMediaType.video {

                    let timeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                    if !ssSelf.didStartedSession {
                        assetWriter.startSession(atSourceTime: timeStamp)
                        ssSelf.didStartedSession = true
                        ssSelf.wrtingStartTime = timeStamp
                    }

                    guard ssSelf.didStartedSession else { return }

                    if let image = outputImage,
                        let assetWriterPixelBufferAdaptor = ssSelf.assetWriterPixelBufferAdaptor,
                        let pixelBufferPool = assetWriterPixelBufferAdaptor.pixelBufferPool, assetWriterPixelBufferAdaptor.assetWriterInput.isReadyForMoreMediaData {

                        var outputRenderBuffer: CVPixelBuffer?

                        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &outputRenderBuffer)

                        if let pixelBuffer = outputRenderBuffer, status == 0 {

                            // Render 'image' to the given CVPixelBufferRef.
                            ssSelf.context.render(image, to: pixelBuffer, bounds: image.extent, colorSpace: ssSelf.genericRGBColorspace)

                            ssSelf.currentTimeStamp = timeStamp

                            success = assetWriterPixelBufferAdaptor.append(pixelBuffer, withPresentationTime: timeStamp)

                            ssSelf.delegate?.writerCoordinatorDidRecording(ssSelf, seconds: ssSelf.recordingSeconds)

                        } else {
                            med_print("Unable to obtain a pixel buffer from the pool.")
                        }
                    } else if let assetWriterVideoInput = ssSelf.assetWriterVideoInput {
                        ssSelf.currentTimeStamp = timeStamp
                        success = assetWriterVideoInput.append(sampleBuffer)
                        ssSelf.delegate?.writerCoordinatorDidRecording(ssSelf, seconds: ssSelf.recordingSeconds)
                    } else {
                        med_print("append buffer failed.")
                    }

                } else if mediaType == AVMediaType.audio && ssSelf.didStartedSession {

                    guard let assetWriterAudioInput = ssSelf.assetWriterAudioInput, assetWriterAudioInput.isReadyForMoreMediaData else { return }

                    success = assetWriterAudioInput.append(sampleBuffer)
                }

                objc_sync_enter(ssSelf)
                if let unwrappedSuccess = success, !unwrappedSuccess {
                    ssSelf.writerStatus = .failed(error: assetWriter.error)
                }
                objc_sync_exit(ssSelf)
            }
        }
    }

    private func makePixelBufferAdaptor(assetWriterInput input: AVAssetWriterInput, videoDimensions: CMVideoDimensions) -> AVAssetWriterInputPixelBufferAdaptor {

        let pixelBufferWidth = min(videoDimensions.height, videoDimensions.width)
        let pixelBufferHeight = max(videoDimensions.height, videoDimensions.width)

        // Use BGRA for the video in order to get realtime encoding.
        let sourcePixelBufferAttributes: [String: Any] = [
            String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA),
            String(kCVPixelBufferWidthKey): Int(pixelBufferWidth),
            String(kCVPixelBufferHeightKey): Int(pixelBufferHeight),
            String(kCVPixelFormatOpenGLESCompatibility): kCFBooleanTrue
        ]

        return AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
    }

    private func makeAssetWriterVideoInput(settings videoSettings: [String: Any], devicePosition: AVCaptureDevice.Position, deviceOrientation: UIDeviceOrientation) -> AVAssetWriterInput? {

        guard let assetWriter = self.assetWriter, assetWriter.canApply(outputSettings: videoSettings, forMediaType: AVMediaType.video) else { return nil }

        let videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoSettings)

        videoInput.expectsMediaDataInRealTime = true

        if let videoTrackSettings = self.videoTrackSettings,
            let videoWidth = videoTrackSettings[AVVideoWidthKey] as? Int,
            let videoHeight = videoTrackSettings[AVVideoHeightKey] as? Int {
            videoInput.naturalSize = CGSize(width: videoWidth, height: videoHeight)
        }

        // videoConnection.videoOrientation = .Portrait, so videoInput.transform = CGAffineTransformIdentity

        var angle: CGFloat = 0.0

        // 横屏拍摄的时候，保证写入的视频和预览的时候一致，调整 assetWriterInput.transform 保证横屏显示
        // 手机默认 landscapeLeft 拍摄，即 videoConnection.videoOrientation = .landscapeLeft
        // 考虑到读取视频文件需要取得正确宽高，简单的方法是不改变 videoOrientation，通过改变 preview 及 assetWriterInput 的 transform 来调整正确的方向
        switch devicePosition {
        case .front:
            angle = -90.0
            switch deviceOrientation {
            case .landscapeLeft:
                angle = 180.0
            case .landscapeRight:
                angle = 0.0
            default:
                break
            }
        case .back:
            angle = 90.0
            switch deviceOrientation {
            case .landscapeLeft:
                angle = 0.0
            case .landscapeRight:
                angle = 180.0
            default:
                break
            }
        default:
            break
        }

        let radians = angle / 180.0 * CGFloat.pi
        let rotation = CGAffineTransform.identity.rotated(by: radians)
        videoInput.transform = rotation

        return videoInput
    }

    private func makeAssetWriterAudioInput(settings audioSettings: [String: Any]) -> AVAssetWriterInput? {

        guard let assetWriter = self.assetWriter, assetWriter.canApply(outputSettings: audioSettings, forMediaType: AVMediaType.audio) else { return nil }

        let audioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        return audioInput
    }
}

