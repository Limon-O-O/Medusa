//
//  Queue.swift
//  VideoRecorderExample
//
//  Created by Limon on 2016/6/14.
//  Copyright © 2016年 VideoRecorder. All rights reserved.
//

protocol ExcutableQueue {
    var queue: dispatch_queue_t { get }
}

extension ExcutableQueue {
    func execute(closure: () -> Void) {
        dispatch_async(queue, closure)
    }
}

enum Queue: ExcutableQueue {
    case Main
    case Background

    var queue: dispatch_queue_t {
        switch self {
        case .Main:
            return dispatch_get_main_queue()
        case .Background:
            return dispatch_get_global_queue(QOS_CLASS_BACKGROUND, 0)
        }
    }
}

enum SerialQueue: ExcutableQueue {

    case VideoDataOutputQueue(queue: dispatch_queue_t)

    var queue: dispatch_queue_t {
        switch self {
        case .VideoDataOutputQueue(let queue):
            return queue
        }
    }
}
