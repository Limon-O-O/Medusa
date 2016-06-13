//
//  CaptureSessionAssetWriterCoordinator.swift
//  VideoRecorderExample
//
//  Created by Limon on 2016/6/13.
//  Copyright © 2016年 VideoRecorder. All rights reserved.
//

import AVFoundation

public final class CaptureSessionAssetWriterCoordinator: CaptureSessionCoordinator {

    private let videoDataOutput: AVCaptureVideoDataOutput
    private let audioDataOutput: AVCaptureAudioDataOutput

    private let videoConnection: AVCaptureConnection
    private let audioConnection: AVCaptureConnection

    private let videoCompressionSettings: [String: AnyObject]
    private let audioCompressionSettings: [NSObject: AnyObject]

    public init<T: UIViewController where T: CaptureSessionCoordinatorDelegate>(delegate: T, size: CGSize) throws {

        videoDataOutput = {
            $0.videoSettings = nil
            $0.alwaysDiscardsLateVideoFrames = false
            return $0
        }(AVCaptureVideoDataOutput())

        audioDataOutput = AVCaptureAudioDataOutput()

        videoConnection = videoDataOutput.connectionWithMediaType(AVMediaTypeVideo)
        audioConnection = videoDataOutput.connectionWithMediaType(AVMediaTypeAudio)

        let codecSettings = [AVVideoAverageBitRateKey: 2000000, AVVideoMaxKeyFrameIntervalKey: 1]

        videoCompressionSettings = [AVVideoCodecKey: AVVideoCodecH264, AVVideoCompressionPropertiesKey: codecSettings, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height]

        audioCompressionSettings = audioDataOutput.recommendedAudioSettingsForAssetWriterWithOutputFileType(AVFileTypeQuickTimeMovie)

        try super.init(delegate: delegate)

        try addOutput(videoDataOutput, toCaptureSession: captureSession)
        try addOutput(audioDataOutput, toCaptureSession: captureSession)

        let videoDataOutputQueue = dispatch_queue_create("top.limon.capturesession.videodata", DISPATCH_QUEUE_SERIAL)
        let audioDataOutputQueue = dispatch_queue_create("top.limon.capturesession.audiodata", DISPATCH_QUEUE_SERIAL)

        dispatch_set_target_queue(videoDataOutputQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0))

        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        audioDataOutput.setSampleBufferDelegate(self, queue: audioDataOutputQueue)
    }
}

extension CaptureSessionAssetWriterCoordinator {

    public override func startRecording() {
        synchronized(self) {

        }
    }

    public override func stopRecording() {

    }
}

extension CaptureSessionAssetWriterCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    public func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
    }
}
