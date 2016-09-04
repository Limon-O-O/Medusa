//
//  ViewController.swift
//  MED
//
//  Created by Limon on 6/16/16.
//  Copyright © 2016 MED. All rights reserved.
//
import UIKit
import AVFoundation
import AssetsLibrary
import Medusa
import Picasso
import Lady

class ViewController: UIViewController {

    private let maxTime: Float = 5.0
    private var totalSeconds: Float = 0.0

    private var filter: HighPassSkinSmoothingFilter?

    private var captureSessionCoordinator: CaptureSessionAssetWriterCoordinator?

    @IBOutlet private weak var progressView: ProgressView!
    @IBOutlet private weak var previewView: VideoPreviewView!
    @IBOutlet private weak var ringControl: RingControl!
    @IBOutlet private weak var rollbackButton: UIButton!
    @IBOutlet private weak var saveButton: UIButton!

    @IBOutlet weak var amountSlider: UISlider! {
        didSet {
            amountSlider.setThumbImage(UIImage(named: "slider_thumb"), forState: .Normal)
        }
    }

    private let attributes: Attributes = {

        let fileName = "video"
        let mediaFormat = MediaFormat.MP4
        let fileURL = NSFileManager.videoURLWithName(fileName, fileExtension: mediaFormat.filenameExtension)

        let videoDimensions = CMVideoDimensions(width: 640, height: 480)

        let codecSettings = [AVVideoAverageBitRateKey: 2000000, AVVideoMaxKeyFrameIntervalKey: 24]

        let videoCompressionSettings: [String: AnyObject] = [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoCompressionPropertiesKey: codecSettings,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill
        ]

        return Attributes(destinationURL: fileURL!, videoDimensions: videoDimensions, mediaFormat: mediaFormat, videoCompressionSettings: videoCompressionSettings)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        var cameraPermission: Bool = false

        AVCaptureDevice.requestAccessForMediaType(AVMediaTypeVideo) { granted in
            dispatch_async(dispatch_get_main_queue()) {
                cameraPermission = granted
            }
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            dispatch_async(dispatch_get_main_queue()) {
                guard cameraPermission && granted else { return }
                self.cameraSetup()
            }
        }

        ringControl.toucheActions = { [weak self] status in

            guard let strongSelf = self, captureSessionCoordinator = strongSelf.captureSessionCoordinator else { return }

            switch status {

            case .Began:
                break

            case .End:
                captureSessionCoordinator.pause()

            case .Press:
                captureSessionCoordinator.startRecording()

            }

        }
    }

    private func cameraSetup() {

        do {

            captureSessionCoordinator = try CaptureSessionAssetWriterCoordinator(sessionPreset: AVCaptureSessionPreset640x480, attributes: attributes)

            captureSessionCoordinator?.delegate = self

        } catch {

            print((error as NSError).localizedDescription)
        }

        guard let captureSessionCoordinator = captureSessionCoordinator else { return }

        previewView.cameraDevice = captureSessionCoordinator.captureDevice
        previewView.canvasContentMode = .ScaleAspectFill

        captureSessionCoordinator.startRunning()
    }

    @IBAction func amountValueChanged(sender: UISlider) {
        filter?.inputAmount = CGFloat(sender.value)
        print("amountValue: \(sender.value)")
    }

    @IBAction private func skinSmooth(sender: UIButton) {

        filter = !sender.selected ? HighPassSkinSmoothingFilter() : nil
        amountSlider.value = Float(filter?.inputAmount ?? 0.0)

        sender.selected = !sender.selected
    }

    @IBAction private func swapCameraDevicePosition(sender: UIButton) {
        try! captureSessionCoordinator?.swapCaptureDevicePosition()
    }

    @IBAction private func rollbackAction(sender: UIButton) {

        if sender.selected {

            let delta = progressView.rollback()

            totalSeconds -= (maxTime * delta)

            if progressView.trackViews.isEmpty {
                rollbackButton.hidden = true
                saveButton.hidden = true
            }

            // delete the lastest video
            captureSessionCoordinator?.removeLastSegment()

        } else {

            progressView.trackViews.last?.backgroundColor = UIColor.brownColor()

        }

        sender.selected = !sender.selected

    }

