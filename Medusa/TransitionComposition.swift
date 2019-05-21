//
//  TransitionComposition.swift
//  MED
//
//  Created by Limon on 7/26/16.
//  Copyright © 2016 MED. All rights reserved.
//

import AVFoundation

struct TransitionCompositionBuilder {

    let assets: [AVAsset]

    private var transitionDuration: CMTime

    private var composition = AVMutableComposition()

    init?(assets: [AVAsset], transitionDuration: Float64 = 0.24) {

        guard !assets.isEmpty else { return nil }

        self.assets = assets
        self.transitionDuration = CMTimeMakeWithSeconds(transitionDuration, preferredTimescale: 600)
    }

    mutating func buildComposition() -> (composition: AVComposition, videoComposition: AVVideoComposition) {

        var durations = assets.map { $0.duration }

        durations.sort {
            CMTimeCompare($0, $1) < 1
        }

        // Make transitionDuration no greater than half the shortest video duration.
        let shortestVideoDuration = durations[0]
        var halfDuration = shortestVideoDuration
        halfDuration.timescale *= 2
        transitionDuration = CMTimeMinimum(transitionDuration, halfDuration)

        // Now call the functions to do the preperation work for preparing a composition to export.
        // First create the tracks needed for the composition.
        let (compositionVideoTracks, _) = buildCompositionTracks(by: composition,
                               transitionDuration: transitionDuration,
                               assets: assets)

        // Create the passthru and transition time ranges.
        let timeRanges = calculateTimeRanges(by: transitionDuration,
                                             assetsWithVideoTracks: assets)

        // Create the instructions for which movie to show and create the video composition.
        let videoComposition = buildVideoCompositionAndInstructions(
            by: composition,
            compositionVideoTracks: compositionVideoTracks,
            passThroughTimeRanges: timeRanges.passThroughTimeRanges,
            transitionTimeRanges: timeRanges.transitionTimeRanges)

        return (composition: composition, videoComposition: videoComposition)
    }

    /// Build the composition tracks
    private func buildCompositionTracks(by composition: AVMutableComposition,
                                            transitionDuration: CMTime,
                                            assets: [AVAsset]) -> (compositionVideoTracks: [AVMutableCompositionTrack], compositionAudioTracks: [AVMutableCompositionTrack]) {

        guard
            let compositionVideoTrackA = composition.addMutableTrack(withMediaType: AVMediaType.video,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid)),

