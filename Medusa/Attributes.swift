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

    public init(destinationURL: NSURL, mediaFormat: MediaFormat = .MOV, videoCompressionSettings: [String: AnyObject], audioCompressionSettings: [String: AnyObject]) {

        if !destinationURL.absoluteString.lowercaseString.containsString(mediaFormat.filenameExtension) {
            fatalError("DestinationURL is Invalid, must need filename extension.")
        }

        self.mediaFormat = mediaFormat
        self.destinationURL = destinationURL
        self._destinationURL = destinationURL
        self.videoCompressionSettings = videoCompressionSettings
        self.audioCompressionSettings = audioCompressionSettings
    }

}