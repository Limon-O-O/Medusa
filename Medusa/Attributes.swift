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

    public var fileFormat: AVFileType {
        switch self {
        case .mov:
            return AVFileType.mov
        case .mp4:
            return AVFileType.mp4
        case .m4V:
            return AVFileType.m4v
        }
    }
}

public struct Attributes {

    var _destinationURL: Foundation.URL

    public let destinationURL: Foundation.URL

    public let mediaFormat: MediaFormat

    public var videoDimensions: CMVideoDimensions {
        didSet {
            videoCompressionSettings[AVVideoWidthKey] = Int(videoDimensions.width)
            videoCompressionSettings[AVVideoHeightKey] = Int(videoDimensions.height)
        }
    }

    public var deviceOrientation: UIDeviceOrientation = .portrait

    public private(set) var videoCompressionSettings: [String: Any]
    public let audioCompressionSettings: [String: Any]

    public init(destinationURL: Foundation.URL, videoDimensions: CMVideoDimensions, mediaFormat: MediaFormat = .mov, videoCompressionSettings: [String: Any], audioCompressionSettings: [String: Any]? = nil) {

        if !destinationURL.absoluteString.lowercased().contains(mediaFormat.filenameExtension) {
            fatalError("DestinationURL is Invalid, must need filename extension.")
        }

        var videoCompressionSettingsBuffer = videoCompressionSettings
        videoCompressionSettingsBuffer[AVVideoWidthKey] = Int(videoDimensions.width)
        videoCompressionSettingsBuffer[AVVideoHeightKey] = Int(videoDimensions.height)
        videoCompressionSettingsBuffer[AVVideoCodecKey] = videoCompressionSettings[AVVideoCodecKey] ?? AVVideoCodecH264
        videoCompressionSettingsBuffer[AVVideoScalingModeKey] = videoCompressionSettings[AVVideoScalingModeKey] ?? AVVideoScalingModeResizeAspectFill

        self.mediaFormat = mediaFormat
        self.destinationURL = destinationURL
        self._destinationURL = destinationURL
        self.videoDimensions = videoDimensions
        self.videoCompressionSettings = videoCompressionSettingsBuffer

        let defaultAudioCompressionSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000
        ]

        self.audioCompressionSettings = audioCompressionSettings ?? defaultAudioCompressionSettings
    }

}
