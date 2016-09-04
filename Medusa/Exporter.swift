//
//  Exporter.swift
//  MED
//
//  Created by Limon on 9/4/16.
//  Copyright © 2016 MED. All rights reserved.
//

import AVFoundation

struct Exporter {

    static func exportSegmentsAsynchronously(segments: [Segment], to destinationURL: NSURL, transition: Bool, presetName: String, fileFormat: String, completionHandler: (error: NSError?) -> Void) {

        let asset: AVAsset
        let videoComposition: AVVideoComposition?

        NSFileManager.med_removeExistingFile(byURL: destinationURL)

        if transition {

            let videoAssets = segments.map { AVAsset(URL:$0.URL) }

            var builder = TransitionCompositionBuilder(assets: videoAssets)!

            let transitionComposition = builder.buildComposition()

            asset = transitionComposition.composition
            videoComposition = transitionComposition.videoComposition

        } else {
            asset = assetRepresentingSegments(segments)
            videoComposition = nil
        }

        let assetExportSession = AVAssetExportSession(asset: asset.copy() as! AVAsset, presetName: presetName)

        guard let unwrappedExportSession = assetExportSession else {
            completionHandler(error: NSError(domain: "AVAssetExportSession Error", code: 0, userInfo: nil))
            return
        }

        unwrappedExportSession.outputURL = destinationURL
        unwrappedExportSession.outputFileType = fileFormat
        unwrappedExportSession.canPerformMultiplePassesOverSourceMediaData = true

        if let unwrappedVideoComposition = videoComposition {
            unwrappedExportSession.videoComposition = unwrappedVideoComposition
        }

        let sessionWaitSemaphore = dispatch_semaphore_create(0)

        unwrappedExportSession.exportAsynchronouslyWithCompletionHandler() {
            dispatch_semaphore_signal(sessionWaitSemaphore)
            return
        }

        dispatch_semaphore_wait(sessionWaitSemaphore, DISPATCH_TIME_FOREVER)

        switch unwrappedExportSession.status {
        case .Completed:
            completionHandler(error: nil)
            
        case .Failed:
            completionHandler(error: unwrappedExportSession.error)
            
        default:
            break
        }
        
    }

    private static func appendTrack(track: AVAssetTrack, toCompositionTrack compositionTrack: AVMutableCompositionTrack, atTime time: CMTime, withBounds bounds: CMTime) -> CMTime {

        var timeRange = track.timeRange
        let time = CMTimeAdd(time, timeRange.start)

        if CMTIME_IS_VALID(bounds) {
            let currentBounds = CMTimeAdd(time, timeRange.duration)

            if (currentBounds > bounds) {
                timeRange = CMTimeRangeMake(timeRange.start, CMTimeSubtract(timeRange.duration, CMTimeSubtract(currentBounds, bounds)));
            }
        }

        if timeRange.duration > kCMTimeZero {

            do {
                try compositionTrack.insertTimeRange(timeRange, ofTrack: track, atTime: time)
                //            print("Inserted %@ at %fs (%fs -> %fs)", track.mediaType, CMTimeGetSeconds(time), CMTimeGetSeconds(timeRange.start), CMTimeGetSeconds(timeRange.duration))

            } catch let error as NSError {

                print("Failed to insert append \(compositionTrack.mediaType) track: \(error.localizedDescription)")

            }
            return CMTimeAdd(time, timeRange.duration);
        }

        return time
    }

    private static func assetRepresentingSegments(segments: [Segment]) -> AVAsset {

        if segments.count == 1 {

            let segment = segments.first!
            return AVAsset(URL: segment.URL)

        } else {

            let composition = AVMutableComposition()
            appendSegmentsToComposition(composition, segments: segments)

            return composition
        }
    }

    private static func appendSegmentsToComposition(composition: AVMutableComposition, segments: [Segment]) {

        var audioTrack: AVMutableCompositionTrack? = nil
        var videoTrack: AVMutableCompositionTrack? = nil

        var currentTime = composition.duration

        for (_, segment) in segments.enumerate() {

            let asset = AVAsset(URL: segment.URL)

            let audioAssetTracks = asset.tracksWithMediaType(AVMediaTypeAudio)
            let videoAssetTracks = asset.tracksWithMediaType(AVMediaTypeVideo)

            var maxBounds = kCMTimeInvalid

            var videoTime = currentTime

            for (_, videoAssetTrack) in videoAssetTracks.enumerate() {

                if (videoTrack == nil) {

                    let videoTracks = composition.tracksWithMediaType(AVMediaTypeVideo)

                    if (videoTracks.count > 0) {
                        videoTrack = videoTracks.first

                    } else {

                        videoTrack = composition.addMutableTrackWithMediaType(AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)
                        videoTrack?.preferredTransform = videoAssetTrack.preferredTransform
                    }
                }

                videoTime = appendTrack(videoAssetTrack, toCompositionTrack: videoTrack!, atTime: videoTime, withBounds: maxBounds)
                maxBounds = videoTime
            }

            var audioTime = currentTime

            for (_, audioAssetTrack) in audioAssetTracks.enumerate() {

                if audioTrack == nil {
                    
                    let audioTracks = composition.tracksWithMediaType(AVMediaTypeAudio)
                    
                    if (audioTracks.count > 0) {
                        audioTrack = audioTracks.first
                    } else {
                        
                        audioTrack = composition.addMutableTrackWithMediaType(AVMediaTypeAudio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    }
                    
                    audioTime = appendTrack(audioAssetTrack, toCompositionTrack: audioTrack!, atTime: audioTime, withBounds: maxBounds)
                }
                
            }
            
            currentTime = composition.duration
        }
    }

}