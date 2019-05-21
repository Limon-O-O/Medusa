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
import Photos
//import Picasso
//import Lady

extension NSLayoutConstraint {

    static func setMultiplier(_ multiplier: CGFloat, of constraint: inout NSLayoutConstraint) {
        NSLayoutConstraint.deactivate([constraint])

        let newConstraint = NSLayoutConstraint(item: constraint.firstItem!, attribute: constraint.firstAttribute, relatedBy: constraint.relation, toItem: constraint.secondItem!, attribute: constraint.secondAttribute, multiplier: multiplier, constant: 0.0)

        newConstraint.priority = constraint.priority
        newConstraint.shouldBeArchived = constraint.shouldBeArchived
        newConstraint.identifier = constraint.identifier

        NSLayoutConstraint.activate([newConstraint])
        constraint = newConstraint
    }

}

class ViewController: UIViewController {

    fileprivate let maxTime: Float = 5.0
    fileprivate var totalSeconds: Float = 0.0

//    fileprivate var filter: HighPassSkinSmoothingFilter?

    fileprivate var captureSessionCoordinator: CaptureSessionAssetWriterCoordinator?
    @IBOutlet private weak var previewConstraintRatioHeight: NSLayoutConstraint!

    @IBOutlet fileprivate weak var progressView: ProgressView!
    @IBOutlet fileprivate weak var previewView: VideoPreviewView!
    @IBOutlet fileprivate weak var ringControl: RingControl!
    @IBOutlet fileprivate weak var rollbackButton: UIButton!
    @IBOutlet fileprivate weak var saveButton: UIButton!

    @IBOutlet weak var amountSlider: UISlider! {
        didSet {
            amountSlider.isHidden = true
//            amountSlider.setThumbImage(UIImage(named: "slider_thumb"), for: UIControlState())
        }
    }

    fileprivate var attributes: Attributes = {

        let fileName = "video"
        let mediaFormat = MediaFormat.mp4
        let fileURL = FileManager.videoURLWithName(fileName, fileExtension: mediaFormat.filenameExtension)

        let videoDimensions = CMVideoDimensions(width: 480, height: 480)

        let numPixels = videoDimensions.width * videoDimensions.height
        // 每像素比特
        let bitsPerPixel: Int32 = 6
        let bitsPerSecond = numPixels * bitsPerPixel
        // AVVideoAverageBitRateKey: 可变码率
        let codecSettings = [AVVideoAverageBitRateKey: bitsPerSecond, AVVideoMaxKeyFrameIntervalKey: 24]

        let videoCompressionSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoCompressionPropertiesKey: codecSettings,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill
        ]

        return Attributes(destinationURL: fileURL!, videoDimensions: videoDimensions, mediaFormat: mediaFormat, videoCompressionSettings: videoCompressionSettings)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        let ratio = CGFloat(attributes.videoDimensions.height) / CGFloat(attributes.videoDimensions.width)
        NSLayoutConstraint.setMultiplier(ratio, of: &previewConstraintRatioHeight)

        previewView.backgroundColor = UIColor.red

