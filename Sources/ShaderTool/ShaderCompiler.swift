//
//  File.swift
//  
//
//  Created by Thomas Roughton on 30/11/19.
//

import Foundation
import Regex
import SPIRV_Cross

// Need to perform reflection for each SPIR-V target and combine conditionally (e.g. with #if canImport(Vulkan)).

struct EntryPoint : Hashable {
    var name: String
    var type: ShaderType
    var renderPass : String
}

struct ShaderSourceFile : Equatable {
    static let entryPointPattern = Regex(#"\[shader\(\"(\w+)\"\)\]\s*(?:\[[^\]]+\])*\s*\w+\s([^\(]+)"#)
    static let externalEntryPointPattern = Regex(#"USES-SHADER:\s+(\S+)"#)
    
    let url : URL
    let renderPass : String
    let modificationTime : Date
    let entryPoints : [EntryPoint]
    let externalEntryPoints : Set<String> // Entry points from used from another source file.
    
    init(url: URL) throws {
        self.url = url
        self.modificationTime = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        let renderPass = url.deletingPathExtension().lastPathComponent
        self.renderPass = renderPass
        
        let fileText = try String(contentsOf: url)
        self.entryPoints = ShaderSourceFile.entryPointPattern.allMatches(in: fileText).compactMap { match in
            guard let shaderTypeString = match.captures[0] else { print("No shader type specified for file \(url)"); return nil }
            guard let shaderType = ShaderType(string: shaderTypeString) else { print("Unrecognised shader type \(shaderTypeString) for file \(url)"); return nil }
            return EntryPoint(name: match.captures[1]!, type: shaderType, renderPass: renderPass)
        }
        self.externalEntryPoints = Set(ShaderSourceFile.externalEntryPointPattern.allMatches(in: fileText).map { match in
            return match.captures[0]!
        })
    }
    
    static func ==(lhs: ShaderSourceFile, rhs: ShaderSourceFile) -> Bool {
        return lhs.url == rhs.url && lhs.entryPoints == rhs.entryPoints && lhs.externalEntryPoints == rhs.externalEntryPoints
    }
}

struct SPIRVFile {
    let sourceFile : ShaderSourceFile
    let url : URL
    let entryPoint : EntryPoint
    let target : Target
    let modificationTime : Date
    
    init(sourceFile: ShaderSourceFile, url: URL, entryPoint: EntryPoint, target: Target) {
        self.sourceFile = sourceFile
        self.url = url
        self.entryPoint = entryPoint
        self.target = target
        self.modificationTime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
    
    var exists : Bool {
        return FileManager.default.fileExists(atPath: self.url.path)
    }
}

extension SPIRVFile : CustomStringConvertible {
    var description: String {
        return "SPIRVFile { renderPass: \(sourceFile.renderPass), entryPoint: \(entryPoint.name), target: \(target) }"
    }
}

extension FileManager {
    func createDirectoryIfNeeded(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
}

extension URL {
    func needsGeneration(sourceFile: URL) -> Bool {
        let sourceFileDate = (try? sourceFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture
        
        let modificationDate = (try? self.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return modificationDate < sourceFileDate
    }
    
    func needsGeneration(sourceFileDate: Date) -> Bool {
        let modificationDate = (try? self.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return modificationDate < sourceFileDate
    }
}

enum ShaderCompilerError : Error {
    case missingSourceDirectory(URL)
}

final class ShaderCompiler {
    let baseDirectory : URL
    let sourceDirectory : URL
    let reflectionFile : URL?
    let sourceFiles : [ShaderSourceFile]
    let targets : [Target]
    
    let dxcDriver : DXCDriver
    let spirvOptDriver : SPIRVOptDriver
    
    let context = SPIRVContext()
    let reflectionContext = ReflectionContext()
    
    var spirvCompilers : [SPIRVCompiler] = []
    
    init(directory: URL, reflectionFile: URL? = nil, targets: [Target] = [.defaultTarget]) throws {
        self.baseDirectory = directory
        self.sourceDirectory = directory.appendingPathComponent("Source/RenderPasses")
        self.reflectionFile = reflectionFile
        self.targets = targets

        self.dxcDriver = try DXCDriver()
        self.spirvOptDriver = try SPIRVOptDriver()
        
        guard FileManager.default.fileExists(atPath: self.sourceDirectory.path) else {
            throw ShaderCompilerError.missingSourceDirectory(self.sourceDirectory)
        }
        
        for target in targets {
            let spirvDirectory = self.baseDirectory.appendingPathComponent(target.spirvDirectory)
            try FileManager.default.createDirectoryIfNeeded(at: spirvDirectory)
        }
        
        let directoryContents = try FileManager.default.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .nameKey], options: [])
        let mostRecentModificationDate = directoryContents.lazy.map { (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantFuture }.min() ?? .distantFuture
        
        if let reflectionFile = reflectionFile,
            FileManager.default.fileExists(atPath: reflectionFile.path),
            let reflectionModificationDate = try? reflectionFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
            mostRecentModificationDate < reflectionModificationDate {
            self.sourceFiles = []
        } else {
            self.sourceFiles = directoryContents.compactMap {
                try? ShaderSourceFile(url: $0)
            }
        }
    }
    
    public func compile() {
        guard !self.sourceFiles.isEmpty else { return }
        
        let spvCompilationGroup = DispatchGroup()
        
        var spirvFiles = [SPIRVFile]()
        
        for target in targets {
            for file in self.sourceFiles {
                for entryPoint in file.entryPoints {
                    spirvFiles.append(self.compileToSPV(file: file, entryPoint: entryPoint, target: target, group: spvCompilationGroup))
                }
            }
        }
        
        spvCompilationGroup.wait()
        self.spirvCompilers = spirvFiles.compactMap { file in
            guard file.exists else { return nil }
            do {
                return try SPIRVCompiler(file: file, context: self.context)
            } catch {
                print("Error generating SPIRV compiler for file \(file): \(error)")
                return nil
            }
        }
        
        for target in self.targets {
            guard let compiler = target.compiler else { continue }
            let targetCompilers = self.spirvCompilers.filter { $0.file.target == target }
            do {
                try compiler.compile(spirvCompilers: targetCompilers, to: self.baseDirectory.appendingPathComponent(target.outputDirectory), withDebugInformation: false)
            }
            catch {
                print("Compilation failed for target \(target): \(error)")
            }
        }
    }
    
    public func generateReflection() {
        guard let reflectionFile = self.reflectionFile, !self.sourceFiles.isEmpty else { return }
        
        for compiler in self.spirvCompilers {
            do {
                try self.reflectionContext.reflect(compiler: compiler)
            } catch {
                print("Error generating reflection for file \(compiler.file): \(error)")
            }
        }
        
        self.reflectionContext.mergeExternalEntryPoints()
        self.reflectionContext.generateDescriptorSets()
        self.reflectionContext.fillTypeLookup()
        
        do {
            try self.reflectionContext.printReflection(to: reflectionFile)
        } catch {
            print("Error generating reflection: \(error)")
        }
    }
    
    private func compileToSPV(file: ShaderSourceFile, entryPoint: EntryPoint, target: Target, group: DispatchGroup) -> SPIRVFile {
        let spirvDirectory = self.baseDirectory.appendingPathComponent(target.spirvDirectory)
        
        let fileName = file.url.deletingPathExtension().lastPathComponent
        let spvFileURL = spirvDirectory.appendingPathComponent("\(fileName)-\(entryPoint.name).spv")
        
        if spvFileURL.needsGeneration(sourceFileDate: file.modificationTime) {
            DispatchQueue.global().async(group: group) {
                let tempFileURL = spirvDirectory.appendingPathComponent("\(fileName)-\(entryPoint.name)-tmp.spv")
                do {
                    let task = try self.dxcDriver.compile(sourceFile: file.url, destinationFile: tempFileURL, entryPoint: entryPoint.name, type: entryPoint.type)
                    task.waitUntilExit()
                    guard task.terminationStatus == 0 else { print("Error compiling entry point \(entryPoint.name) in file \(file): \(task.terminationReason)"); return }
                    
                    let optimisationTask = try self.spirvOptDriver.optimise(sourceFile: tempFileURL, destinationFile: spvFileURL)
                    optimisationTask.waitUntilExit()
                    guard optimisationTask.terminationStatus == 0 else { print("Error optimising entry point \(entryPoint.name) in file \(file): \(task.terminationReason)"); return }
                    
                    try? FileManager.default.removeItem(at: tempFileURL)
                    
                } catch {
                    print("Error compiling entry point \(entryPoint.name) in file \(file): \(error)")
                }
            }
        }
        
        return SPIRVFile(sourceFile: file, url: spvFileURL, entryPoint: entryPoint, target: target)
    }
}