//
//  CommandEncoders.swift
//  Substrate
//
//  Created by Thomas Roughton on 30/08/20.
//

import SubstrateUtilities

#if canImport(Metal)
@preconcurrency import Metal
#endif

#if canImport(MetalPerformanceShaders)
@preconcurrency import MetalPerformanceShaders
#endif

#if canImport(Vulkan)
import Vulkan
#endif

@usableFromInline
protocol CommandEncoder : AnyObject {
    var passRecord : RenderPassRecord { get }
    
    func pushDebugGroup(_ groupName: String)
    func popDebugGroup()
    
    func endEncoding()
}

// Performance: avoid slow range initialiser until https://github.com/apple/swift/pull/40871 makes it into a release branch.
extension Range where Bound: Strideable, Bound.Stride: SignedInteger {
  /// Creates an instance equivalent to the given `ClosedRange`.
  ///
  /// - Parameter other: A closed range to convert to a `Range` instance.
  ///
  /// An equivalent range must be representable as an instance of Range<Bound>.
  /// For example, passing a closed range with an upper bound of `Int.max`
  /// triggers a runtime error, because the resulting half-open range would
  /// require an upper bound of `Int.max + 1`, which is not representable as
  /// an `Int`.
  @inlinable // trivial-implementation
  public init(_ other: ClosedRange<Bound>) {
    let upperBound = other.upperBound.advanced(by: 1)
    self.init(uncheckedBounds: (lower: other.lowerBound, upper: upperBound))
  }
}

extension CommandEncoder {
    @inlinable
    public var renderPass : RenderPass {
        return self.passRecord.pass
    }
}

extension CommandEncoder {
    @inlinable
    public func debugGroup<T>(_ groupName: String, perform: () throws -> T) rethrows -> T {
        self.pushDebugGroup(groupName)
        let result = try perform()
        self.popDebugGroup()
        return result
    }
}

/*
 
 ** Resource Binding Algorithm-of-sorts **
 
 When the user binds a resource for a key, record the association between that key and that resource.
 
 When the user submits a draw call, look at all key-resource pairs and bind them. Do this by retrieving the resource binding path from the backend, along with how the resource is used. Record the first usage of the resource;  the ‘first use command index’ is the first index for all of the bindings. Keep a handle to allow updating of the applicable command range. If a resource is not used, then it is not an active binding and its update handle is not retained.
 
 After the pipeline state is changed, we need to query all resources given their keys on the next draw call. If they are an active binding and the resource binding path has not changed and the usage type has not changed, then we do not need to make any changes; however, if any of the above change we need to end the applicable command range at the index of the last draw call and register a new resource binding path and update handle.
 
 We can bypass the per-draw-call checks iff the pipeline state has not changed and there have been no changes to bound resources.
 
 For buffers, we also need to track a 32-bit offset. If the offset changes but not the main resource binding path, then we submit a update-offset command instead rather than a ‘bind’ command. The update-offset command includes the ObjectIdentifier for the resource.
 
 When encoding has finished, update the applicable command range for all active bindings to continue through to the last draw call made within the encoder.
 
 
 A requirement for resource binding is that subsequently bound pipeline states are compatible with the pipeline state bound at the time of the first draw call.
 */

struct ResourceUsagePointerList: Collection, Equatable {
    let pointer: UnsafeMutableRawPointer?
    let count: Int
    
    public init(usagePointer: ResourceUsagePointer?) {
        self.pointer = UnsafeMutableRawPointer(usagePointer)
        self.count = usagePointer == nil ? 0 : 1
    }
    
    public init(usagePointers: UnsafeMutableBufferPointer<ResourceUsagePointer>) {
        self.pointer = UnsafeMutableRawPointer(usagePointers.baseAddress)
        self.count = usagePointers.count
    }
    
    public var isEmpty: Bool {
        return self.count == 0
    }
    
    public var startIndex: Int {
        return 0
    }
    
    public var endIndex: Int {
        return self.count
    }
    
    public func index(after i: Int) -> Int {
        return i + 1
    }
    
    public subscript(index: Int) -> ResourceUsagePointer {
        assert(index >= 0 && index < self.count)
        if self.count == 1 {
            return self.pointer!.assumingMemoryBound(to: ResourceUsage.self)
        } else {
            return self.pointer!.assumingMemoryBound(to: ResourceUsagePointer.self)[index]
        }
    }
    
