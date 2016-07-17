//
//  ProgressView.swift
//  MED
//
//  Created by Limon on 2016/7/16.
//  Copyright © 2016年 MED. All rights reserved.
//

import UIKit

private let headerViewWidth: CGFloat = 2.0

@IBDesignable
class ProgressView: UIView {

    enum Status {
        case Idle
        case Progressing
        case Pause
    }

    var status = Status.Idle {
        willSet {
            switch newValue {
            case .Idle:
                currentTrackView = nil
                trackViews.removeAll()
            default:
                break
            }
        }
    }

    var progress: Float = 0.0 {

        willSet {

            guard newValue <= 1.0 && progress != 1.0 else { return }

            if status == .Idle {
                status = .Progressing
            }

            guard status == .Progressing else { return }

            _progress = newValue
        }
    }

    var progressTintColor: UIColor = UIColor.yellowColor() {
        willSet {
            currentTrackView.backgroundColor = progressTintColor
        }
    }

    private var _progress: Float = 0.0 {
        willSet {
            let totalWidth: CGFloat = currentTrackView.frame.origin.x
            let deltaWidth: CGFloat = frame.size.width * CGFloat(newValue) - totalWidth
            currentTrackView.frame.size.width = deltaWidth
        }
    }

    private(set) var trackViews = [TrackView]()
    
    private var currentTrackView: TrackView!

    override init(frame: CGRect) {

        super.init(frame: frame)

        appendTrackView()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        appendTrackView()
    }

    private func appendTrackView() {
        currentTrackView = makeTrackView()
        trackViews.append(currentTrackView)
        addSubview(currentTrackView)
    }

    func pause() {

        guard status == .Progressing else { return }

        status = .Pause
    }

    func resume() {

        guard status == .Pause else { return }
        status = .Progressing

        appendTrackView()

        trackViews.last?.headerView.hidden = false
    }

    func rollback() -> Float {

        guard let lastTrackView = trackViews.last else { return 0.0 }

        let lastTrackViewWidth = lastTrackView.frame.size.width
        let delta = Float(lastTrackViewWidth / frame.size.width)

        lastTrackView.removeFromSuperview()
        trackViews.removeLast()

        return delta
    }

    private func makeTrackView() -> TrackView {

        let trackViewX: CGFloat = trackViews.isEmpty ? 0.0 : trackViews.last!.frame.origin.x + trackViews.last!.frame.size.width

        let trackViewWidth: CGFloat = trackViews.isEmpty ? 0.0 : headerViewWidth
        let trackView = TrackView(frame: CGRect(x: trackViewX, y: 0.0, width: trackViewWidth, height: frame.size.height))
        trackView.headerView.hidden = true
        trackView.headerView.backgroundColor = backgroundColor

        trackView.backgroundColor = trackViews.isEmpty ? progressTintColor : UIColor.clearColor()

        return trackView
    }
}

class TrackView: UIView {

    let headerView: UIView

    override init(frame: CGRect) {

        headerView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: headerViewWidth, height: frame.size.height))

        super.init(frame: frame)
        addSubview(headerView)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
