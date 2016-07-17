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

    private let maxTime: Float = 5.0
    private var currentTime: Float = 0.0
    private var timer: NSTimer?

    private var captureSessionCoordinator: CaptureSessionAssetWriterCoordinator?

    @IBOutlet private weak var progressView: ProgressView!
    @IBOutlet private weak var previewView: VideoPreviewView!
    @IBOutlet private weak var ringControl: RingControl!
    @IBOutlet private weak var rollbackButton: UIButton!
    @IBOutlet private weak var saveButton: UIButton!

    private let attributes: Attributes = {

        let fileName = "video"
        let mediaFormat = MediaFormat.MP4
        let fileURL = NSFileManager.videoURLWithName(fileName, fileExtension: mediaFormat.filenameExtension)

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

        return Attributes(destinationURL: fileURL!, mediaFormat: mediaFormat, videoCompressionSettings: videoCompressionSettings, audioCompressionSettings: audioCompressionSettings)
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

            switch status {

            case .Began:
                self?.captureSessionCoordinator?.startRecording()

            case .End:
                self?.captureSessionCoordinator?.stopRecording()

            case .Press:
                break
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

        previewView.previewLayer = captureSessionCoordinator.previewLayer

        previewView.cameraDevice = captureSessionCoordinator.captureDevice

        captureSessionCoordinator.startRunning()
    }

    @IBAction func swapCameraDevicePosition(sender: UIButton) {
        try! captureSessionCoordinator?.swapCaptureDevicePosition()
    }

    @IBAction func rollbackAction(sender: UIButton) {

        if sender.selected {

            let delta = progressView.rollback()

            currentTime -= (maxTime * delta)

            if progressView.trackViews.isEmpty {
                rollbackButton.hidden = true
                saveButton.hidden = true
            }

        } else {

            progressView.trackViews.last?.backgroundColor = UIColor.brownColor()

        }

        sender.selected = !sender.selected

    }

    @IBAction func saveAction(sender: UIButton) {
        progressView.status = .Idle
    }

}



// MARK: CaptureSessionCoordinatorDelegate

extension ViewController: CaptureSessionCoordinatorDelegate {

    func coordinatorWillBeginRecording(coordinator: CaptureSessionCoordinator) {

        switch progressView.status {
        case .Pause:
            progressView.resume()
        case .Progressing, .Idle:
            break
        }

        addTimer(timeInterval: 0.01)
        rollbackButton.hidden = true
        saveButton.hidden = true

        rollbackButton.selected = false
        progressView.trackViews.last?.backgroundColor = progressView.progressTintColor

    }

    func coordinatorDidBeginRecording(coordinator: CaptureSessionCoordinator) {}

    func coordinator(coordinator: CaptureSessionCoordinator, didFinishRecordingToOutputFileURL outputFileURL: NSURL?, error: NSError?) {

        timer?.invalidate()
        progressView.pause()

        rollbackButton.hidden = false
        saveButton.hidden = false

        guard error == nil else { print("error: \(error?.localizedDescription)"); return }

        guard let outputFileURL = outputFileURL else { return }

        let videoAsset = AVURLAsset(URL: outputFileURL, options: nil)
        let videoDuration = Int(CMTimeGetSeconds(videoAsset.duration) as Double)

        print("didFinishRecording fileSize: \(fileSize(outputFileURL)) M, \(videoDuration) seconds")

//        saveVideoToPhotosAlbum(outputFileURL)
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

        currentTime = currentTime + Float(timer.timeInterval)

        if currentTime > maxTime {
            timer.invalidate()
            self.captureSessionCoordinator?.stopRecording()
            return
        }

        progressView.progress = currentTime / maxTime
    }
}