    public var first: ResourceUsagePointer? {
        if self.isEmpty {
            return nil
        }
        return self[0]
    }
}

/// `ResourceBindingEncoder` is the common superclass `CommandEncoder` for all command encoders that can bind resources.
/// You never instantiate a `ResourceBindingEncoder` directly; instead, you are provided with one of its concrete subclasses in a render pass' `execute` method.
public class ResourceBindingEncoder : CommandEncoder {
    
    @usableFromInline
    struct BoundResource {
        public var resource : Resource
        public var bindingCommand : UnsafeMutableRawPointer?
        public var usagePointers : ResourceUsagePointerList // where the first element is the usage pointer for this resource and subsequent elements, if present, are for its subresources
        public var isIndirectlyBound : Bool
        /// Whether the resource is assumed to be used in the same way for the entire time it's bound.
        public var consistentUsageAssumed : Bool
        
//        public var usagePointer: ResourceUsagePointer? {
//            self.usagePointers.first
//        }
    }
    
    @usableFromInline let passRecord: RenderPassRecord
    
    @usableFromInline
    var needsUpdateBindings = false
    @usableFromInline
    var pipelineStateChanged = false
    @usableFromInline
    var depthStencilStateChanged = false
    
    @usableFromInline
    var currentPipelineReflection : PipelineReflection! = nil
    
    init(passRecord: RenderPassRecord) {
        self.passRecord = passRecord
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.pushDebugGroup(passRecord.name)
#endif
    }
    
    public func pushDebugGroup(_ groupName: String) {
        
    }
    
    public func popDebugGroup() {
        
    }
    
    func setLabel(_ label: String) {
        
    }
    
    public func insertDebugSignpost(_ string: String) {
        
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, at path: ResourceBindingPath) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, at path: ResourceBindingPath) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func setBufferOffset(_ offset: Int, at path: ResourceBindingPath) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func setTexture(_ texture: Texture?, at path: ResourceBindingPath) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func setSampler(_ descriptor: SamplerDescriptor?, at path: ResourceBindingPath) async {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func setSampler(_ state: SamplerState?, at path: ResourceBindingPath) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    public func setVisibleFunctionTable(_ table: VisibleFunctionTable?, at path: ResourceBindingPath) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    public func setIntersectionFunctionTable(_ table: IntersectionFunctionTable?, at path: ResourceBindingPath) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    @available(macOS 12.0, iOS 15.0, *)
    public func setAccelerationStructure(_ structure: AccelerationStructure?, at path: ResourceBindingPath) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    /// Construct an `ArgumentBuffer` specified by the `ArgumentBufferEncodable` value `arguments`
    /// and bind it to the binding index `setIndex`, corresponding to a `[[buffer(setIndex + 1)]]` binding for Metal or the
    /// descriptor set at `setIndex` for Vulkan.
    public func setArguments<A : ArgumentBufferEncodable>(_ arguments: inout A, at setIndex: Int) {
        if A.self == NilSet.self {
            return
        }
        
        let bindingPath = RenderBackend.argumentBufferPath(at: setIndex, stages: A.activeStages)
        
        let argumentBuffer = ArgumentBuffer(descriptor: A.argumentBufferDescriptor)
        assert(argumentBuffer.bindings.isEmpty)
        arguments.encode(into: argumentBuffer, setIndex: setIndex, bindingEncoder: self)
     
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        argumentBuffer.label = "Descriptor Set for \(String(reflecting: A.self))"
#endif
        
        if _isDebugAssertConfiguration() {
            
            for binding in argumentBuffer.bindings {
                switch binding.1 {
                case .buffer(let buffer, _):
                    assert(buffer.type == .buffer)
                case .texture(let texture):
                    assert(texture.type == .texture)
                default:
                    break
                }
            }
        }

        self.setArgumentBuffer(argumentBuffer, at: setIndex, stages: A.activeStages)
    }
    
    /// Bind `argumentBuffer` to the binding index `index`, corresponding to a `[[buffer(setIndex + 1)]]` binding for Metal or the
    /// descriptor set at `setIndex` for Vulkan, and mark it as active in render stages `stages`.
    public func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer?, at index: Int, stages: RenderStages) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    /// Bind `argumentBufferArray` to the binding index `index`, corresponding to a `[[buffer(setIndex + 1)]]` binding for Metal or the
    /// descriptor set at `setIndex` for Vulkan, and mark it as active in render stages `stages`.
    public func setArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray?, at index: Int, stages: RenderStages) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    @usableFromInline func endEncoding() {
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.popDebugGroup() // Pass Name
#endif
    }
}

