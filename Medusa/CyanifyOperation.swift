//
//  CyanifyOperation.swift
//  MED
//
//  Created by Limon on 2016/7/19.
//  Copyright © 2016年 MED. All rights reserved.
//

import AVFoundation
import Dispatch

public enum CyanifyError: ErrorType {
    case NoMediaData
    case Canceled
}

public class CyanifyOperation: NSOperation {

    public enum Result {
        case Success(outputURL: NSURL)
        case Cancellation
        case Failure(ErrorType)
    }

    override public var executing: Bool {
        return result == nil
    }

    override public var finished: Bool {
        return result != nil
    }

    override public var asynchronous: Bool {
        return true
    }

    public let attributes: Attributes

    private let asset: AVAsset

    private var sampleTransferError: ErrorType?

    public var result: Result? {
        willSet {
            willChangeValueForKey("isExecuting")
            willChangeValueForKey("isFinished")
        }
        didSet {
            didChangeValueForKey("isExecuting")
            didChangeValueForKey("isFinished")
        }
    }

    // MARK: - Initialization

    public init(asset: AVAsset, attributes: Attributes) {
        self.asset = asset
        self.attributes = attributes
    }

    // Every path through `start()` must call `finish()` exactly once.
    override public func start() {

        if cancelled {
            finish(.Cancellation)
            return
        }

        // Load asset properties in the background, to avoid blocking the caller with synchronous I/O.
        asset.loadValuesAsynchronouslyForKeys(["tracks"]) { [weak self] in

            guard let strongSelf = self else { return }

            if strongSelf.cancelled {
                strongSelf.finish(.Cancellation)
                return
            }

            // These are all initialized in the below 'do' block, assuming no errors are thrown.
            let assetReader: AVAssetReader
            let assetWriter: AVAssetWriter
            let videoReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput]
            let passthroughReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput]

            do {

                var trackLoadingError: NSError?
                guard strongSelf.asset.statusOfValueForKey("tracks", error: &trackLoadingError) == .Loaded else {
                    throw trackLoadingError!
                }

                let tracks = strongSelf.asset.tracksWithMediaType(AVMediaTypeVideo)

                // Create reader/writer objects.

                assetReader = try AVAssetReader(asset: strongSelf.asset)
                assetWriter = try AVAssetWriter(URL: strongSelf.attributes.destinationURL, fileType: strongSelf.attributes.mediaFormat.fileFormat)

                let (videoReaderOutputs, passthroughReaderOutputs) = try strongSelf.makeReaderOutputs(byTracks: tracks, videoDecompressionSettings: strongSelf.attributes.videoDecompressionSettings, availableMediaTypes: assetWriter.availableMediaTypes)

                videoReaderOutputsAndWriterInputs = try strongSelf.makeVideoWriterInputs(byVideoReaderOutputs: videoReaderOutputs, videoCompressionSettings: strongSelf.attributes.videoCompressionSettings)

                passthroughReaderOutputsAndWriterInputs = try strongSelf.makePassthroughWriterInputs(byPassthroughReaderOutputs: passthroughReaderOutputs)

                // Hook everything up.

                for (readerOutput, writerInput) in videoReaderOutputsAndWriterInputs {
                    assetReader.addOutput(readerOutput)
                    assetWriter.addInput(writerInput)
                }

                for (readerOutput, writerInput) in passthroughReaderOutputsAndWriterInputs {
                    assetReader.addOutput(readerOutput)
                    assetWriter.addInput(writerInput)
                }

                /*
                 Remove file if necessary. AVAssetWriter will not overwrite
                 an existing file.
                 */

                try self?.removeExistingFileIfNeeded(strongSelf.attributes.destinationURL)

                // Start reading/writing.

                guard assetReader.startReading() else {
                    // `error` is non-nil when startReading returns false.
                    throw assetReader.error!
                }

                guard assetWriter.startWriting() else {
                    // `error` is non-nil when startWriting returns false.
                    throw assetWriter.error!
                }

                assetWriter.startSessionAtSourceTime(kCMTimeZero)

            } catch {
                self?.finish(.Failure(error))
                return
            }

            let writingGroup = dispatch_group_create()