            let compositionVideoTrackB = composition.addMutableTrack(withMediaType: AVMediaType.video,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid)),

            let compositionAudioTrackA = composition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid)),

            let compositionAudioTrackB = composition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                              preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid))
            else { return (compositionVideoTracks: [], compositionAudioTracks: []) }

        let compositionVideoTracks = [compositionVideoTrackA, compositionVideoTrackB]
        let compositionAudioTracks = [compositionAudioTrackA, compositionAudioTrackB]

        var cursorTime = CMTime.zero

        for i in 0..<assets.count {

            let trackIndex = i % 2

            let currentVideoTrack = compositionVideoTracks[trackIndex]
            let currentAudioTrack = compositionAudioTracks[trackIndex]

            if let assetVideoTrack = assets[i].tracks(withMediaType: AVMediaType.video).first,
                let assetAudioTrack = assets[i].tracks(withMediaType: AVMediaType.audio).first {

                currentVideoTrack.preferredTransform = assetVideoTrack.preferredTransform

                let timeRange = CMTimeRangeMake(start: CMTime.zero, duration: assets[i].duration)

                do {
                    try currentVideoTrack.insertTimeRange(timeRange, of: assetVideoTrack, at: cursorTime)
                    try currentAudioTrack.insertTimeRange(timeRange, of: assetAudioTrack, at: cursorTime)

                } catch {
                    print("Failed to insert append track: \(error.localizedDescription)")
                }

                // Overlap clips by tranition duration
                cursorTime = CMTimeAdd(cursorTime, assets[i].duration)
                cursorTime = CMTimeSubtract(cursorTime, transitionDuration)
            }
        }

        return (compositionVideoTracks: compositionVideoTracks, compositionAudioTracks: compositionAudioTracks)
    }

    /// Calculate both the pass through time and the transition time ranges.
    private func calculateTimeRanges(by transitionDuration: CMTime,
                                                assetsWithVideoTracks: [AVAsset])
        -> (passThroughTimeRanges: [NSValue], transitionTimeRanges: [NSValue]) {

            var passThroughTimeRanges = [NSValue]()
            var transitionTimeRanges = [NSValue]()
            var cursorTime = CMTime.zero

            for i in 0..<assetsWithVideoTracks.count {

                let asset = assetsWithVideoTracks[i]
                var timeRange = CMTimeRangeMake(start: cursorTime, duration: asset.duration)

                if i > 0 {
                    timeRange.start = CMTimeAdd(timeRange.start, transitionDuration)
                    timeRange.duration = CMTimeSubtract(timeRange.duration, transitionDuration)
                }

                if i + 1 < assetsWithVideoTracks.count {
                    timeRange.duration = CMTimeSubtract(timeRange.duration, transitionDuration)
                }

                passThroughTimeRanges.append(NSValue(timeRange: timeRange))
                cursorTime = CMTimeAdd(cursorTime, asset.duration)
                cursorTime = CMTimeSubtract(cursorTime, transitionDuration)

                if i + 1 < assetsWithVideoTracks.count {
                    timeRange = CMTimeRangeMake(start: cursorTime, duration: transitionDuration)
                    transitionTimeRanges.append(NSValue(timeRange: timeRange))
                }
            }
            return (passThroughTimeRanges, transitionTimeRanges)
    }

    // Build the video composition and instructions.
    private func buildVideoCompositionAndInstructions(by composition: AVMutableComposition, compositionVideoTracks: [AVMutableCompositionTrack],
                                                          passThroughTimeRanges: [NSValue],
                                                          transitionTimeRanges: [NSValue])
        -> AVMutableVideoComposition {

            var instructions = [AVMutableVideoCompositionInstruction]()

            /// http://www.stackoverflow.com/a/31146867/1638273
            let videoTracks = compositionVideoTracks // guaranteed the correct time range

            let videoComposition = AVMutableVideoComposition(propertiesOf: composition)

            let videoWidth: CGFloat
            let videoHeight: CGFloat

            let transform: CGAffineTransform

            let videoAngleInDegree = atan2(videoTracks[0].preferredTransform.b, videoTracks[0].preferredTransform.a) * 180 / CGFloat(Double.pi)

            if videoAngleInDegree == 90 {

                videoWidth = composition.naturalSize.height
                videoHeight = composition.naturalSize.width
                transform = videoTracks[0].preferredTransform.concatenating(CGAffineTransform(translationX: videoWidth, y: 0.0))

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
                passThroughInstruction.timeRange = passThroughTimeRanges[i].timeRangeValue

                let passThroughLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: currentVideoTrack)

                passThroughLayerInstruction.setTransform(transform, at: CMTime.zero)

                // You can use it to debug.
//                passThroughLayerInstruction.setTransformRampFromStartTransform(CGAffineTransformIdentity, toEndTransform: transform, timeRange: passThroughTimeRanges[i].CMTimeRangeValue)

                passThroughInstruction.layerInstructions = [passThroughLayerInstruction]

                instructions.append(passThroughInstruction)

                if i < transitionTimeRanges.count {

                    let transitionInstruction = AVMutableVideoCompositionInstruction()
                    transitionInstruction.timeRange = transitionTimeRanges[i].timeRangeValue

                    // Determine the foreground and background tracks.
                    let fromTrack = videoTracks[trackIndex]
                    let toTrack = videoTracks[1 - trackIndex]

                    let fromLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: fromTrack)
                    fromLayerInstruction.setTransform(transform, at: CMTime.zero)

                    // Make the opacity ramp and apply it to the from layer instruction.
                    fromLayerInstruction.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity:0.0, timeRange: transitionInstruction.timeRange)

                    let toLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: toTrack)
                    toLayerInstruction.setTransform(transform, at: CMTime.zero)

                    transitionInstruction.layerInstructions = [fromLayerInstruction, toLayerInstruction]

                    instructions.append(transitionInstruction)

                }
            }

            videoComposition.instructions = instructions
            videoComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
            videoComposition.renderSize = CGSize(width: videoWidth, height: videoHeight)

            return videoComposition
    }
}