extension ResourceBindingEncoder {
    
    @inlinable
    public func setValue<T : ResourceProtocol>(_ value: T, at path: ResourceBindingPath) {
        preconditionFailure("setValue should not be used with resources; use setBuffer, setTexture, or setArgumentBuffer instead.")
    }
    
    @inlinable
    public func setValue<T>(_ value: T, at path: ResourceBindingPath) {
        assert(!(T.self is AnyObject.Type), "setValue should only be used with value types.")
        
        var value = value
        withUnsafeBytes(of: &value) { bytes in
            self.setBytes(bytes.baseAddress!, length: bytes.count, at: path)
        }
    }
}

public protocol AnyRenderCommandEncoder {
    func setArgumentBuffer(_ argumentBuffer: ArgumentBuffer?, at index: Int, stages: RenderStages)
    
    func setArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray?, at index: Int, stages: RenderStages)
    
    func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int)
    
    func setVertexBufferOffset(_ offset: Int, index: Int)
    
    func setViewport(_ viewport: Viewport)
    
    func setFrontFacing(_ frontFacingWinding: Winding)
    
    func setCullMode(_ cullMode: CullMode)

    func setScissorRect(_ rect: ScissorRect)
    
    func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float)
    
    func setStencilReferenceValue(_ referenceValue: UInt32)
    
    func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32)
    
    func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int, baseInstance: Int) async
    
    func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int, baseVertex: Int, baseInstance: Int)  async
}

/// `RenderCommandEncoder` allows you to encode rendering commands to be executed by the GPU within a single `DrawRenderPass`.
public class RenderCommandEncoder : ResourceBindingEncoder, AnyRenderCommandEncoder {
    
    @usableFromInline
    enum Attachment : Hashable, CustomHashable {
        case color(Int)
        case depth
        case stencil
        
        public var customHashValue: Int {
            switch self {
            case .depth:
                return 1 << 0
            case .stencil:
                return 1 << 1
            case .color(let index):
                return 1 << 2 &+ index
            }
        }
    }
    
    struct DrawDynamicState: OptionSet {
        let rawValue: Int
        
        init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        static let viewport = DrawDynamicState(rawValue: 1 << 0)
        static let scissorRect = DrawDynamicState(rawValue: 1 << 1)
        static let frontFacing = DrawDynamicState(rawValue: 1 << 2)
        static let cullMode = DrawDynamicState(rawValue: 1 << 3)
        static let triangleFillMode = DrawDynamicState(rawValue: 1 << 4)
        static let depthBias = DrawDynamicState(rawValue: 1 << 5)
        static let stencilReferenceValue = DrawDynamicState(rawValue: 1 << 6)
    }
    
    let drawRenderPass : DrawRenderPass
    
    var renderPipelineDescriptor : RenderPipelineDescriptor? = nil
    var depthStencilDescriptor : DepthStencilDescriptor? = nil
    
    var nonDefaultDynamicState: DrawDynamicState = []

    init(renderPass: DrawRenderPass, passRecord: RenderPassRecord) {
        self.drawRenderPass = renderPass
        
        super.init(passRecord: passRecord)
        
        assert(passRecord.pass === renderPass)
    }
    
    /// The debug label for this render command encoder. Inferred from the render pass' name by default.
    public var label : String = "" {
        didSet {
            self.setLabel(label)
        }
    }
    
    public func setRenderPipelineDescriptor(_ descriptor: RenderPipelineDescriptor, retainExistingBindings: Bool = true) async {
        self.renderPipelineDescriptor = descriptor
        self.currentPipelineReflection = await RenderBackend.renderPipelineReflection(descriptor: descriptor, renderTarget: self.drawRenderPass.renderTargetsDescriptor)
        
        self.pipelineStateChanged = true
        self.needsUpdateBindings = true
    }
    
