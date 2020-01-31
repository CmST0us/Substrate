//
//  VKRenderer.swift
//  VKRenderer
//
//  Created by Joseph Bennett on 1/1/18.
//
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras
import FrameGraphUtilities
import Foundation

public final class VulkanBackend : _RenderBackendProtocol {
    
    public var api: RenderAPI {
        return .vulkan
    }
    
    public let vulkanInstance : VulkanInstance
    public let device : VulkanDevice
    
    let resourceRegistry : VulkanPersistentResourceRegistry
    let shaderLibrary : VulkanShaderLibrary
    let stateCaches : VulkanStateCaches
    
    var activeContext : VulkanFrameGraphContext? = nil
    
    public init(instance: VulkanInstance, surface: VkSurfaceKHR, shaderLibraryURL: URL) {
        self.vulkanInstance = instance
        let physicalDevice = self.vulkanInstance.createSystemDefaultDevice(surface: surface)!
        
        self.device = VulkanDevice(physicalDevice: physicalDevice)!
        
        self.resourceRegistry = VulkanPersistentResourceRegistry(device: self.device)
        self.shaderLibrary = try! VulkanShaderLibrary(device: self.device, url: shaderLibraryURL)
        self.stateCaches = VulkanStateCaches(device: self.device, shaderLibrary: self.shaderLibrary)
        
        RenderBackend._backend = self
    }
    
    public func registerWindowTexture(texture: Texture, context: Any) {
        self.resourceRegistry.registerWindowTexture(texture: texture, context: context)
    }
    
    @usableFromInline func setActiveContext(_ context: VulkanFrameGraphContext) {
        assert(self.activeContext == nil)
//        self.stateCaches.checkForLibraryReload()
        self.activeContext = context
    }
    
    public func materialisePersistentTexture(_ texture: Texture) -> Bool {
        let usage = VkImageUsageFlagBits(texture.descriptor.usageHint, pixelFormat: texture.descriptor.pixelFormat)
        return resourceRegistry.accessLock.withWriteLock {
            return self.resourceRegistry.allocateTexture(texture, usage: usage, sharingMode: VulkanSharingMode(usage: usage, queueIndices: self.device.physicalDevice.queueFamilyIndices), initialLayout: VK_IMAGE_LAYOUT_UNDEFINED) != nil
        }
    }
    
    public func materialisePersistentBuffer(_ buffer: Buffer) -> Bool {
        let usage = VkBufferUsageFlagBits(buffer.descriptor.usageHint)
        return resourceRegistry.accessLock.withWriteLock {
            return self.resourceRegistry.allocateBuffer(buffer, usage: usage, sharingMode: VulkanSharingMode(usage: usage, queueIndices: self.device.physicalDevice.queueFamilyIndices)) != nil
        }
    }
    
    public func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer {
        let bufferReference = self.activeContext?.resourceMap.bufferForCPUAccess(buffer) ?? resourceRegistry.accessLock.withReadLock { resourceRegistry[buffer]! }
        
        fatalError()
    }
    
    public func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        if range.isEmpty { return }
        if buffer.descriptor.storageMode == .managed {
            //            var memoryRange = VkMappedMemoryRange()
            //            memoryRange.sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE
            //            memoryRange.memory = vkBuffer.memory
            //            memoryRange.size = VkDeviceSize(range.count)
            //            memoryRange.offset = VkDeviceSize(range.lowerBound)
            //
            //            vkFlushMappedMemoryRanges(self.device.vkDevice, 1, &memoryRange)
            //        }
            
            fatalError()
//            vkBuffer.unmapMemory(range: range)
        }
    }
    
    public func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        fatalError()
    }
    
    public func dispose(texture: Texture) {
        self.resourceRegistry.disposeTexture(texture)
    }
    
    public func dispose(buffer: Buffer) {
        self.resourceRegistry.disposeBuffer(buffer)
    }

    public func dispose(argumentBuffer: _ArgumentBuffer) {
        self.resourceRegistry.disposeArgumentBuffer(argumentBuffer)
    }

    public func dispose(argumentBufferArray: _ArgumentBufferArray) {
        self.resourceRegistry.disposeArgumentBufferArray(argumentBufferArray)
    }

    public func backingResource(_ resource: Resource) -> Any? {
        return resourceRegistry.accessLock.withReadLock {
            if let buffer = resource.buffer {
                let bufferReference = resourceRegistry[buffer]
                return bufferReference?.buffer.vkBuffer
            } else if let texture = resource.texture {
                return resourceRegistry[texture]?.vkImage
            }
            return nil
        }
    }
    
    public var isDepth24Stencil8PixelFormatSupported: Bool = false // TODO: query device capabilities for this
    
    public var threadExecutionWidth : Int = 32 // TODO: Actually retrieve this from the device.

    public var renderDevice: Any {
        return self.device
    }
    
    @usableFromInline
    func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: RenderTargetDescriptor) -> PipelineReflection? {
        return self.stateCaches.reflection(for: descriptor, renderTarget: renderTarget)
    }
    
    @usableFromInline
    func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection? {
        return self.stateCaches.reflection(for: descriptor)
    }
    
    @usableFromInline
    var pushConstantPath: ResourceBindingPath {
        return ResourceBindingPath.pushConstantPath
    }
    
    @usableFromInline
    func materialiseHeap(_ heap: Heap) -> Bool {
        assertionFailure("Heaps are not implemented on Vulkan")
        return false
    }
    
    @usableFromInline
    func registerExternalResource(_ resource: Resource, backingResource: Any) {
        fatalError("registerExternalResource is unimplemented on Vulkan")
    }
    
    @usableFromInline
    func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        fatalError("copyTextureBytes is unimplemented on Vulkan")
    }
    
    @usableFromInline
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        fatalError("replaceTextureRegion is unimplemented on Vulkan")
    }
    
    @usableFromInline
    func dispose(heap: Heap) {
        fatalError("dispose(Heap) is unimplemented on Vulkan")
    }
    
    @usableFromInline
    func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath {
        return ResourceBindingPath(argumentBuffer: UInt32(index))
    }
}

#endif // canImport(Vulkan)
