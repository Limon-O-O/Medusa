//
//  NSFileManager+VideoRecorder.swift
//  VideoRecorderExample
//
//  Created by Limon on 6/14/16.
//  Copyright © 2016 VideoRecorder. All rights reserved.
//

import Foundation

extension FileManager {

    class func videoCachesURL() -> URL? {
        guard let cacheURL = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return nil }
        let fileManager = FileManager.default
        let messageCachesURL = cacheURL.appendingPathComponent("video_caches", isDirectory: true)
        do {
            try fileManager.createDirectory(at: messageCachesURL, withIntermediateDirectories: true, attributes: nil)
            return messageCachesURL
        } catch _ {}
        return nil
    }

    class func videoURLWithName(_ name: String, fileExtension: String) -> URL? {
        let fileName = name + fileExtension
        if let videoCachesURL = videoCachesURL() {
            return videoCachesURL.appendingPathComponent("\(fileName)")
        }
        return nil
    }

    class func removeVideoFileWithFileURL(_ fileURL: URL) {
        do {
            let fileManager = FileManager.default
            let outputPath = fileURL.path
            if fileManager.fileExists(atPath: outputPath) {
                try fileManager.removeItem(at: fileURL)
            }
        } catch {
            print(error.localizedDescription)
        }
    }
}