    @IBAction private func saveAction(sender: UIButton) {
        resetProgressView()
        captureSessionCoordinator?.stopRecording()
    }

    private func resetProgressView() {
        progressView.status = .Idle
        totalSeconds = 0.0
    }

}


// MARK: - CaptureSessionCoordinatorDelegate

extension ViewController: CaptureSessionCoordinatorDelegate {

    func coordinatorVideoDataOutput(didOutputSampleBuffer sampleBuffer: CMSampleBuffer, completionHandler: ((CIImage) -> Void)) {

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var outputImage = CIImage(CVPixelBuffer: imageBuffer)

        if let filter = filter {
            filter.setValue(outputImage, forKey: kCIInputImageKey)
            if let newOutputImage = filter.outputImage {
                outputImage = newOutputImage
            }
        }

        dispatch_sync(dispatch_get_main_queue(), {
            self.previewView.image = outputImage
        })

        completionHandler(outputImage)
    }

    func coordinatorWillBeginRecording(coordinator: CaptureSessionCoordinator) {}

    func coordinatorDidRecording(coordinator: CaptureSessionCoordinator, seconds: Float) {

        print("\(Int(seconds / 60)):\(seconds % 60)")

        let totalTimeBuffer = totalSeconds + seconds

        if totalTimeBuffer > maxTime {
            self.captureSessionCoordinator?.stopRecording()
            resetProgressView()
            return
        }

        progressView.progress = totalTimeBuffer / maxTime
    }

    func coordinatorWillPauseRecording(coordinator: CaptureSessionCoordinator) {

        progressView.pause()

        rollbackButton.hidden = false
        saveButton.hidden = false
    }

    func coordinatorDidPauseRecording(coordinator: CaptureSessionCoordinator, segments: [Segment]) {
        let seconds = segments.last?.seconds ?? 0.0
        totalSeconds += seconds
    }

    func coordinatorDidBeginRecording(coordinator: CaptureSessionCoordinator) {

        switch progressView.status {
        case .Pause:
            progressView.resume()
        case .Progressing, .Idle:
            break
        }

        rollbackButton.hidden = true
        saveButton.hidden = true

        rollbackButton.selected = false
        progressView.trackViews.last?.backgroundColor = progressView.progressTintColor
    }

    func coordinator(coordinator: CaptureSessionCoordinator, didFinishRecordingToOutputFileURL outputFileURL: NSURL?, error: NSError?) {

        guard error == nil else {
            print("\((#file as NSString).lastPathComponent)[\(#line)], \(#function): \(error?.localizedDescription)")
            resetProgressView()
            return
        }

        guard let outputFileURL = outputFileURL else { return }

        let videoAsset = AVURLAsset(URL: outputFileURL, options: nil)
        let videoDuration = Int(CMTimeGetSeconds(videoAsset.duration) as Double)

        print("didFinishRecording fileSize: \(fileSize(outputFileURL)) M, \(videoDuration) seconds")

        saveVideoToPhotosAlbum(outputFileURL)
    }
}


// MARK: - Private Methods

extension ViewController {

    private func saveVideoToPhotosAlbum(fileURL: NSURL) {

        let assetsLibrary = ALAssetsLibrary()

        assetsLibrary.writeVideoAtPathToSavedPhotosAlbum(fileURL) { URL, error in

            if error != nil {
                print("Save error: \(error.localizedDescription)")
                return
            }

            print("Saved to PhotosAlbum Successfully")

            NSFileManager.removeVideoFileWithFileURL(fileURL)
        }
    }

    private func fileSize(fileURL: NSURL) -> Double {
        return Double(NSData(contentsOfURL: fileURL)?.length ?? 0)/(1024.00*1024.0)
    }
}