    public func setVertexBuffer(_ buffer: Buffer?, offset: Int, index: Int) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func setVertexBufferOffset(_ offset: Int, index: Int) {
        preconditionFailure("\(#function) needs concrete implementation")
    }

    public func setViewport(_ viewport: Viewport) {
        self.nonDefaultDynamicState.formUnion(.viewport)
    }
    
    public func setFrontFacing(_ frontFacingWinding: Winding) {
        self.nonDefaultDynamicState.formUnion(.frontFacing)
    }
    
    public func setCullMode(_ cullMode: CullMode) {
        self.nonDefaultDynamicState.formUnion(.cullMode)
    }
    
    public func setDepthStencilDescriptor(_ descriptor: DepthStencilDescriptor?) {
        guard self.drawRenderPass.renderTargetsDescriptor.depthAttachment != nil ||
            self.drawRenderPass.renderTargetsDescriptor.stencilAttachment != nil else {
                return
        }
        
        var descriptor = descriptor ?? DepthStencilDescriptor()
        if self.drawRenderPass.renderTargetsDescriptor.depthAttachment == nil {
            descriptor.depthCompareFunction = .always
            descriptor.isDepthWriteEnabled = false
        }
        if self.drawRenderPass.renderTargetsDescriptor.stencilAttachment == nil {
            descriptor.frontFaceStencil = .init()
            descriptor.backFaceStencil = .init()
        }
        
        self.depthStencilDescriptor = descriptor
        self.depthStencilStateChanged = true
    }
    
//    @inlinable
    public func setScissorRect(_ rect: ScissorRect) {
        self.nonDefaultDynamicState.formUnion(.scissorRect)
    }
    
    public func setDepthBias(_ depthBias: Float, slopeScale: Float, clamp: Float) {
        self.nonDefaultDynamicState.formUnion(.depthBias)
    }
    
    public func setStencilReferenceValue(_ referenceValue: UInt32) {
        self.nonDefaultDynamicState.formUnion(.stencilReferenceValue)
    }
    
    public func setStencilReferenceValues(front frontReferenceValue: UInt32, back backReferenceValue: UInt32) {
        self.nonDefaultDynamicState.formUnion(.stencilReferenceValue)
    }
    
    
    public func drawPrimitives(type primitiveType: PrimitiveType, vertexStart: Int, vertexCount: Int, instanceCount: Int = 1, baseInstance: Int = 0) {
        assert(instanceCount > 0, "instanceCount(\(instanceCount)) must be non-zero.")

        guard self.currentPipelineReflection != nil else {
            assert(self.renderPipelineDescriptor != nil, "No render or compute pipeline is set for pass \(renderPass.name).")
            return
        }
    }
    
    public func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexCount: Int, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, instanceCount: Int = 1, baseVertex: Int = 0, baseInstance: Int = 0) {
        assert(instanceCount > 0, "instanceCount(\(instanceCount)) must be non-zero.")
        
        guard self.currentPipelineReflection != nil else {
            assert(self.renderPipelineDescriptor != nil, "No render or compute pipeline is set for pass \(renderPass.name).")
            return
        }
    }
    
    public func drawIndexedPrimitives(type primitiveType: PrimitiveType, indexType: IndexType, indexBuffer: Buffer, indexBufferOffset: Int, indirectBuffer: Buffer, indirectBufferOffset: Int) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    
    @available(macOS 13.0, iOS 16.0, *)
    public func drawMeshThreadgroups(_ threadgroupsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    public func drawMeshThreads(_ threadsPerGrid: Size, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    @available(macOS 13.0, iOS 16.0, *)
    public func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerObjectThreadgroup: Size, threadsPerMeshThreadgroup: Size) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func dispatchThreadsPerTile(_ threadsPerTile: Size) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func useResource(_ resource: Resource, access: ResourceAccessFlags, stages: RenderStages) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func useHeap(_ heap: Heap, stages: RenderStages) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func memoryBarrier(scope: BarrierScope, after: RenderStages, before: RenderStages) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func memoryBarrier(resources: [Resource], after: RenderStages, before: RenderStages) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    @usableFromInline override func endEncoding() {
        // Reset any dynamic state to the defaults.
        let renderTargetSize = self.drawRenderPass.renderTargetsDescriptor.size
        if self.nonDefaultDynamicState.contains(.viewport) {
            self.setViewport(Viewport(originX: 0.0, originY: 0.0, width: Double(renderTargetSize.width), height: Double(renderTargetSize.height), zNear: 0.0, zFar: 1.0))
        }
        if self.nonDefaultDynamicState.contains(.scissorRect) {
            self.setScissorRect(ScissorRect(x: 0, y: 0, width: renderTargetSize.width, height: renderTargetSize.height))
        }
        if self.nonDefaultDynamicState.contains(.frontFacing) {
            self.setFrontFacing(.counterClockwise)
        }
        if self.nonDefaultDynamicState.contains(.cullMode) {
            self.setCullMode(.none)
        }
        if self.nonDefaultDynamicState.contains(.depthBias) {
            self.setDepthBias(0.0, slopeScale: 0.0, clamp: 0.0)
        }
        if self.nonDefaultDynamicState.contains(.stencilReferenceValue) {
            self.setStencilReferenceValue(0)
        }
        
        super.endEncoding()
    }
}


