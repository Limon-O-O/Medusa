//
//  Canvas.swift
//  Picasso
//
//  Created by Limon on 2016/8/13.
//  Copyright © 2016年 Picasso. All rights reserved.
//

import UIKit
import AVFoundation.AVUtilities

public enum CanvasContentMode {
    case Default
    case ScaleAspectFit
    case ScaleAspectFill
    case Center
}

@IBDesignable
public class Canvas: UIView {

    private lazy var renderer: Renderable =  {

        let suggestedRenderer = Canvas.suggestedRenderer()
        suggestedRenderer.view.frame = CGRectIntegral(self.bounds)
        self.addSubview(suggestedRenderer.view)

        return suggestedRenderer

    }()

    public var image: CIImage? {
        didSet {
            guard oldValue != image else { return }
            setNeedsLayout()
        }
    }

    public var canvasContentMode: CanvasContentMode = .Default {
        didSet {
            guard oldValue != canvasContentMode else { return }
            setNeedsLayout()
        }
    }

    private class func suggestedRenderer() -> Renderable {

        if #available(iOS 9.0, *) {
            #if !(arch(i386) || arch(x86_64)) && (os(iOS) || os(watchOS) || os(tvOS))
                if let defaultDevice = MTLCreateSystemDefaultDevice(), metalRenderer = MetalRenderer(device: defaultDevice) {
                    return metalRenderer
                }
            #endif
        }

        return GLKRenderer(GLContext: EAGLContext(API: .OpenGLES2))
    }

    private let screenScaleFactor = UIScreen.mainScreen().nativeScale

    private func makeRectWithAspectRatioFillRect(aspectRatio: CGSize, boundingRect: CGRect) -> CGRect {

        let horizontalRatio = boundingRect.size.width / aspectRatio.width
        let verticalRatio = boundingRect.size.height / aspectRatio.height

        let ratio = max(horizontalRatio, verticalRatio)

        let newSize = CGSizeMake(aspectRatio.width * ratio, aspectRatio.height * ratio)

        let rect = CGRectMake(boundingRect.origin.x + (boundingRect.size.width - newSize.width)/2, boundingRect.origin.y + (boundingRect.size.height - newSize.height)/2, newSize.width, newSize.height)
        return CGRectIntegral(rect)
    }

    private func makeRectWithAspectRatioInsideRect(aspectRatio: CGSize, boundingRect: CGRect) -> CGRect {
        return AVMakeRectWithAspectRatioInsideRect(aspectRatio, boundingRect)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        guard let unwrappedImage = image else { return }

        let imageSize = unwrappedImage.extent.size

        if (CGSizeEqualToSize(imageSize, CGSizeZero) || CGSizeEqualToSize(bounds.size, CGSizeZero)) {
            return
        }

        switch canvasContentMode {

        case .ScaleAspectFill:
            renderer.view.frame = makeRectWithAspectRatioFillRect(imageSize, boundingRect: bounds)

        case .ScaleAspectFit:
            renderer.view.frame = makeRectWithAspectRatioInsideRect(imageSize, boundingRect: bounds)

        case .Center:
            let viewSize = CGSizeMake(imageSize.width/screenScaleFactor, imageSize.height/screenScaleFactor)
            renderer.view.frame = CGRectIntegral(CGRectMake((CGRectGetWidth(bounds) - viewSize.width)/2, (CGRectGetHeight(bounds) - viewSize.height)/2, viewSize.width, viewSize.height))

        case .Default:
            renderer.view.frame = CGRectIntegral(bounds)
        }

        updateContent()
    }

    private func updateContent() {
        guard let unwrappedImage = image else { return }
        let scaledImage = scaleImageForDisplay(unwrappedImage)
        renderer.renderImage(scaledImage)
    }

    private func scaleImageForDisplay(image: CIImage) -> CIImage {

        let scaledBounds = CGRectApplyAffineTransform(self.bounds, CGAffineTransformMakeScale(screenScaleFactor, screenScaleFactor))
        let imageSize = image.extent.size

        switch canvasContentMode {
        case .ScaleAspectFill:
            let targetRect = makeRectWithAspectRatioFillRect(imageSize, boundingRect: scaledBounds)
            let horizontalScale = targetRect.size.width / imageSize.width
            let verticalScale = targetRect.size.height / imageSize.height
            return image.imageByApplyingTransform(CGAffineTransformMakeScale(horizontalScale, verticalScale))

        case .ScaleAspectFit:
            let targetRect = makeRectWithAspectRatioInsideRect(imageSize, boundingRect: scaledBounds)
            let horizontalScale = targetRect.size.width / imageSize.width
            let verticalScale = targetRect.size.height / imageSize.height
            return image.imageByApplyingTransform(CGAffineTransformMakeScale(horizontalScale, verticalScale))

        default:
            return image
        }
    }
}