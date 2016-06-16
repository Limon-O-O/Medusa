//
//  NSFileManager+VideoRecorder.swift
//  VideoRecorderExample
//
//  Created by Limon on 6/14/16.
//  Copyright © 2016 VideoRecorder. All rights reserved.
//

import Foundation

extension NSFileManager {

    class func videoCachesURL() -> NSURL? {

        guard let cacheURL = try? NSFileManager.defaultManager().URLForDirectory(.CachesDirectory, inDomain: .UserDomainMask, appropriateForURL: nil, create: false) else { return nil }

        let fileManager = NSFileManager.defaultManager()

        let messageCachesURL = cacheURL.URLByAppendingPathComponent("video_caches", isDirectory: true)

        do {
            try fileManager.createDirectoryAtURL(messageCachesURL, withIntermediateDirectories: true, attributes: nil)
            return messageCachesURL

        } catch _ {}

        return nil
    }

    class func videoURLWithName(name: String) -> NSURL? {

        let fileName = name + ".mov"
        if let videoCachesURL = videoCachesURL() {
            return videoCachesURL.URLByAppendingPathComponent("\(fileName)")
        }

        return nil
    }

    class func removeVideoFileWithFileURL(fileURL: NSURL) {

        do {

            let fileManager = NSFileManager.defaultManager()

            if let outputPath = fileURL.path where fileManager.fileExistsAtPath(outputPath) {
                try fileManager.removeItemAtURL(fileURL)
            }
            
        } catch let error {
            print((error as NSError).localizedDescription)
        }
    }
}