public class ComputeCommandEncoder : ResourceBindingEncoder {
    
    let computeRenderPass : ComputeRenderPass
    
    private var currentComputePipeline : ComputePipelineDescriptorBox? = nil
    
    init(renderPass: ComputeRenderPass, passRecord: RenderPassRecord) {
        self.computeRenderPass = renderPass
        super.init(passRecord: passRecord)
        
        assert(passRecord.pass === renderPass)
    }
    
    public var label : String = "" {
        didSet {
            self.setLabel(label)
        }
    }
    
    public func setComputePipelineDescriptor(_ descriptor: ComputePipelineDescriptor, retainExistingBindings: Bool = true) async {
        self.currentPipelineReflection = await RenderBackend.computePipelineReflection(descriptor: descriptor)
        
        self.pipelineStateChanged = true
        self.needsUpdateBindings = true

        let pipelineBox = ComputePipelineDescriptorBox(descriptor)
        self.currentComputePipeline = pipelineBox
    }
    
    public func setComputePipelineState(_ pipelineState: ComputePipelineState) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    /// The number of threads in a SIMD group/wave for the current pipeline state.
    public var currentThreadExecutionWidth: Int {
        return self.currentPipelineReflection?.threadExecutionWidth ?? 0
    }
    
    public func setStageInRegion(_ region: Region) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func setThreadgroupMemoryLength(_ length: Int, at index: Int) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    @usableFromInline
    func updateThreadgroupExecutionWidth(threadsPerThreadgroup: Size) {
        let threads = threadsPerThreadgroup.width * threadsPerThreadgroup.height * threadsPerThreadgroup.depth
        let isMultiple = threads % self.currentThreadExecutionWidth == 0
        self.currentComputePipeline!.threadGroupSizeIsMultipleOfThreadExecutionWidth = self.currentComputePipeline!.threadGroupSizeIsMultipleOfThreadExecutionWidth && isMultiple
    }