            // Transfer data from input file to output file.
            strongSelf.transferVideoTracks(videoReaderOutputsAndWriterInputs, group: writingGroup)
            strongSelf.transferPassthroughTracks(passthroughReaderOutputsAndWriterInputs, group: writingGroup)

            // Handle completion.
            let queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)

            dispatch_group_notify(writingGroup, queue) {
                // `readingAndWritingDidFinish()` is guaranteed to call `finish()` exactly once.
                strongSelf.readingAndWritingDidFinish(assetReader, assetWriter: assetWriter)
            }
        }
    }

    /**
     A type used for correlating an `AVAssetWriterInput` with the `AVAssetReaderOutput`
     that is the source of appended samples.
     */
    private typealias ReaderOutputAndWriterInput = (readerOutput: AVAssetReaderOutput, writerInput: AVAssetWriterInput)

    private func makeReaderOutputs(byTracks tracks: [AVAssetTrack], videoDecompressionSettings: [String: AnyObject], availableMediaTypes: [String]) throws -> (videoReaderOutputs: [AVAssetReaderTrackOutput], passthroughReaderOutputs: [AVAssetReaderTrackOutput]) {

        // Partition tracks into "video" and "passthrough" buckets, create reader outputs.

        var videoReaderOutputs = [AVAssetReaderTrackOutput]()
        var passthroughReaderOutputs = [AVAssetReaderTrackOutput]()

        for track in tracks {
            guard availableMediaTypes.contains(track.mediaType) else { continue }

            switch track.mediaType {
            case AVMediaTypeVideo:
                let videoReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: videoDecompressionSettings)
                videoReaderOutputs += [videoReaderOutput]

            default:
                // `nil` output settings means "passthrough."
                let passthroughReaderOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                passthroughReaderOutputs += [passthroughReaderOutput]
            }
        }

        return (videoReaderOutputs, passthroughReaderOutputs)
    }


    // 此方法唯一的目：根据 videoCompressionSettings 和 "real" FormatDescription，创建 videoWriterInput
    private func makeVideoWriterInputs(byVideoReaderOutputs videoReaderOutputs: [AVAssetReaderTrackOutput], videoCompressionSettings: [String: AnyObject]) throws -> [ReaderOutputAndWriterInput] {

        /*
         In order to find the source format we need to create a temporary asset
         reader, plus a temporary track output for each "real" track output.
         We will only read as many samples (typically just one) as necessary
         to discover the format of the buffers that will be read from each "real"
         track output.
         */

        // 为了得到源文件的 FormatDescription
        let tempAssetReader = try AVAssetReader(asset: asset)

        let videoReaderOutputsAndTempVideoReaderOutputs: [(videoReaderOutput: AVAssetReaderTrackOutput, tempVideoReaderOutput: AVAssetReaderTrackOutput)] = videoReaderOutputs.map { videoReaderOutput in

            let tempVideoReaderOutput = AVAssetReaderTrackOutput(track: videoReaderOutput.track, outputSettings: videoReaderOutput.outputSettings)

            tempAssetReader.addOutput(tempVideoReaderOutput)

            return (videoReaderOutput, tempVideoReaderOutput)
        }

        // Start reading.

        guard tempAssetReader.startReading() else {
            // 'error' will be non-nil if startReading fails.
            throw tempAssetReader.error!
        }

        /*
         Create video asset writer inputs, using the source format hints read
         from the "temporary" reader outputs.
         */

        var videoReaderOutputsAndWriterInputs = [ReaderOutputAndWriterInput]()

        for (videoReaderOutput, tempVideoReaderOutput) in videoReaderOutputsAndTempVideoReaderOutputs {
            // Fetch format of source sample buffers.

            var videoFormatHint: CMFormatDescriptionRef?

            while videoFormatHint == nil {
                guard let sampleBuffer = tempVideoReaderOutput.copyNextSampleBuffer() else {
                    // We ran out of sample buffers before we found one with a format description
                    throw CyanifyError.NoMediaData
                }

                videoFormatHint = CMSampleBufferGetFormatDescription(sampleBuffer)
            }

            // Create asset writer input.
            let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoCompressionSettings, sourceFormatHint: videoFormatHint)
            videoWriterInput.transform = videoReaderOutput.track.preferredTransform

            videoReaderOutputsAndWriterInputs.append((readerOutput: videoReaderOutput, writerInput: videoWriterInput))
        }

        // Shut down processing pipelines, since only a subset of the samples were read.
        tempAssetReader.cancelReading()

        return videoReaderOutputsAndWriterInputs
    }

    private func makeAudioWriterInputs(byAudioReaderOutputs audioReaderOutputs: [AVAssetReaderTrackOutput], audioCompressionSettings: [String: AnyObject]) throws -> [ReaderOutputAndWriterInput] {

        let tempAssetReader = try AVAssetReader(asset: asset)

        let audioReaderOutputsAndTempAudioReaderOutputs: [(videoReaderOutput: AVAssetReaderTrackOutput, tempVideoReaderOutput: AVAssetReaderTrackOutput)] = audioReaderOutputs.map { audioReaderOutput in

            let tempAudioReaderOutput = AVAssetReaderTrackOutput(track: audioReaderOutput.track, outputSettings: audioReaderOutput.outputSettings)

            tempAssetReader.addOutput(tempAudioReaderOutput)

            return (audioReaderOutput, tempAudioReaderOutput)
        }

        guard tempAssetReader.startReading() else {
            throw tempAssetReader.error!
        }

        var audioReaderOutputsAndWriterInputs = [ReaderOutputAndWriterInput]()

        for (audioReaderOutput, tempAudioReaderOutput) in audioReaderOutputsAndTempAudioReaderOutputs {

            var audioFormatHint: CMFormatDescriptionRef?

            while audioFormatHint == nil {
                guard let sampleBuffer = tempAudioReaderOutput.copyNextSampleBuffer() else {
                    throw CyanifyError.NoMediaData
                }

                audioFormatHint = CMSampleBufferGetFormatDescription(sampleBuffer)
            }

            let audioWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioCompressionSettings, sourceFormatHint: audioFormatHint)

            audioReaderOutputsAndWriterInputs.append((readerOutput: audioReaderOutput, writerInput: audioWriterInput))
        }

        tempAssetReader.cancelReading()

        return audioReaderOutputsAndWriterInputs
    }

    private func makePassthroughWriterInputs(byPassthroughReaderOutputs passthroughReaderOutputs: [AVAssetReaderTrackOutput]) throws -> [ReaderOutputAndWriterInput] {
        /*
         Create passthrough writer inputs, using the source track's format
         descriptions as the format hint for each writer input.
         */

        var passthroughReaderOutputsAndWriterInputs = [ReaderOutputAndWriterInput]()

        for passthroughReaderOutput in passthroughReaderOutputs {
            /*
             For passthrough, we can simply ask the track for its format
             description and use that as the writer input's format hint.
             */
            let trackFormatDescriptions = passthroughReaderOutput.track.formatDescriptions as! [CMFormatDescriptionRef]

            guard let passthroughFormatHint = trackFormatDescriptions.first else {
                throw CyanifyError.NoMediaData
            }

            // Create asset writer input with nil (passthrough) output settings
            let passthroughWriterInput = AVAssetWriterInput(mediaType: passthroughReaderOutput.mediaType, outputSettings: nil, sourceFormatHint: passthroughFormatHint)

            passthroughReaderOutputsAndWriterInputs.append((readerOutput: passthroughReaderOutput, writerInput: passthroughWriterInput))
        }

        return passthroughReaderOutputsAndWriterInputs
    }

    private func transferVideoTracks(videoReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput], group: dispatch_group_t) {

        for (videoReaderOutput, videoWriterInput) in videoReaderOutputsAndWriterInputs {

            let perTrackDispatchQueue = dispatch_queue_create("Track data transfer queue: \(videoReaderOutput) -> \(videoWriterInput).", DISPATCH_QUEUE_SERIAL)

            dispatch_group_enter(group)
            transferSamplesAsynchronously(byReaderOutput: videoReaderOutput, toWriterInput: videoWriterInput, onQueue: perTrackDispatchQueue) {
                dispatch_group_leave(group)
            }
        }
    }

    private func transferPassthroughTracks(passthroughReaderOutputsAndWriterInputs: [ReaderOutputAndWriterInput], group: dispatch_group_t) {

        for (passthroughReaderOutput, passthroughWriterInput) in passthroughReaderOutputsAndWriterInputs {

            let perTrackDispatchQueue = dispatch_queue_create("Track data transfer queue: \(passthroughReaderOutput) -> \(passthroughWriterInput).", DISPATCH_QUEUE_SERIAL)

            dispatch_group_enter(group)
            transferSamplesAsynchronously(byReaderOutput: passthroughReaderOutput, toWriterInput: passthroughWriterInput, onQueue: perTrackDispatchQueue) {
                dispatch_group_leave(group)
            }

        }
    }

    private func transferSamplesAsynchronously(byReaderOutput readerOutput: AVAssetReaderOutput, toWriterInput writerInput: AVAssetWriterInput, onQueue queue: dispatch_queue_t, sampleBufferProcessor: ((sampleBuffer: CMSampleBufferRef) throws -> Void)? = nil, completionHandler: Void -> Void) {

        // Provide the asset writer input with a block to invoke whenever it wants to request more samples

        writerInput.requestMediaDataWhenReadyOnQueue(queue) {
            var isDone = false

            /*
             Loop, transferring one sample per iteration, until the asset writer
             input has enough samples. At that point, exit the callback block
             and the asset writer input will invoke the block again when it
             needs more samples.
             */
            while writerInput.readyForMoreMediaData {

                if self.cancelled {
                    isDone = true
                    return
                }

                // Grab next sample from the asset reader output.
                guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                    /*
                     At this point, the asset reader output has no more samples
                     to vend.
                     */
                    isDone = true
                    break
                }

                // Process the sample, if requested.
                do {
                    try sampleBufferProcessor?(sampleBuffer: sampleBuffer)
                }
                catch {
                    // This error will be picked back up in `readingAndWritingDidFinish()`.
                    self.sampleTransferError = error
                    isDone = true
                }

                // Append the sample to the asset writer input.
                if !writerInput.appendSampleBuffer(sampleBuffer) {
                    isDone = true
                    break
                }
            }

            if isDone {
                /*
                 Calling `markAsFinished()` on the asset writer input will both:
                 1. Unblock any other inputs that need more samples.
                 2. Cancel further invocations of this "request media data"
                 callback block.
                 */
                writerInput.markAsFinished()

                // Tell the caller that we are done transferring samples.
                completionHandler()
            }
        }
    }

    private func readingAndWritingDidFinish(assetReader: AVAssetReader, assetWriter: AVAssetWriter) {

        if cancelled {
            assetReader.cancelReading()
            assetWriter.cancelWriting()
        }

        // Deal with any error that occurred during processing of the video.
        if sampleTransferError != nil  {
            assetReader.cancelReading()
            assetWriter.cancelWriting()
            finish(.Failure(sampleTransferError!))
            return
        }

        // Evaluate result of reading samples.

        if assetReader.status != .Completed {
            let result: Result

            switch assetReader.status {
            case .Cancelled:
                assetWriter.cancelWriting()
                result = .Cancellation

            case .Failed:
                // `error` property is non-nil in the `.Failed` status.
                result = .Failure(assetReader.error!)

            default:
                fatalError("Unexpected terminal asset reader status: \(assetReader.status).")
            }

            finish(result)

            return
        }
        
        // Finish writing, (asynchronously) evaluate result of writing samples.
        
        assetWriter.finishWritingWithCompletionHandler { [weak self] in

            guard let strongSelf = self else { return }

            let result: Result
            
            switch assetWriter.status {
            case .Completed:
                result = .Success(outputURL: strongSelf.attributes.destinationURL)
                
            case .Cancelled:
                result = .Cancellation
                
            case .Failed:
                // `error` property is non-nil in the `.Failed` status.
                result = .Failure(assetWriter.error!)
                
            default:
                fatalError("Unexpected terminal asset writer status: \(assetWriter.status).")
            }
            
            strongSelf.finish(result)
        }
    }
    
    public func finish(result: Result) {
        self.result = result
    }
    
    private func removeExistingFileIfNeeded(URL: NSURL) throws {
        let fileManager = NSFileManager.defaultManager()
        if let outputPath = URL.path where fileManager.fileExistsAtPath(outputPath) {
            do {
                try fileManager.removeItemAtURL(URL)
            } catch {
                throw error
            }
        }
    }
}