        AVCaptureDevice.requestAccess(for: AVMediaType.video) { granted in
            let cameraPermission = granted
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    print("cameraPermission \(cameraPermission) \(granted)")
                    guard cameraPermission && granted else { return }
                    self.cameraSetup()
                }
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(deviceRotated), name: UIDevice.orientationDidChangeNotification, object: nil)

        ringControl.toucheActions = { [weak self] status in
            guard let strongSelf = self, let captureSessionCoordinator = strongSelf.captureSessionCoordinator else { return }
            switch status {
            case .began:
                captureSessionCoordinator.startRecording(videoDimensions: strongSelf.attributes.videoDimensions, deviceOrientation: strongSelf.attributes.deviceOrientation)
            case .end:
                captureSessionCoordinator.pause()
            case .press:
                break
            }
        }
    }

    @objc private func deviceRotated() {

        let action: (UIDeviceOrientation) -> Void = { [weak self] orientation in
            guard let sSelf = self else { return }

            let videoDimensions: CMVideoDimensions
            let ratio: CGFloat
            switch orientation {
            case .landscapeRight, .landscapeLeft:
                // 9比16，横屏拍摄的时候，保证写入的视频和预览的时候一致，同时调整 assetWriterInput.transform 保证横屏显示
                videoDimensions = CMVideoDimensions(width: 360, height: 640)
                ratio = CGFloat(sSelf.view.frame.height) / CGFloat(sSelf.view.frame.width)
            default:
                videoDimensions = CMVideoDimensions(width: 480, height: 480)
                ratio = CGFloat(videoDimensions.height) / CGFloat(videoDimensions.width)
            }

            sSelf.attributes.videoDimensions = videoDimensions
            sSelf.attributes.deviceOrientation = orientation

            NSLayoutConstraint.setMultiplier(ratio, of: &sSelf.previewConstraintRatioHeight)
            UIView.animate(withDuration: 0.2) { [weak sSelf] in
                guard let ssSelf = sSelf else { return }
                ssSelf.view.layoutIfNeeded()
            }
        }

        switch UIDevice.current.orientation {
        case .landscapeLeft:
            guard attributes.deviceOrientation != .landscapeLeft else { return }
            action(.landscapeLeft)
            print("landscape Left \(self.previewView.frame)")

        case .landscapeRight:
            guard attributes.deviceOrientation != .landscapeRight else { return }
            action(.landscapeRight)
            print("landscape Right \(self.previewView.frame)")

        default:
            guard attributes.deviceOrientation != .portrait else { return }
            action(.portrait)
            print("other \(self.previewView.frame)")
        }
        print()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print(previewView.frame)
    }

    fileprivate func cameraSetup() {
        do {
            captureSessionCoordinator = try CaptureSessionAssetWriterCoordinator(sessionPreset: AVCaptureSession.Preset.vga640x480, attributes: attributes, position: .front)
            captureSessionCoordinator?.delegate = self
        } catch {
            print("cameraSetup error: \(error.localizedDescription)")
        }

        guard let captureSessionCoordinator = captureSessionCoordinator else { return }

        previewView.cameraDevice = captureSessionCoordinator.captureDevice
        previewView.canvasContentMode = .scaleAspectFill

        captureSessionCoordinator.startRunning()
        print("startRunning success")
    }

    @IBAction func amountValueChanged(_ sender: UISlider) {
//        filter?.inputAmount = sender.value
        print("amountValue: \(sender.value)")
    }

    @IBAction fileprivate func skinSmooth(_ sender: UIButton) {

//        filter = !sender.isSelected ? HighPassSkinSmoothingFilter() : nil
//        amountSlider.value = amountSlider.value == 0.0 ? Float(filter?.inputAmount ?? 0.0) : amountSlider.value
//        filter?.inputAmount = amountSlider.value
//
//        amountSlider.isHidden = !amountSlider.isHidden
//        sender.isSelected = !sender.isSelected
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

    func coordinatorVideoDataOutput(didOutputSampleBuffer sampleBuffer: CMSampleBuffer, completionHandler: ((CMSampleBuffer, CIImage?) -> Void)) {

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
//
//        var outputImage = CIImage(cvPixelBuffer: imageBuffer)
//
//        if let filter = filter {
//            filter.inputImage = outputImage
//            if let newOutputImage = filter.outputImage {
//                outputImage = newOutputImage
//            }
//        }
//
//        DispatchQueue.main.sync(execute: {
//        })

//        let height = CGFloat(CVPixelBufferGetHeight(imageBuffer))
//        let width = CGFloat(CVPixelBufferGetWidth(imageBuffer))
//        print(width, height)

        self.previewView.pixelBuffer = imageBuffer
        completionHandler(sampleBuffer, nil)
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

    func coordinator(_ coordinator: CaptureSessionCoordinator, didFinishRecordingToOutputFileURL outputFileURL: URL?, error: Error?) {

        ringControl.touchStatus = .end

        guard error == nil else {
            print("\((#file as NSString).lastPathComponent)[\(#line)], \(#function): \(error?.localizedDescription ?? "")")
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
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }, completionHandler: { (success, error) in
            if success {
                print("Saved to PhotosAlbum Successfully")
                FileManager.removeVideoFileWithFileURL(fileURL)
            } else {
                print("Save error: \(String(describing: error?.localizedDescription))")
            }
        })
    }

    fileprivate func fileSize(_ fileURL: URL) -> Double {
        return Double((try? Data(contentsOf: fileURL))?.count ?? 0)/(1024.00*1024.0)
    }
}

