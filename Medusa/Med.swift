//
//  Med.swift
//  Medusa
//
//  Created by Limon F. on 11/4/2019.
//  Copyright © 2019 MED. All rights reserved.
//

struct Med<Base> {
    let base: Base
    init(_ base: Base) {
        self.base = base
    }
}

extension NSObject: MedProtocol {}

protocol MedProtocol {}

extension MedProtocol {
    var med: Med<Self> {
        return Med(self)
    }

    static var med: Med<Self>.Type {
        return Med.self
    }
}

func med_print<T>(_ message: T, file: String = #file, method: String = #function, line: Int = #line) {
    #if DEBUG
    let dateFormatter: DateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm:ss"
    let dateString = dateFormatter.string(from: Date())
    print("[Medusa] \(dateString) \((file as NSString).lastPathComponent)[\(line)], \(method): \(message)")
    #endif
}