    public func dispatchThreads(_ threadsPerGrid: Size, threadsPerThreadgroup: Size) {
        guard self.currentPipelineReflection != nil else {
            assert(self.currentComputePipeline != nil, "No compute pipeline is set for pass \(renderPass.name).")
            return
        }
        precondition(threadsPerGrid.width > 0 && threadsPerGrid.height > 0 && threadsPerGrid.depth > 0)
        precondition(threadsPerThreadgroup.width > 0 && threadsPerThreadgroup.height > 0 && threadsPerThreadgroup.depth > 0)
        
        self.needsUpdateBindings = true // to track barriers between resources bound for the compute command

        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func dispatchThreadgroups(_ threadgroupsPerGrid: Size, threadsPerThreadgroup: Size) {
        guard self.currentPipelineReflection != nil else {
            assert(self.currentComputePipeline != nil, "No compute pipeline is set for pass \(renderPass.name).")
            return
        }
        precondition(threadgroupsPerGrid.width > 0 && threadgroupsPerGrid.height > 0 && threadgroupsPerGrid.depth > 0)
        precondition(threadsPerThreadgroup.width > 0 && threadsPerThreadgroup.height > 0 && threadsPerThreadgroup.depth > 0)
        
        self.needsUpdateBindings = true // to track barriers between resources bound for the compute command
        
        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func dispatchThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        guard self.currentPipelineReflection != nil else {
            assert(self.currentComputePipeline != nil, "No compute pipeline is set for pass \(renderPass.name).")
            return
        }
        precondition(threadsPerThreadgroup.width > 0 && threadsPerThreadgroup.height > 0 && threadsPerThreadgroup.depth > 0)
        
        self.needsUpdateBindings = true // to track barriers between resources bound for the compute command
        
        self.updateThreadgroupExecutionWidth(threadsPerThreadgroup: threadsPerThreadgroup)
    }
    
    public func drawMeshThreadgroups(indirectBuffer: Buffer, indirectBufferOffset: Int, threadsPerThreadgroup: Size) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func useResource(_ resource: Resource, access: ResourceAccessFlags) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func useHeap(_ heap: Heap) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func memoryBarrier(scope: BarrierScope) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func memoryBarrier(resources: [Resource]) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
}

public class BlitCommandEncoder : CommandEncoder {

    @usableFromInline let passRecord: RenderPassRecord
    let blitRenderPass : BlitRenderPass
    
    init(renderPass: BlitRenderPass, passRecord: RenderPassRecord) {
        self.blitRenderPass = renderPass
        self.passRecord = passRecord
        
        assert(passRecord.pass === renderPass)
        
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.pushDebugGroup(passRecord.name)
#endif
    }
    
    @usableFromInline func endEncoding() {
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.popDebugGroup() // Pass Name
#endif
    }
    
    public var label : String = "" {
        didSet {
            self.setLabel(label)
        }
    }
    
    public func pushDebugGroup(_ groupName: String) {
        
    }
    
    public func popDebugGroup() {
        
    }
    
    func setLabel(_ label: String) {
        
    }
    
    public func insertDebugSignpost(_ string: String) {
        
    }
    
    public func copy(from sourceBuffer: Buffer, sourceOffset: Int, sourceBytesPerRow: Int, sourceBytesPerImage: Int, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin, options: BlitOption = []) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func copy(from sourceBuffer: Buffer, sourceOffset: Int, to destinationBuffer: Buffer, destinationOffset: Int, size: Int) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationBuffer: Buffer, destinationOffset: Int, destinationBytesPerRow: Int, destinationBytesPerImage: Int, options: BlitOption = []) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func copy(from sourceTexture: Texture, sourceSlice: Int, sourceLevel: Int, sourceOrigin: Origin, sourceSize: Size, to destinationTexture: Texture, destinationSlice: Int, destinationLevel: Int, destinationOrigin: Origin) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func fill(buffer: Buffer, range: Range<Int>, value: UInt8) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func generateMipmaps(for texture: Texture) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func synchronize(buffer: Buffer) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func synchronize(texture: Texture) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    public func synchronize(texture: Texture, slice: Int, level: Int) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
}

public class ExternalCommandEncoder : CommandEncoder {
    @usableFromInline let passRecord: RenderPassRecord
    let externalRenderPass : ExternalRenderPass
    
    init(renderPass: ExternalRenderPass, passRecord: RenderPassRecord) {
        self.externalRenderPass = renderPass
        self.passRecord = passRecord
        
        assert(passRecord.pass === renderPass)
        
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.pushDebugGroup(passRecord.name)
#endif
    }
    
    @usableFromInline func endEncoding() {
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.popDebugGroup() // Pass Name
#endif
    }
    
    public var label : String = "" {
        didSet {
            self.setLabel(label)
        }
    }
    
    public func pushDebugGroup(_ groupName: String) {
        
    }
    
    public func popDebugGroup() {
        
    }
    
    func setLabel(_ label: String) {
        
    }
    
    public func insertDebugSignpost(_ string: String) {
        
    }
    
    func encodeCommand(_ command: (_ commandBuffer: UnsafeRawPointer) -> Void) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    #if canImport(Metal)
    
