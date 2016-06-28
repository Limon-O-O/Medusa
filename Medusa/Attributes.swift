//
//  Attributes.swift
//  MED
//
//  Created by Limon on 6/28/16.
//  Copyright © 2016 MED. All rights reserved.
//

import AVFoundation.AVMediaFormat

public struct Attributes {

    public let fileType: String
    public let recordingURL: NSURL
    public let videoCompressionSettings: [String: AnyObject]
    public let audioCompressionSettings: [String: AnyObject]

    public init(recordingURL: NSURL, fileType: String = AVFileTypeQuickTimeMovie, videoCompressionSettings: [String: AnyObject], audioCompressionSettings: [String: AnyObject]) {
        self.fileType = fileType
        self.recordingURL = recordingURL
        self.videoCompressionSettings = videoCompressionSettings
        self.audioCompressionSettings = audioCompressionSettings
    }

}