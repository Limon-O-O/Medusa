//
//  Exporter.swift
//  MED
//
//  Created by Limon on 9/4/16.
//  Copyright © 2016 MED. All rights reserved.
//

import AVFoundation

struct Exporter {

    static let shareInstance = Exporter()

    private init() {}

    func exportSegmentsAsynchronously(_ segments: [Segment], to destinationURL: Foundation.URL, transition: Bool, presetName: String, fileFormat: AVFileType, completionHandler: (_ error: Error?) -> Void) {

        if segments.isEmpty {
            completionHandler(NSError(domain: "Segments is empty", code: 0, userInfo: nil))
            return
        }

        let assetBuffer: AVAsset?
        let videoComposition: AVVideoComposition?

        FileManager.med.removeExistingFile(at: destinationURL)

        if transition {

            let videoAssets = segments.map { AVAsset(url:$0.URL as Foundation.URL) }

            var builder = TransitionCompositionBuilder(assets: videoAssets)

            let transitionComposition = builder?.buildComposition()
            assetBuffer = transitionComposition?.composition
            videoComposition = transitionComposition?.videoComposition

        } else {
            assetBuffer = assetRepresentingSegments(segments)
            videoComposition = nil
        }

        guard let asset = assetBuffer else {
            completionHandler(NSError(domain: "AVAsset is nil", code: 0, userInfo: nil))
            return
        }

        let assetExportSession = AVAssetExportSession(asset: asset.copy() as! AVAsset, presetName: presetName)

        guard let unwrappedExportSession = assetExportSession else {
            completionHandler(NSError(domain: "AVAssetExportSession Error", code: 0, userInfo: nil))
            return
        }

        unwrappedExportSession.outputURL = destinationURL
        unwrappedExportSession.outputFileType = fileFormat
        unwrappedExportSession.canPerformMultiplePassesOverSourceMediaData = true

        if let unwrappedVideoComposition = videoComposition {
            unwrappedExportSession.videoComposition = unwrappedVideoComposition
        }

        let sessionWaitSemaphore = DispatchSemaphore(value: 0)

        unwrappedExportSession.exportAsynchronously() {
            sessionWaitSemaphore.signal()
            return
        }

        let _ = sessionWaitSemaphore.wait(timeout: DispatchTime.distantFuture)

        switch unwrappedExportSession.status {
        case .completed:
            completionHandler(nil)
            
        case .failed:
            completionHandler(unwrappedExportSession.error)
            
        default:
            break
        }
    }

    private func appendTrack(_ track: AVAssetTrack, toCompositionTrack compositionTrack: AVMutableCompositionTrack, atTime time: CMTime, withBounds bounds: CMTime) -> CMTime {

        var timeRange = track.timeRange
        let time = CMTimeAdd(time, timeRange.start)

        if CMTIME_IS_VALID(bounds) {
            let currentBounds = CMTimeAdd(time, timeRange.duration)

            if (currentBounds > bounds) {
                timeRange = CMTimeRangeMake(start: timeRange.start, duration: CMTimeSubtract(timeRange.duration, CMTimeSubtract(currentBounds, bounds)));
            }
        }

        if timeRange.duration > CMTime.zero {

            do {
                try compositionTrack.insertTimeRange(timeRange, of: track, at: time)
                //            print("Inserted %@ at %fs (%fs -> %fs)", track.mediaType, CMTimeGetSeconds(time), CMTimeGetSeconds(timeRange.start), CMTimeGetSeconds(timeRange.duration))

            } catch {
                med_print("Failed to insert append \(compositionTrack.mediaType) track: \(error.localizedDescription)")
            }
            return CMTimeAdd(time, timeRange.duration);
        }

        return time
    }

    private func assetRepresentingSegments(_ segments: [Segment]) -> AVAsset? {

        if segments.isEmpty {
            return nil
        }

        if segments.count == 1 {

            let segment = segments.first!
            return AVAsset(url: segment.URL as Foundation.URL)

        } else {

            let composition = AVMutableComposition()
            appendSegmentsToComposition(composition, segments: segments)

            return composition
        }
    }

    private func appendSegmentsToComposition(_ composition: AVMutableComposition, segments: [Segment]) {

        var audioTrack: AVMutableCompositionTrack? = nil
        var videoTrack: AVMutableCompositionTrack? = nil

        var currentTime = composition.duration

        for (_, segment) in segments.enumerated() {

            let asset = AVAsset(url: segment.URL as Foundation.URL)

            let audioAssetTracks = asset.tracks(withMediaType: AVMediaType.audio)
            let videoAssetTracks = asset.tracks(withMediaType: AVMediaType.video)

            var maxBounds = CMTime.invalid

            var videoTime = currentTime

            for (_, videoAssetTrack) in videoAssetTracks.enumerated() {

                if (videoTrack == nil) {

                    let videoTracks = composition.tracks(withMediaType: AVMediaType.video)

                    if (videoTracks.count > 0) {
                        videoTrack = videoTracks.first

                    } else {

                        videoTrack = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
                        videoTrack?.preferredTransform = videoAssetTrack.preferredTransform
                    }
                }

                videoTime = appendTrack(videoAssetTrack, toCompositionTrack: videoTrack!, atTime: videoTime, withBounds: maxBounds)
                maxBounds = videoTime
            }

            var audioTime = currentTime

            for (_, audioAssetTrack) in audioAssetTracks.enumerated() {

                if audioTrack == nil {
                    
                    let audioTracks = composition.tracks(withMediaType: AVMediaType.audio)
                    
                    if (audioTracks.count > 0) {
                        audioTrack = audioTracks.first
                    } else {
                        
                        audioTrack = composition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    }
                    
                    audioTime = appendTrack(audioAssetTrack, toCompositionTrack: audioTrack!, atTime: audioTime, withBounds: maxBounds)
                }
                
            }
            
            currentTime = composition.duration
        }
    }

}
