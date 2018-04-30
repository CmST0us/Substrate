//
//  RingBuffer.swift
//  ClassMemoryAllocatorTest
//
//  Created by Thomas Roughton on 24/03/18.
//  Copyright © 2018 Team Llama. All rights reserved.
//

import Foundation

public final class RingBuffer<Element> {
    
//    public typealias SubSequence = Slice<RingBuffer<Element>>
    public typealias Index = Int
    
    @_versioned
    var capacity : Int
    public private(set) var buffer : UnsafeMutablePointer<Element>
    
    public private(set) var startIndex : Int = 0
    public private(set) var endIndex : Int = 0
    
    public convenience init() {
        self.init(initialCapacity: 16)
    }
    
    public init(initialCapacity: Int = 16) {
        self.capacity = initialCapacity
        self.buffer = UnsafeMutablePointer<Element>.allocate(capacity: capacity)
    }
    
    public subscript(index: Int) -> Element {
        get {
            return self.buffer.advanced(by: index % self.capacity).pointee
        } set {
            self.buffer.advanced(by: index % self.capacity).pointee = newValue
        }
    }
    
    @inlinable
    public var count : Int {
        return self.endIndex - self.startIndex
    }
    
    @inlinable
    public func append(_ element: Element) {
        self.resize(capacity: self.count + 1)
        self.buffer.advanced(by: self.endIndex % self.capacity).initialize(to: element)
        self.endIndex += 1
    }
    
    @inlinable
    public func popFirst() -> Element? {
        if self.startIndex < self.endIndex {
            return self.removeFirst()
        }
        return nil
    }
    
    @inlinable
    public func removeFirst() -> Element {
        let element = self.buffer.advanced(by: self.startIndex % self.capacity).move()
        self.startIndex = (self.startIndex + 1) % self.capacity
        return element
    }
    
    @inlinable
    public func popLast() -> Element? {
        if self.startIndex < self.endIndex {
            return self.removeLast()
        }
        return nil
    }
    
    @inlinable
    public func removeLast() -> Element {
        let element = self.buffer.advanced(by: (self.endIndex - 1) % self.capacity).move()
        self.endIndex -= 1
        return element
    }
    
    public func removeAll() {
        self.clearBuffer()
        self.endIndex = 0
    }
    
    @inlinable
    public var indices : Range<Int> {
        return self.startIndex..<self.endIndex
    }
    
    @inlinable
    public func resize(capacity: Int) {
        if self.capacity < capacity {
            let newCapacity = Swift.max(self.capacity * 2, capacity)
            
            let newBaseAddress = UnsafeMutablePointer<Element>.allocate(capacity: newCapacity)
            
            let count = self.count
            
            let startElementCount = Swift.min(self.capacity, self.endIndex) - self.startIndex
            newBaseAddress.moveInitialize(from: self.buffer.advanced(by: self.startIndex), count: startElementCount)
            
            if self.endIndex > self.capacity {
                let wrappedEnd = self.endIndex % self.capacity
                newBaseAddress.advanced(by: startElementCount).moveInitialize(from: self.buffer, count: wrappedEnd)
            }
            
            self.buffer.deallocate()
            
            self.buffer = newBaseAddress
            self.capacity = newCapacity
            self.startIndex = 0
            self.endIndex = count
        }
    }
    
    public func index(after i: Int) -> Int {
        return i + 1
    }
    
    private func clearBuffer() {
        if self.endIndex > self.capacity {
            let wrappedEnd = self.endIndex % self.capacity
            
            self.buffer.deinitialize(count: wrappedEnd)
        }
        
        let startElementCount = Swift.min(self.capacity, self.endIndex) - self.startIndex
        self.buffer.advanced(by: self.startIndex).deinitialize(count: startElementCount)
    }
    
    deinit {
        self.clearBuffer()
        self.buffer.deallocate()
    }
}
