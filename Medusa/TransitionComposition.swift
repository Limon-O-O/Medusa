//
//  TransitionComposition.swift
//  MED
//
//  Created by Limon on 7/26/16.
//  Copyright © 2016 MED. All rights reserved.
//

import AVFoundation

struct TransitionComposition {

    let composition: AVComposition

    let videoComposition: AVVideoComposition

    func makePlayable() -> AVPlayerItem {
        let playerItem = AVPlayerItem(asset: composition.copy() as! AVAsset)
        playerItem.videoComposition = self.videoComposition
        return playerItem
    }

    func makeExportSession(preset preset: String, outputURL: NSURL, outputFileType: String) -> AVAssetExportSession? {
        let session = AVAssetExportSession(asset: composition, presetName: preset)
        session?.outputFileType = outputFileType
        session?.outputURL = outputURL
        session?.timeRange = CMTimeRangeMake(kCMTimeZero, composition.duration)
        session?.videoComposition = videoComposition
        session?.canPerformMultiplePassesOverSourceMediaData = true
        return session
    }
}

struct TransitionCompositionBuilder {

    let assets: [AVAsset]

    private var transitionDuration: CMTime

    private var composition = AVMutableComposition()

    private var compositionVideoTracks = [AVMutableCompositionTrack]()

    init?(assets: [AVAsset], transitionDuration: Float64 = 0.3) {

        guard !assets.isEmpty else { return nil }

        self.assets = assets
        self.transitionDuration = CMTimeMakeWithSeconds(transitionDuration, 600)
    }

    mutating func buildComposition() -> TransitionComposition {

        var durations = assets.map { $0.duration }

        durations.sortInPlace {
            CMTimeCompare($0, $1) < 1
        }

        // Make transitionDuration no greater than half the shortest video duration.
        let shortestVideoDuration = durations[0]
        var halfDuration = shortestVideoDuration
        halfDuration.timescale *= 2
        transitionDuration = CMTimeMinimum(transitionDuration, halfDuration)

        // Now call the functions to do the preperation work for preparing a composition to export.
        // First create the tracks needed for the composition.
        buildCompositionTracks(composition: composition,
                               transitionDuration: transitionDuration,
                               assets: assets)

        // Create the passthru and transition time ranges.
        let timeRanges = calculateTimeRanges(transitionDuration: transitionDuration,
                                             assetsWithVideoTracks: assets)

        // Create the instructions for which movie to show and create the video composition.
        let videoComposition = buildVideoCompositionAndInstructions(
            composition: composition,
            passThroughTimeRanges: timeRanges.passThroughTimeRanges,
            transitionTimeRanges: timeRanges.transitionTimeRanges)

        return TransitionComposition(composition: composition, videoComposition: videoComposition)
    }

    /// Build the composition tracks

    mutating func buildCompositionTracks(composition composition: AVMutableComposition,
                                            transitionDuration: CMTime,
                                            assets: [AVAsset]) {

        let compositionVideoTrackA = composition.addMutableTrackWithMediaType(AVMediaTypeVideo,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid))

