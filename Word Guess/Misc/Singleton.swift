//
//  Singleton.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 10/09/2024.
//

import Foundation

class Singleton: NSObject, ObservableObject {
    private typealias SharedChase = [String: NSObject]
    
    private static var _chase = SharedChase()
    private static var _barrier: [Singleton.Type] = []
    
    private static var validted: [String: Bool] = [:]
    private static var _currentInitilized: Singleton.Type? { return _barrier.last }
    
    static var shared: Self { return value(for: self) }
    
    static var markAsInitializedFromOtherSource:() -> () { { validted["\(Self.self)"] = true } }
    
    private static var vaildate: (_ initilized: Singleton.Type) -> Void {
        return { initilized in
            let valid = validted["\(initilized)"] ?? false
            guard !valid else { return validted["\(initilized)"] = false }
            guard initilized == _currentInitilized else { fatalError("class \"\("\(initilized)".asClassName())\" must use shared property") }
            _ = _barrier.popLast()
        }
    }
    
    internal override init() { Self.vaildate(Self.self) }
    
    private static func value<T: NSObject>(for value: Singleton.Type) -> T {
        let key = "\(value)"
        if _chase[key] == nil {
            _barrier.append(value)
            _chase[key] = T()
        }
        return _chase[key] as! T
    }
}
