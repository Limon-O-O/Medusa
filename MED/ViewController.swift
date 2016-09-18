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

    fileprivate let maxTime: Float = 5.0
    fileprivate var totalSeconds: Float = 0.0

    fileprivate var filter: HighPassSkinSmoothingFilter?

    fileprivate var captureSessionCoordinator: CaptureSessionAssetWriterCoordinator?

    @IBOutlet fileprivate weak var progressView: ProgressView!
    @IBOutlet fileprivate weak var previewView: VideoPreviewView!
    @IBOutlet fileprivate weak var ringControl: RingControl!
    @IBOutlet fileprivate weak var rollbackButton: UIButton!
    @IBOutlet fileprivate weak var saveButton: UIButton!

    @IBOutlet weak var amountSlider: UISlider! {
        didSet {
            amountSlider.isHidden = true
            amountSlider.setThumbImage(UIImage(named: "slider_thumb"), for: UIControlState())
        }
    }

    fileprivate let attributes: Attributes = {

        let fileName = "video"
        let mediaFormat = MediaFormat.mp4
        let fileURL = FileManager.videoURLWithName(fileName, fileExtension: mediaFormat.filenameExtension)

        let videoDimensions = CMVideoDimensions(width: 640, height: 480)

        let codecSettings = [AVVideoAverageBitRateKey: 2000000, AVVideoMaxKeyFrameIntervalKey: 24]

        let videoCompressionSettings: [String: AnyObject] = [
            AVVideoCodecKey: AVVideoCodecH264 as AnyObject,
            AVVideoCompressionPropertiesKey: codecSettings as AnyObject,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill as AnyObject
        ]

        return Attributes(destinationURL: fileURL!, videoDimensions: videoDimensions, mediaFormat: mediaFormat, videoCompressionSettings: videoCompressionSettings)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        var cameraPermission: Bool = false

        AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo) { granted in
            DispatchQueue.main.async {
                cameraPermission = granted
            }
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard cameraPermission && granted else { return }
                self.cameraSetup()
            }
        }

        ringControl.toucheActions = { [weak self] status in

            guard let strongSelf = self, let captureSessionCoordinator = strongSelf.captureSessionCoordinator else { return }

            switch status {

            case .began:
                captureSessionCoordinator.startRecording()

            case .end:
                captureSessionCoordinator.pause()

            case .press:
                break
            }

        }
    }

    fileprivate func cameraSetup() {

        do {

            captureSessionCoordinator = try CaptureSessionAssetWriterCoordinator(sessionPreset: AVCaptureSessionPreset640x480, attributes: attributes)

            captureSessionCoordinator?.delegate = self

        } catch {

            print((error as NSError).localizedDescription)
        }

        guard let captureSessionCoordinator = captureSessionCoordinator else { return }

        previewView.cameraDevice = captureSessionCoordinator.captureDevice
        previewView.canvasContentMode = .scaleAspectFill

        captureSessionCoordinator.startRunning()
    }

    @IBAction func amountValueChanged(_ sender: UISlider) {
        filter?.inputAmount = sender.value
        print("amountValue: \(sender.value)")
    }

    @IBAction fileprivate func skinSmooth(_ sender: UIButton) {

        filter = !sender.isSelected ? HighPassSkinSmoothingFilter() : nil
        amountSlider.value = amountSlider.value == 0.0 ? Float(filter?.inputAmount ?? 0.0) : amountSlider.value
        filter?.inputAmount = amountSlider.value

        amountSlider.isHidden = !amountSlider.isHidden
        sender.isSelected = !sender.isSelected
    }

    @IBAction fileprivate func swapCameraDevicePosition(_ sender: UIButton) {
        try! captureSessionCoordinator?.swapCaptureDevicePosition()
    }

    @IBAction fileprivate func rollbackAction(_ sender: UIButton) {

        if sender.isSelected {

            let delta = progressView.rollback()

            totalSeconds = max(totalSeconds - (maxTime * delta), 0.0)

            print("totalSeconds \(totalSeconds) (maxTime * delta) \((maxTime * delta))")

            if progressView.trackViews.isEmpty {
                rollbackButton.isHidden = true
                saveButton.isHidden = true
                totalSeconds = 0.0
            }

            // delete the lastest video
            captureSessionCoordinator?.removeLastSegment()

        } else {

            progressView.trackViews.last?.backgroundColor = UIColor.brown

        }

        sender.isSelected = !sender.isSelected

    }

    @IBAction fileprivate func saveAction(_ sender: UIButton) {
        resetProgressView()
        captureSessionCoordinator?.stopRecording()
    }

    fileprivate func resetProgressView() {
        progressView.status = .idle
        totalSeconds = 0.0
    }

}


