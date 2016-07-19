//
//  Attributes.swift
//  MED
//
//  Created by Limon on 6/28/16.
//  Copyright © 2016 MED. All rights reserved.
//

import AVFoundation.AVMediaFormat

public enum MediaFormat {
    case MOV
    case MP4
    case M4V

    public var filenameExtension: String {
        switch self {
        case .MOV:
            return ".mov"
        case .MP4:
            return ".mp4"
        case .M4V:
            return ".m4v"
        }
    }

    public var fileFormat: String {
        switch self {
        case .MOV:
            return AVFileTypeQuickTimeMovie
        case .MP4:
            return AVFileTypeMPEG4
        case .M4V:
            return AVFileTypeAppleM4V
        }
    }
}

public struct Attributes {

    var _destinationURL: NSURL

    public let mediaFormat: MediaFormat
    public let destinationURL: NSURL
    public let videoCompressionSettings: [String: AnyObject]
    public let audioCompressionSettings: [String: AnyObject]

    public let videoDecompressionSettings: [String: AnyObject]
    public let audioDecompressionSettings: [String: AnyObject]

    public init(destinationURL: NSURL, mediaFormat: MediaFormat = .MOV, videoCompressionSettings: [String: AnyObject], audioCompressionSettings: [String: AnyObject]? = nil, videoDecompressionSettings: [String: AnyObject]? = nil, audioDecompressionSettings: [String: AnyObject]? = nil) {

        if !destinationURL.absoluteString.lowercaseString.containsString(mediaFormat.filenameExtension) {
            fatalError("DestinationURL is Invalid, must need filename extension.")
        }

        self.mediaFormat = mediaFormat
        self.destinationURL = destinationURL
        self._destinationURL = destinationURL
        self.videoCompressionSettings = videoCompressionSettings

        let defaultAudioCompressionSettings: [String: AnyObject] = [
            AVFormatIDKey: NSNumber(unsignedInt: kAudioFormatMPEG4AAC),
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44100,
            AVEncoderBitRateKey: 128000
        ]

        // Decompress source video to 32ARGB.
        let defaultVideoDecompressionSettings: [String: AnyObject] = [
            String(kCVPixelBufferPixelFormatTypeKey): NSNumber(unsignedInt: kCVPixelFormatType_32ARGB),
            String(kCVPixelBufferIOSurfacePropertiesKey): [:]
        ]

        let defaultAudioDecompressionSettings: [String: AnyObject] = [AVFormatIDKey: NSNumber(unsignedInt: kAudioFormatLinearPCM)]

        self.audioCompressionSettings = audioCompressionSettings ?? defaultAudioCompressionSettings

        self.audioDecompressionSettings = audioDecompressionSettings ?? defaultAudioDecompressionSettings
        self.videoDecompressionSettings = videoDecompressionSettings ?? defaultVideoDecompressionSettings
    }

}