        let compositionVideoTrackB = composition.addMutableTrackWithMediaType(AVMediaTypeVideo,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid))

        let compositionAudioTrackA = composition.addMutableTrackWithMediaType(AVMediaTypeAudio,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid))

        let compositionAudioTrackB = composition.addMutableTrackWithMediaType(AVMediaTypeAudio,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid))

        compositionVideoTracks = [compositionVideoTrackA, compositionVideoTrackB]
        let compositionAudioTracks = [compositionAudioTrackA, compositionAudioTrackB]

        var cursorTime = kCMTimeZero

        for i in 0..<assets.count {

            let trackIndex = i % 2

            let currentVideoTrack = compositionVideoTracks[trackIndex]
            let currentAudioTrack = compositionAudioTracks[trackIndex]

            let assetVideoTrack = assets[i].tracksWithMediaType(AVMediaTypeVideo)[0]
            let assetAudioTrack = assets[i].tracksWithMediaType(AVMediaTypeAudio)[0]

            currentVideoTrack.preferredTransform = assetVideoTrack.preferredTransform

            let timeRange = CMTimeRangeMake(kCMTimeZero, assets[i].duration)

            do {
                try currentVideoTrack.insertTimeRange(timeRange, ofTrack: assetVideoTrack, atTime: cursorTime)
                try currentAudioTrack.insertTimeRange(timeRange, ofTrack: assetAudioTrack, atTime: cursorTime)

            } catch let error as NSError {
                print("Failed to insert append track: \(error.localizedDescription)")
            }

            // Overlap clips by tranition duration
            cursorTime = CMTimeAdd(cursorTime, assets[i].duration)
            cursorTime = CMTimeSubtract(cursorTime, transitionDuration)
        }
    }

    /// Calculate both the pass through time and the transition time ranges.
    func calculateTimeRanges(transitionDuration transitionDuration: CMTime,
                                                assetsWithVideoTracks: [AVAsset])
        -> (passThroughTimeRanges: [NSValue], transitionTimeRanges: [NSValue]) {

            var passThroughTimeRanges = [NSValue]()
            var transitionTimeRanges = [NSValue]()
            var cursorTime = kCMTimeZero

            for i in 0..<assetsWithVideoTracks.count {

                let asset = assetsWithVideoTracks[i]
                var timeRange = CMTimeRangeMake(cursorTime, asset.duration)

                if i > 0 {
                    timeRange.start = CMTimeAdd(timeRange.start, transitionDuration)
                    timeRange.duration = CMTimeSubtract(timeRange.duration, transitionDuration)
                }

                if i + 1 < assetsWithVideoTracks.count {
                    timeRange.duration = CMTimeSubtract(timeRange.duration, transitionDuration)
                }

                passThroughTimeRanges.append(NSValue(CMTimeRange: timeRange))
                cursorTime = CMTimeAdd(cursorTime, asset.duration)
                cursorTime = CMTimeSubtract(cursorTime, transitionDuration)

                if i + 1 < assetsWithVideoTracks.count {
                    timeRange = CMTimeRangeMake(cursorTime, transitionDuration)
                    transitionTimeRanges.append(NSValue(CMTimeRange: timeRange))
                }
            }
            return (passThroughTimeRanges, transitionTimeRanges)
    }

    // Build the video composition and instructions.
    func buildVideoCompositionAndInstructions(composition composition: AVMutableComposition,
                                                          passThroughTimeRanges: [NSValue],
                                                          transitionTimeRanges: [NSValue])
        -> AVMutableVideoComposition {

            var instructions = [AVMutableVideoCompositionInstruction]()

            /// http://www.stackoverflow.com/a/31146867/1638273
            let videoTracks = compositionVideoTracks // guaranteed the correct time range

            let videoComposition = AVMutableVideoComposition(propertiesOfAsset: composition)

            let videoWidth: CGFloat
            let videoHeight: CGFloat

            let transform: CGAffineTransform

            let videoAngleInDegree  = atan2(videoTracks[0].preferredTransform.b, videoTracks[0].preferredTransform.a) * 180 / CGFloat(M_PI)

            if videoAngleInDegree == 90 {

                videoWidth = composition.naturalSize.height
                videoHeight = composition.naturalSize.width
                transform = CGAffineTransformConcat(videoTracks[0].preferredTransform, CGAffineTransformMakeTranslation(videoWidth, 0.0))

            } else {

                transform = videoTracks[0].preferredTransform
                videoWidth = composition.naturalSize.width
                videoHeight = composition.naturalSize.height
            }

            // Now create the instructions from the various time ranges.
            for i in 0..<passThroughTimeRanges.count {

                let trackIndex = i % 2
                let currentVideoTrack = videoTracks[trackIndex]

                let passThroughInstruction = AVMutableVideoCompositionInstruction()
                passThroughInstruction.timeRange = passThroughTimeRanges[i].CMTimeRangeValue

                let passThroughLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: currentVideoTrack)

                passThroughLayerInstruction.setTransform(transform, atTime: kCMTimeZero)

                // You can use it to debug.
//                passThroughLayerInstruction.setTransformRampFromStartTransform(CGAffineTransformIdentity, toEndTransform: transform, timeRange: passThroughTimeRanges[i].CMTimeRangeValue)


                passThroughInstruction.layerInstructions = [passThroughLayerInstruction]

                instructions.append(passThroughInstruction)

                if i < transitionTimeRanges.count {

                    let transitionInstruction = AVMutableVideoCompositionInstruction()
                    transitionInstruction.timeRange = transitionTimeRanges[i].CMTimeRangeValue

                    // Determine the foreground and background tracks.
                    let fromTrack = videoTracks[trackIndex]
                    let toTrack = videoTracks[1 - trackIndex]

                    let fromLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: fromTrack)
                    fromLayerInstruction.setTransform(transform, atTime: kCMTimeZero)

                    // Make the opacity ramp and apply it to the from layer instruction.
                    fromLayerInstruction.setOpacityRampFromStartOpacity(1.0, toEndOpacity:0.0, timeRange: transitionInstruction.timeRange)

                    let toLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: toTrack)
                    toLayerInstruction.setTransform(transform, atTime: kCMTimeZero)

                    transitionInstruction.layerInstructions = [fromLayerInstruction, toLayerInstruction]

                    instructions.append(transitionInstruction)

                }
            }

            videoComposition.instructions = instructions
            videoComposition.frameDuration = CMTimeMake(1, 30)
            videoComposition.renderSize = CGSize(width: videoWidth, height: videoHeight)

            return videoComposition
    }
}