// MARK: - CaptureSessionCoordinatorDelegate

extension ViewController: CaptureSessionCoordinatorDelegate {

    func coordinatorVideoDataOutput(didOutputSampleBuffer sampleBuffer: CMSampleBuffer, completionHandler: ((CIImage) -> Void)) {

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var outputImage = CIImage(cvPixelBuffer: imageBuffer)

        if let filter = filter {
            filter.inputImage = outputImage
            if let newOutputImage = filter.outputImage {
                outputImage = newOutputImage
            }
        }

        DispatchQueue.main.sync(execute: {
            self.previewView.image = outputImage
        })

        completionHandler(outputImage)
    }

    func coordinatorWillBeginRecording(_ coordinator: CaptureSessionCoordinator) {}

    func coordinatorDidRecording(_ coordinator: CaptureSessionCoordinator, seconds: Float) {

        print("\(Int(seconds / 60)):\(seconds.truncatingRemainder(dividingBy: 60))")

        let totalTimeBuffer = totalSeconds + seconds

        if totalTimeBuffer > maxTime {
            self.captureSessionCoordinator?.stopRecording()
            resetProgressView()
            return
        }

        progressView.progress = totalTimeBuffer / maxTime
    }

    func coordinatorWillPauseRecording(_ coordinator: CaptureSessionCoordinator) {

        progressView.pause()

        rollbackButton.isHidden = false
        saveButton.isHidden = false
    }

    func coordinatorDidPauseRecording(_ coordinator: CaptureSessionCoordinator, segments: [Segment]) {
        let seconds = segments.last?.seconds ?? 0.0
        totalSeconds += seconds
    }

    func coordinatorDidBeginRecording(_ coordinator: CaptureSessionCoordinator) {

        switch progressView.status {
        case .pause:
            progressView.resume()
        case .progressing, .idle:
            break
        }

        rollbackButton.isHidden = true
        saveButton.isHidden = true

        rollbackButton.isSelected = false
        progressView.trackViews.last?.backgroundColor = progressView.progressTintColor
    }

    func coordinator(_ coordinator: CaptureSessionCoordinator, didFinishRecordingToOutputFileURL outputFileURL: URL?, error: NSError?) {

        guard error == nil else {
            print("\((#file as NSString).lastPathComponent)[\(#line)], \(#function): \(error?.localizedDescription)")
            resetProgressView()
            return
        }

        guard let outputFileURL = outputFileURL else { return }

        let videoAsset = AVURLAsset(url: outputFileURL, options: nil)
        let videoDuration = Int(CMTimeGetSeconds(videoAsset.duration) as Double)

        print("didFinishRecording fileSize: \(fileSize(outputFileURL)) M, \(videoDuration) seconds")

        saveVideoToPhotosAlbum(outputFileURL)
    }
}


// MARK: - Private Methods

extension ViewController {

    fileprivate func saveVideoToPhotosAlbum(_ fileURL: URL) {

        let assetsLibrary = ALAssetsLibrary()

        assetsLibrary.writeVideoAtPath(toSavedPhotosAlbum: fileURL) { URL, error in

            if error != nil {
                print("Save error: \(error?.localizedDescription)")
                return
            }

            print("Saved to PhotosAlbum Successfully")

            FileManager.removeVideoFileWithFileURL(fileURL)
        }
    }

    fileprivate func fileSize(_ fileURL: URL) -> Double {
        return Double((try? Data(contentsOf: fileURL))?.count ?? 0)/(1024.00*1024.0)
    }
}

