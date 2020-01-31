//
//  Memory.swift
//  Raytracer
//
//  Created by Thomas Roughton on 23/07/17.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphUtilities
import FrameGraphCExtras

fileprivate class VulkanTemporaryBufferArena {
    
    private static let blockAlignment = 64
    
    let device : VulkanDevice
    let allocator : VmaAllocator
    
    private let blockSize : Int
    var currentBlockPos = 0
    var currentBlock : VulkanBuffer? = nil
    var usedBlocks = LinkedList<VulkanBuffer>()
    var availableBlocks = LinkedList<VulkanBuffer>()
    
    // MemoryArena Public Methods
    public init(blockSize: Int = 262144, allocator: VmaAllocator, device: VulkanDevice) {
        self.blockSize = blockSize
        self.allocator = allocator
        self.device = device
        
    }
    
    func allocate(bytes: Int, alignedTo alignment: Int) -> (VulkanBuffer, Int) {
        let alignedPosition = (currentBlockPos + alignment - 1) & ~(alignment - 1)
        
        if (alignedPosition + bytes > (currentBlock?.descriptor.size ?? 0)) {
            // Add current block to usedBlocks list
            if let currentBlock = self.currentBlock {
                usedBlocks.append(currentBlock)
                self.currentBlock = nil
            }
            
            
            // Try to get memory block from availableBlocks
            let iterator = self.availableBlocks.makeIterator()
            while let block = iterator.next() {
                if block.descriptor.size >= bytes {
                    self.currentBlock = block
                    iterator.removeLast()
                    break
                }
            }
            if self.currentBlock == nil {
                let allocationSize = max(bytes, self.blockSize)
                
                let renderAPIDescriptor = BufferDescriptor(length: allocationSize, storageMode: .managed, cacheMode: .defaultCache, usage: .shaderRead)
                
                var allocInfo = VmaAllocationCreateInfo()
                allocInfo.usage = VMA_MEMORY_USAGE_CPU_TO_GPU
                // FIXME: is it actually valid to have a buffer being used without ownership transfers?
                let descriptor = VulkanBufferDescriptor(renderAPIDescriptor, usage: .uniformBuffer, sharingMode: .exclusive)
                var buffer : VkBuffer? = nil
                var allocation : VmaAllocation? = nil
                var allocationInfo = VmaAllocationInfo()
                descriptor.withBufferCreateInfo(device: self.device) { (info) in
                    var info = info
                    vmaCreateBuffer(self.allocator, &info, &allocInfo, &buffer, &allocation, &allocationInfo)
                }
                
                self.currentBlock = VulkanBuffer(device: self.device, buffer: buffer!, allocator: self.allocator, allocation: allocation!, allocationInfo: allocationInfo, descriptor: descriptor)
            }
            self.currentBlockPos = 0
            return self.allocate(bytes: bytes, alignedTo: alignment)
        }
        let retVal = (self.currentBlock!, alignedPosition)
        self.currentBlockPos = (alignedPosition + bytes)
        return retVal
    }
    
    func reset() {
        self.currentBlockPos = 0
        self.availableBlocks.prependAndClear(contentsOf: usedBlocks)
    }
}

class VulkanTemporaryBufferAllocator : VulkanBufferAllocator {
    private var arenas : [VulkanTemporaryBufferArena]
    
    let numFrames : Int
    private var currentIndex : Int = 0
    private var waitSemaphoreValue : UInt64 = 0
    private var nextFrameWaitSemaphoreValue : UInt64 = 0
    
    public init(numFrames: Int, allocator: VmaAllocator, device: VulkanDevice) {
        self.numFrames = numFrames
        self.arenas = (0..<numFrames).map { _ in VulkanTemporaryBufferArena(allocator: allocator, device: device) }
    }
    
    public func allocate(bytes: Int) -> (VulkanBuffer, Int) {
        return self.arenas[self.currentIndex].allocate(bytes: bytes, alignedTo: 256)
    }
    
    func collectBuffer(descriptor: VulkanBufferDescriptor) -> (VkBufferReference, [VulkanEventHandle], VulkanContextWaitSemaphore) {
        let (buffer, offset) = self.allocate(bytes: Int(descriptor.size))
        return (VkBufferReference(buffer: Unmanaged.passUnretained(buffer), offset: offset), [], VulkanContextWaitSemaphore(waitValue: self.waitSemaphoreValue))
    }
    
    func depositBuffer(_ buffer: VkBufferReference, events: [VulkanEventHandle], waitSemaphore: VulkanContextWaitSemaphore) {
        assert(events.isEmpty)
        self.nextFrameWaitSemaphoreValue = max(self.waitSemaphoreValue, waitSemaphore.waitValue)
    }
    
    public func cycleFrames() {
        self.currentIndex = (self.currentIndex + 1) % self.numFrames
        self.waitSemaphoreValue = self.nextFrameWaitSemaphoreValue
        self.arenas[self.currentIndex].reset()
    }
}

#endif // canImport(Vulkan)