    public func encodeToMetalCommandBuffer(_ command: @escaping (_ commandBuffer: MTLCommandBuffer) -> Void) {
        self.encodeCommand({ (cmdBuffer) in
            command(Unmanaged<MTLCommandBuffer>.fromOpaque(cmdBuffer).takeUnretainedValue())
        })
    }
    
    #endif
    
    #if canImport(MetalPerformanceShaders)
    
    @available(OSX 10.14, *)
    public func encodeRayIntersection(intersector: MPSRayIntersector, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCount: Int, accelerationStructure: MPSAccelerationStructure) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    @available(OSX 10.14, *)
    public func encodeRayIntersection(intersector: MPSRayIntersector, intersectionType: MPSIntersectionType, rayBuffer: Buffer, rayBufferOffset: Int, intersectionBuffer: Buffer, intersectionBufferOffset: Int, rayCountBuffer: Buffer, rayCountBufferOffset: Int, accelerationStructure: MPSAccelerationStructure) {
        preconditionFailure("\(#function) needs concrete implementation")
    }
    
    #endif
}

@available(macOS 11.0, iOS 14.0, *)
public class AccelerationStructureCommandEncoder : CommandEncoder {
    
    @usableFromInline let passRecord: RenderPassRecord
    let accelerationStructureRenderPass : AccelerationStructureRenderPass
    
    init(accelerationStructureRenderPass: AccelerationStructureRenderPass, passRecord: RenderPassRecord) {
        self.accelerationStructureRenderPass = accelerationStructureRenderPass
        self.passRecord = passRecord
        
        assert(passRecord.pass === renderPass)
        
        self.pushDebugGroup(passRecord.name)
    }
    
    @usableFromInline func endEncoding() {
        self.popDebugGroup() // Pass Name
    }
    
    public var label : String = "" {
        didSet {
            self.setLabel(label)
        }
    }
    
    public func pushDebugGroup(_ groupName: String) {
        
    }
    
    public func popDebugGroup() {
        
    }
    
    func setLabel(_ label: String) {
        
    }
    
    public func insertDebugSignpost(_ string: String) {
        
    }
    
    public func build(accelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, scratchBuffer: Buffer, scratchBufferOffset: Int) {
        accelerationStructure.descriptor = descriptor
    }
    
    
    public func build(accelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor) {
        let scratchBuffer = Buffer(length: descriptor.sizes.buildScratchBufferSize, storageMode: .private)
        self.build(accelerationStructure: accelerationStructure, descriptor: descriptor, scratchBuffer: scratchBuffer, scratchBufferOffset: 0)
    }

    public func refit(sourceAccelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, destinationAccelerationStructure: AccelerationStructure?, scratchBuffer: Buffer, scratchBufferOffset: Int) {
        
        if let destinationStructure = destinationAccelerationStructure {
            sourceAccelerationStructure.descriptor = nil
            destinationStructure.descriptor = descriptor
        } else {
            sourceAccelerationStructure.descriptor = descriptor
        }
    }
    
    public func refit(sourceAccelerationStructure: AccelerationStructure, descriptor: AccelerationStructureDescriptor, destinationAccelerationStructure: AccelerationStructure?) {
        let scratchBuffer = Buffer(length: descriptor.sizes.refitScratchBufferSize, storageMode: .private)
        self.refit(sourceAccelerationStructure: sourceAccelerationStructure, descriptor: descriptor, destinationAccelerationStructure: destinationAccelerationStructure, scratchBuffer: scratchBuffer, scratchBufferOffset: 0)
    }
    
    public func copy(sourceAccelerationStructure: AccelerationStructure, destinationAccelerationStructure: AccelerationStructure) {
        destinationAccelerationStructure.descriptor = sourceAccelerationStructure.descriptor
    }

        // vkCmdWriteAccelerationStructuresPropertiesKHR
    public func writeCompactedSize(of accelerationStructure: AccelerationStructure, to buffer: Buffer, offset: Int) {
        preconditionFailure("\(#function) needs concrete implementation")
    }

        
    public func copyAndCompact(sourceAccelerationStructure: AccelerationStructure, destinationAccelerationStructure: AccelerationStructure) {
        destinationAccelerationStructure.descriptor = sourceAccelerationStructure.descriptor
    }

}
