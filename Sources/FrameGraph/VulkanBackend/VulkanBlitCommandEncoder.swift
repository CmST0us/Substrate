//
//  BlitCommandEncoder.swift
//  VkRenderer
//
//  Created by Thomas Roughton on 8/01/18.
//

#if canImport(Vulkan)
import Vulkan
import FrameGraphCExtras

class VulkanBlitCommandEncoder : VulkanCommandEncoder {
    let device: VulkanDevice
    
    let commandBufferResources: CommandBufferResources
    let resourceMap: VulkanFrameResourceMap
    
    public init(device: VulkanDevice, commandBuffer: CommandBufferResources, resourceMap: VulkanFrameResourceMap) {
        self.device = device
        self.commandBufferResources = commandBuffer
        self.resourceMap = resourceMap
    }
    
    var queueFamily: QueueFamily {
        return .copy
    }
    
    func executePass(_ pass: RenderPassRecord, resourceCommands: [VulkanFrameResourceCommand]) {
        var resourceCommandIndex = resourceCommands.binarySearch { $0.index < pass.commandRange!.lowerBound }
         
         for (i, command) in zip(pass.commandRange!, pass.commands) {
             self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .before, commandIndex: i)
             self.executeCommand(command)
             self.checkResourceCommands(resourceCommands, resourceCommandIndex: &resourceCommandIndex, phase: .after, commandIndex: i)
         }
    }
    
    func executeCommand(_ command: FrameGraphCommand) {
        switch command {
        case .insertDebugSignpost(_):
            break
            
        case .setLabel(_):
            break
            
        case .pushDebugGroup(_):
            break
            
        case .popDebugGroup:
            break
            
        case .copyBufferToTexture(let args):
            let source = resourceMap[args.pointee.sourceBuffer]
            let destination = resourceMap[args.pointee.destinationTexture]

            let regions = destination.descriptor.allAspects.map { aspect -> VkBufferImageCopy in
                let layers = VkImageSubresourceLayers(aspectMask: aspect, mipLevel: args.pointee.destinationLevel, baseArrayLayer: args.pointee.destinationSlice, layerCount: 1)
                
                return VkBufferImageCopy(bufferOffset: VkDeviceSize(args.pointee.sourceOffset) + VkDeviceSize(source.offset),
                                         bufferRowLength: args.pointee.sourceBytesPerRow,
                                         bufferImageHeight: args.pointee.sourceBytesPerImage / args.pointee.sourceBytesPerRow,
                                         imageSubresource: layers,
                                         imageOffset: VkOffset3D(args.pointee.destinationOrigin),
                                         imageExtent: VkExtent3D(args.pointee.sourceSize))
                
            }
            regions.withUnsafeBufferPointer { regions in
                vkCmdCopyBufferToImage(self.commandBufferResources.commandBuffer, source.buffer.vkBuffer, destination.vkImage, destination.layout, UInt32(regions.count), regions.baseAddress)
            }
            
        case .copyBufferToBuffer(let args):
            let source = resourceMap[args.pointee.sourceBuffer]
            let destination = resourceMap[args.pointee.destinationBuffer]
            
            var region = VkBufferCopy(srcOffset: VkDeviceSize(args.pointee.sourceOffset) + VkDeviceSize(source.offset), dstOffset: VkDeviceSize(args.pointee.destinationOffset) + VkDeviceSize(destination.offset), size: VkDeviceSize(args.pointee.size))
            vkCmdCopyBuffer(self.commandBufferResources.commandBuffer, source.buffer.vkBuffer, destination.buffer.vkBuffer, 1, &region)
            
        case .copyTextureToBuffer(let args):
            fatalError("Unimplemented.")
            
        case .copyTextureToTexture(let args):
            fatalError("Unimplemented.")
            
        case .fillBuffer(let args):
            let buffer = resourceMap[args.pointee.buffer]
            let byteValue = UInt32(args.pointee.value)
            let intValue : UInt32 = (byteValue << 24) | (byteValue << 16) | (byteValue << 8) | byteValue
            vkCmdFillBuffer(self.commandBufferResources.commandBuffer, buffer.buffer.vkBuffer, VkDeviceSize(args.pointee.range.lowerBound) + VkDeviceSize(buffer.offset), VkDeviceSize(args.pointee.range.count), intValue)
            
        case .generateMipmaps(let texture):
            print("Generating mipmaps for \(texture)")
            self.generateMipmaps(image: resourceMap[texture])
            
        case .synchroniseTexture(let textureHandle):
            fatalError("GPU to CPU synchronisation of managed resources is unimplemented on Vulkan.")
            
        case .synchroniseTextureSlice(let args):
            fatalError("GPU to CPU synchronisation of managed resources is unimplemented on Vulkan.")
            
        case .synchroniseBuffer(let buffer):
            fatalError("GPU to CPU synchronisation of managed resources is unimplemented on Vulkan.")
            
        default:
            fatalError()
        }
    }
    
    func imageMemoryBarrier(image: VkImage, srcAccessMask: VkAccessFlagBits,
                            dstAccessMask: VkAccessFlagBits, srcStageMask: VkPipelineStageFlagBits,
                            dstStageMask: VkPipelineStageFlagBits, oldLayout: VkImageLayout,
                            newLayout: VkImageLayout, baseMipLevel: UInt32, mipLevelCount: UInt32) {
        var barrier = VkImageMemoryBarrier()
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
        barrier.srcAccessMask = VkAccessFlags(srcAccessMask)
        barrier.dstAccessMask = VkAccessFlags(dstAccessMask)
        barrier.oldLayout = oldLayout
        barrier.newLayout = newLayout
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
        barrier.image = image
        barrier.subresourceRange.aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT)
        barrier.subresourceRange.baseMipLevel = baseMipLevel
        barrier.subresourceRange.levelCount = mipLevelCount
        barrier.subresourceRange.layerCount = 1
        
        vkCmdPipelineBarrier(self.commandBufferResources.commandBuffer, VkPipelineStageFlags(srcStageMask), VkPipelineStageFlags(dstStageMask), 0, 0, nil, 0, nil, 1, &barrier)
    }
    
    /// PRECONDITION: the image layout is VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
    /// POSTCONDITION: the image layout is VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
    func generateMipmaps(image: VulkanImage) {
        assert(image.descriptor.usage.contains([.transferSource, .transferDestination, .sampled]))
        assert(image.layout == VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL)
        
        for i in 0..<image.descriptor.mipLevels {
            var region = VkImageBlit()
            region.srcSubresource.aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT)
            region.srcSubresource.mipLevel = i - 1
            region.srcSubresource.layerCount = 1
            region.srcOffsets.1.x = Int32(max(image.descriptor.extent.width >> (i - 1), 1))
            region.srcOffsets.1.y = Int32(max(image.descriptor.extent.height >> (i - 1), 1))
            region.srcOffsets.1.z = 1
            region.dstSubresource.aspectMask = VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT)
            region.dstSubresource.mipLevel = i
            region.dstSubresource.layerCount = 1
            region.dstOffsets.1.x = Int32(max(image.descriptor.extent.width >> i, 1))
            region.dstOffsets.1.y = Int32(max(image.descriptor.extent.height >> i, 1))
            region.dstOffsets.1.z = 1
            // Generate a mip level by copying and scaling the previous one.
            vkCmdBlitImage(self.commandBufferResources.commandBuffer, image.vkImage, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, image.vkImage, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region, VK_FILTER_LINEAR)
            
            // Transition the previous mip level into a SHADER_READ_ONLY_OPTIMAL layout.
            imageMemoryBarrier(image: image.vkImage, srcAccessMask: VK_ACCESS_TRANSFER_READ_BIT, dstAccessMask: VK_ACCESS_SHADER_READ_BIT, srcStageMask: VK_PIPELINE_STAGE_TRANSFER_BIT,
                               dstStageMask: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, oldLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, newLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                               baseMipLevel: i - 1, mipLevelCount: 1)
            
            if i + 1 < image.descriptor.mipLevels {
                // Transition the current mip level into a TRANSFER_SRC_OPTIMAL layout, to be used as the source for the next one.
                imageMemoryBarrier(image: image.vkImage, srcAccessMask: VK_ACCESS_TRANSFER_WRITE_BIT, dstAccessMask: VK_ACCESS_TRANSFER_READ_BIT, srcStageMask: VK_PIPELINE_STAGE_TRANSFER_BIT,
                                   dstStageMask: VK_PIPELINE_STAGE_TRANSFER_BIT, oldLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, newLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                                   baseMipLevel: i, mipLevelCount: 1);
            } else {
                // If this is the last iteration of the loop, transition the mip level directly to a SHADER_READ_ONLY_OPTIMAL layout.
                imageMemoryBarrier(image: image.vkImage, srcAccessMask: VK_ACCESS_TRANSFER_WRITE_BIT, dstAccessMask: VK_ACCESS_SHADER_READ_BIT, srcStageMask: VK_PIPELINE_STAGE_TRANSFER_BIT,
                                   dstStageMask: VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, oldLayout: VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, newLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                                   baseMipLevel: i, mipLevelCount: 1);
            }
        }
        
    }
}

#endif // canImport(Vulkan)
