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

    private let transitionDuration: CMTime

    private var composition = AVMutableComposition()

    private var compositionVideoTracks = [AVMutableCompositionTrack]()

    init(assets: [AVAsset], transitionDuration: Float64 = 0.6) {
        self.assets = assets
        self.transitionDuration = CMTimeMakeWithSeconds(transitionDuration, 600)
    }

    mutating func buildComposition() -> TransitionComposition {

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
                // println("cursorTime.value: \(cursorTime.value)")
                // println("cursorTime.timescale: \(cursorTime.timescale)")

                if i + 1 < assetsWithVideoTracks.count {
                    timeRange = CMTimeRangeMake(cursorTime, transitionDuration)
                    // println("timeRange start value: \(timeRange.start.value)")
                    // println("timeRange start timescale: \(timeRange.start.timescale)")
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
            let videoTracks = compositionVideoTracks

            let videoComposition = AVMutableVideoComposition(propertiesOfAsset: composition)

            // Now create the instructions from the various time ranges.
            for i in 0..<passThroughTimeRanges.count {

                let trackIndex = i % 2
                let currentVideoTrack = videoTracks[trackIndex]

                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = passThroughTimeRanges[i].CMTimeRangeValue

                let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: currentVideoTrack)

                instruction.layerInstructions = [layerInstruction]

                instructions.append(instruction)

                if i < transitionTimeRanges.count {

                    let instruction = AVMutableVideoCompositionInstruction()
                    instruction.timeRange = transitionTimeRanges[i].CMTimeRangeValue

                    // Determine the foreground and background tracks.
                    let fromTrack = videoTracks[trackIndex]
                    let toTrack = videoTracks[1 - trackIndex]

                    let fromInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: fromTrack)

                    // Make the opacity ramp and apply it to the from layer instruction.
                    fromInstruction.setOpacityRampFromStartOpacity(1.0, toEndOpacity:0.0, timeRange: instruction.timeRange)

                    let toInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: toTrack)
                    instruction.layerInstructions = [fromInstruction, toInstruction]
                    instructions.append(instruction)

                }
            }
            
            videoComposition.instructions = instructions
            videoComposition.renderSize = composition.naturalSize
            videoComposition.frameDuration = CMTimeMake(1, 30)
            
            return videoComposition
    }
}
