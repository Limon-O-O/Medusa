//
//  Attributes.swift
//  MED
//
//  Created by Limon on 6/28/16.
//  Copyright © 2016 MED. All rights reserved.
//

import AVFoundation.AVMediaFormat

public enum MediaFormat {
    case mov
    case mp4
    case m4V

    public var filenameExtension: String {
        switch self {
        case .mov:
            return ".mov"
        case .mp4:
            return ".mp4"
        case .m4V:
            return ".m4v"
        }
    }

    public var fileFormat: String {
        switch self {
        case .mov:
            return AVFileTypeQuickTimeMovie
        case .mp4:
            return AVFileTypeMPEG4
        case .m4V:
            return AVFileTypeAppleM4V
        }
    }
}

public struct Attributes {

    var _destinationURL: Foundation.URL

    public let destinationURL: Foundation.URL

    public let mediaFormat: MediaFormat

    public let videoDimensions: CMVideoDimensions

    public let videoCompressionSettings: [String: AnyObject]
    public let audioCompressionSettings: [String: AnyObject]

    public init(destinationURL: Foundation.URL, videoDimensions: CMVideoDimensions, mediaFormat: MediaFormat = .mov, videoCompressionSettings: [String: AnyObject], audioCompressionSettings: [String: AnyObject]? = nil) {

        if !destinationURL.absoluteString.lowercased().contains(mediaFormat.filenameExtension) {
            fatalError("DestinationURL is Invalid, must need filename extension.")
        }

        var videoCompressionSettingsBuffer = videoCompressionSettings
        videoCompressionSettingsBuffer[AVVideoWidthKey] = Int(videoDimensions.width) as AnyObject
        videoCompressionSettingsBuffer[AVVideoHeightKey] = Int(videoDimensions.height) as AnyObject
        videoCompressionSettingsBuffer[AVVideoCodecKey] = videoCompressionSettings[AVVideoCodecKey] ?? AVVideoCodecH264 as AnyObject
        videoCompressionSettingsBuffer[AVVideoScalingModeKey] = videoCompressionSettings[AVVideoScalingModeKey] ?? AVVideoScalingModeResizeAspectFill as AnyObject

        self.mediaFormat = mediaFormat
        self.destinationURL = destinationURL
        self._destinationURL = destinationURL
        self.videoDimensions = videoDimensions
        self.videoCompressionSettings = videoCompressionSettingsBuffer

        let defaultAudioCompressionSettings: [String: AnyObject] = [
            AVFormatIDKey: NSNumber(value: kAudioFormatMPEG4AAC as UInt32),
            AVNumberOfChannelsKey: 1 as AnyObject,
            AVSampleRateKey: 44100 as AnyObject,
            AVEncoderBitRateKey: 128000 as AnyObject
        ]

        self.audioCompressionSettings = audioCompressionSettings ?? defaultAudioCompressionSettings
    }

}
