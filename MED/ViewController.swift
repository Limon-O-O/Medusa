//
//  ViewController.swift
//  MED
//
//  Created by Limon on 6/16/16.
//  Copyright © 2016 MED. All rights reserved.
//
import UIKit
import AVFoundation
import Medusa
import AssetsLibrary


class ViewController: UIViewController {

    private let maxTime = 5.0
    private var currentTime: Int = 0
    private var timer: NSTimer?

    private var captureSessionCoordinator: CaptureSessionAssetWriterCoordinator?

    @IBOutlet private weak var hintLabel: UILabel!
    @IBOutlet private weak var progressView: UIView!
    @IBOutlet private weak var previewView: VideoPreviewView!
    @IBOutlet private weak var ringControl: RingControl!
    @IBOutlet private weak var progressViewConstraintWidth: NSLayoutConstraint!

    @IBOutlet private weak var countdownButton: UIButton! {
        didSet {
            countdownButton.alpha = 0.0
            countdownButton.userInteractionEnabled = false
            countdownButton.layer.masksToBounds = true
            countdownButton.layer.cornerRadius = countdownButton.frame.size.height / 2.0
        }
    }

    private let attributes: Attributes = {

        let fileName = "video"
        let fileURL = NSFileManager.videoURLWithName(fileName, fileExtension: ".mp4")

        let videoFinalSize = CGSize(width: 480, height: 640)

        let codecSettings = [AVVideoAverageBitRateKey: 2000000, AVVideoMaxKeyFrameIntervalKey: 24]

        let videoCompressionSettings: [String : AnyObject] = [
            AVVideoCodecKey: AVVideoCodecH264,
            AVVideoCompressionPropertiesKey: codecSettings,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoWidthKey: videoFinalSize.width,
            AVVideoHeightKey: videoFinalSize.height
        ]

        let audioCompressionSettings: [String : AnyObject] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000
        ]

        return Attributes(recordingURL: fileURL!, fileType: AVFileTypeMPEG4, videoCompressionSettings: videoCompressionSettings, audioCompressionSettings: audioCompressionSettings)
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

            guard let strongSelf = self else { return }

            switch status {

            case .Began:
                self?.captureSessionCoordinator?.startRecording(byAttributes: strongSelf.attributes)

            case .End:
                self?.captureSessionCoordinator?.stopRecording()

            case .Press:
                break
            }

        }
    }

    private func cameraSetup() {

        do {

            captureSessionCoordinator = try CaptureSessionAssetWriterCoordinator(sessionPreset: AVCaptureSessionPreset640x480)

            captureSessionCoordinator?.delegate = self

        } catch {

            print((error as NSError).localizedDescription)
        }

        guard let captureSessionCoordinator = captureSessionCoordinator else { return }

        previewView.previewLayer = captureSessionCoordinator.previewLayer

        previewView.cameraDevice = captureSessionCoordinator.captureDevice

        captureSessionCoordinator.startRunning()
    }

    @IBAction func swapCameraDevicePosition(sender: UIButton) {
        try! captureSessionCoordinator?.swapCaptureDevicePosition()
    }

}


// MARK: CaptureSessionCoordinatorDelegate

extension ViewController: CaptureSessionCoordinatorDelegate {

    func coordinatorWillBeginRecording(coordinator: CaptureSessionCoordinator) {
        showViews()
    }

    func coordinatorDidBeginRecording(coordinator: CaptureSessionCoordinator) {}

    func coordinator(coordinator: CaptureSessionCoordinator, didFinishRecordingToOutputFileURL outputFileURL: NSURL?, error: NSError?) {

        hideViews()

        guard error == nil else { print("error: \(error?.localizedDescription)"); return }

        guard let outputFileURL = outputFileURL else { return }

        let videoAsset = AVURLAsset(URL: outputFileURL, options: nil)
        let videoDuration = Int(CMTimeGetSeconds(videoAsset.duration) as Double)

        print("didFinishRecording fileSize: \(fileSize(outputFileURL)) M, \(videoDuration) seconds")

        saveVideoToPhotosAlbum(outputFileURL)
    }
}


// MARK: Views

extension ViewController {

    private func showViews() {
        showRecordProgressView()
        showCountdownButton()
        addTimer(timeInterval: 1.0)
    }

    private func hideViews() {
        currentTime = 0
        progressView.alpha = 0.0
        progressView.layer.removeAllAnimations()
        progressViewConstraintWidth.constant = 0.0
        timer?.invalidate()
    }

    private func showRecordProgressView() {

        progressView.alpha = 1.0

        progressViewConstraintWidth.constant = UIScreen.mainScreen().bounds.width

        UIView.animateWithDuration(maxTime, delay: 0.0, options: .CurveLinear, animations: {
            self.view.layoutIfNeeded()

        }, completion: {_ in

            self.progressView.alpha = 0.0
            self.progressViewConstraintWidth.constant = 0.0
            self.captureSessionCoordinator?.stopRecording()
        })
    }

    private func showCountdownButton() {

        countdownButton.setTitle("0", forState: .Normal)

        guard countdownButton.alpha == 0.0 else { return }

        UIView.animateWithDuration(0.25) {
            self.countdownButton.alpha = 1.0
            self.hintLabel.alpha = 0.0
        }
    }
}


// MARK: Private Methods

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


// MARK: Timer

extension ViewController {

    private func addTimer(timeInterval duration: NSTimeInterval) {
        
        timer?.invalidate()
        
        timer = NSTimer.scheduledTimerWithTimeInterval(duration, target: self, selector: #selector(ViewController.timerDidFired(_:)), userInfo: nil, repeats: true)
    }
    
    @objc private func timerDidFired(timer: NSTimer) {
        currentTime = min(currentTime + 1, Int(maxTime))
        countdownButton.setTitle("\(currentTime)", forState: .Normal)
    }
}




