//
//  MetalRenderer.swift
//  Canvas
//
//  Created by Limon on 9/1/16.
//  Copyright © 2016 Picasso. All rights reserved.
//

#if !(arch(i386) || arch(x86_64)) && (os(iOS) || os(watchOS) || os(tvOS))
import MetalKit

@available(iOS 9.0, *)
class MetalRenderer: NSObject, Renderable {

    let view: UIView

    let context: CIContext

    private let commandQueue: MTLCommandQueue

    private var image: CIImage?

    private let colorSpace: CGColorSpace

    init?(device: MTLDevice) {

        let colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let unwrappedColorSpace = colorSpace else { return nil }

        let options = [kCIContextWorkingColorSpace: unwrappedColorSpace]

        self.context = CIContext(MTLDevice: device, options: options)

        self.commandQueue = device.newCommandQueue()

        self.colorSpace = unwrappedColorSpace

        let metalView = MTKView(frame: CGRectZero, device: device)
        metalView.device = device
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 0)
        metalView.backgroundColor = UIColor.clearColor()
        metalView.enableSetNeedsDisplay = true

        // Allow to access to `currentDrawable.texture` write mode.
        metalView.framebufferOnly = false

        self.view = metalView

        super.init()

        metalView.delegate = self
    }

    func renderImage(image: CIImage) {
        self.image = image
        view.setNeedsDisplay()
    }
}

@available(iOS 9.0, *)
extension MetalRenderer: MTKViewDelegate {

    func mtkView(view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay()
    }

    func drawInMTKView(view: MTKView) {

        guard let currentDrawable = view.currentDrawable, unwrappedImage = image else { return }

        let commandBuffer = commandQueue.commandBuffer()

        let outputTexture = currentDrawable.texture

        context.render(unwrappedImage, toMTLTexture: outputTexture, commandBuffer: commandBuffer, bounds: unwrappedImage.extent, colorSpace: colorSpace)
        commandBuffer.presentDrawable(currentDrawable)
        commandBuffer.commit()
    }
}

#else

class MetalRenderer {}
    
#endif