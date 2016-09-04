//
//  GLKRenderer.swift
//  Canvas
//
//  Created by Limon on 9/1/16.
//  Copyright © 2016 Picasso. All rights reserved.
//

import GLKit

class GLKRenderer: NSObject, Renderable {

    let view: UIView

    let context: CIContext

    private var image: CIImage?

    init(GLContext: EAGLContext) {

        let colorSpace: CGColorSpace?

        if #available(iOS 9.0, *) {
            colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB)
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB()
        }

        let options: [String: AnyObject]? = colorSpace != nil ? [kCIContextWorkingColorSpace: colorSpace!] : nil
        context = CIContext(EAGLContext: GLContext, options: options)

        let view = GLKView(frame: CGRectZero, context: GLContext)
        view.contentScaleFactor = UIScreen.mainScreen().scale
        view.enableSetNeedsDisplay = true
        self.view = view

        super.init()

        view.delegate = self
    }

    func renderImage(image: CIImage) {
        self.image = image
        view.setNeedsDisplay()
    }
}

extension GLKRenderer: GLKViewDelegate {

    func glkView(view: GLKView, drawInRect rect: CGRect) {

        guard let unwrappedImage = image else { return }

        glClearColor(0, 0, 0, 0)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        let inRect = CGRect(origin: CGPointZero, size: CGSizeApplyAffineTransform(rect.size, CGAffineTransformMakeScale(view.contentScaleFactor, view.contentScaleFactor)))
        context.drawImage(unwrappedImage, inRect: inRect, fromRect: unwrappedImage.extent)
    }
}
