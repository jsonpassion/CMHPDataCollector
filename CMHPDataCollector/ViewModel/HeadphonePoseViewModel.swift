//
//  HeadphonePoseViewModel.swift
//  CMHPClassifier
//
//  Created by Jason on 6/9/24.
//

import SwiftUI
import SceneKit
import CoreMotion
import simd
import UIKit
import Combine

class HeadphonePoseViewModel: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    @Published var motionButtonTitle: String = "Start Tracking"
    @Published var isMotionButtonEnabled: Bool = false
    @Published var isReferenceButtonVisible: Bool = false
    @Published var duration: String = "00:00:000"
    @Published var showAlert = false
    @Published var alertMessage = ""
    @Published var savedFiles: [String] = []
    @Published var isCollecting = false
    
    var scene: SCNScene?
    var cameraNode: SCNNode?
    
    private var motionManager = CMHeadphoneMotionManager()
    private var motionData: [MotionData] = []
    private var headNode: SCNNode?
    private var referenceFrame = matrix_identity_float4x4
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var startTime: Date?
    
    struct MotionData: Codable {
        let timestamp: TimeInterval
        let accX: Double
        let accY: Double
        let accZ: Double
        let rotX: Double
        let rotY: Double
        let rotZ: Double
        let pitch: Double
        let roll: Double
        let yaw: Double
        let label: String
    }
    
    override init() {
        super.init()
        motionManager.delegate = self
        loadSavedFiles()
        updateButtonState()
    }
    
    func setupScene() {
        let scene = SCNScene(named: "head.obj")!
        self.scene = scene
        
        headNode = scene.rootNode.childNodes.first
        
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        scene.rootNode.addChildNode(cameraNode)
        
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 2.0)
        cameraNode.camera?.zNear = 0.05
        self.cameraNode = cameraNode
        
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
        scene.rootNode.addChildNode(lightNode)
        
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)
        
        updateButtonState()
    }
    
    private func updateButtonState() {
        isMotionButtonEnabled = motionManager.isDeviceMotionAvailable
                                && CMHeadphoneMotionManager.authorizationStatus() != .denied
        motionButtonTitle = motionManager.isDeviceMotionActive ? "Stop Tracking" : "Start Tracking"
        isReferenceButtonVisible = motionManager.isDeviceMotionActive
    }
    
    func toggleTracking(label: String) {
        // Check the authorization status
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .authorized:
            print("Motion tracking authorized.")
            
        case .restricted:
            print("Motion tracking restricted.")
            return
            
        case .denied:
            print("Motion tracking denied.")
            return
            
        case .notDetermined:
            print("Motion tracking permission not determined.")
            requestPermissionAndStartTracking(label: label)
            return
            
        @unknown default:
            print("Unknown authorization status.")
            return
        }
        
        
        // Start or stop device motion updates based on the current state
        if motionManager.isDeviceMotionActive {
            stopCollecting()
            motionManager.stopDeviceMotionUpdates()
            print("Stopped device motion updates.")
        } else {
            startCollecting(label: label)
            motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { [weak self] maybeDeviceMotion, maybeError in
                guard let self = self, let deviceMotion = maybeDeviceMotion else { return }
                self.headphoneMotionManager(self.motionManager, didUpdate: deviceMotion)
            }
            print("Started device motion updates.")
        }
        
        // Update the button state
        updateButtonState()
    }
    
    private func requestPermissionAndStartTracking(label: String) {
        // Temporarily start device motion updates to trigger permission request
        motionManager.startDeviceMotionUpdates()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.motionManager.stopDeviceMotionUpdates()
            if CMHeadphoneMotionManager.authorizationStatus() == .authorized {
            } else {
                self.alertMessage = "Motion tracking permission not granted."
                self.showAlert = true
            }
        }
    }
    
    func setReferenceFrame() {
        if let deviceMotion = motionManager.deviceMotion {
            referenceFrame = float4x4(rotationMatrix: deviceMotion.attitude.rotationMatrix).inverse
        }
    }
    
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphones did connect")
        updateButtonState()
    }
    
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphones did disconnect")
        updateButtonState()
    }
    
    func headphoneMotionManager(_ motionManager: CMHeadphoneMotionManager, didUpdate deviceMotion: CMDeviceMotion) {
        addMotionDataSampleToArray(motionSample: deviceMotion)
        
        let rotation = float4x4(rotationMatrix: deviceMotion.attitude.rotationMatrix)
        
        let mirrorTransform = simd_float4x4([
            simd_float4(-1.0, 0.0, 0.0, 0.0),
            simd_float4(0.0, 1.0, 0.0, 0.0),
            simd_float4(0.0, 0.0, 1.0, 0.0),
            simd_float4(0.0, 0.0, 0.0, 1.0)
        ])
        
        headNode?.simdTransform = mirrorTransform * rotation * referenceFrame
        
        updateButtonState()
    }
    
    func headphoneMotionManager(_ motionManager: CMHeadphoneMotionManager, didFail error: Error) {
        updateButtonState()
    }
    
    // Aggregating sensor readings
    func addMotionDataSampleToArray(motionSample: CMDeviceMotion) {
        // Add the current motion data reading to the data array
        DispatchQueue.global().async {
            self.motionData.append(MotionData(
                timestamp: Date().timeIntervalSince1970,
                accX: motionSample.userAcceleration.x,
                accY: motionSample.userAcceleration.y,
                accZ: motionSample.userAcceleration.z,
                rotX: motionSample.rotationRate.x,
                rotY: motionSample.rotationRate.y,
                rotZ: motionSample.rotationRate.z,
                pitch: motionSample.attitude.pitch,
                roll: motionSample.attitude.roll,
                yaw: motionSample.attitude.yaw,
                label: ""))
        }
    }
    
    func startCollecting(label: String) {
        motionData.removeAll()
        startTime = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { _ in
            self.updateDuration()
        }
        isCollecting = true
    }
    
    func stopCollecting() {
        timer?.invalidate()
        isCollecting = false
        duration = "00:00:000"
    }
    
    func updateDuration() {
        guard let startTime = startTime else { return }
        let currentTime = Date()
        let elapsedTime = currentTime.timeIntervalSince(startTime)
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let milliseconds = Int((elapsedTime - Double(minutes * 60 + seconds)) * 1000)
        duration = String(format: "%02d:%02d:%03d", minutes, seconds, milliseconds)
    }
    
    func saveCSV(label: String) {
        let sanitizedLabel = label.replacingOccurrences(of: " ", with: "_")
        let fileName = "\(sanitizedLabel)-\(Date().timeIntervalSince1970).csv"
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        
        var csvText = "Timestamp,AccX,AccY,AccZ,RotX,RotY,RotZ,Pitch,Roll,Yaw,Label\n"
        
        for data in motionData {
            let row = "\(data.timestamp),\(data.accX),\(data.accY),\(data.accZ),\(data.rotX),\(data.rotY),\(data.rotZ),\(data.pitch),\(data.roll),\(data.yaw),\(data.label)\n"
            csvText.append(row)
        }
        
        do {
            try csvText.write(to: path, atomically: true, encoding: .utf8)
            alertMessage = "CSV saved at \(path)"
            showAlert = true
            loadSavedFiles()
        } catch {
            alertMessage = "Failed to create CSV file: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    func loadSavedFiles() {
        let fileManager = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        do {
            let files = try fileManager.contentsOfDirectory(atPath: tempDir.path)
            savedFiles = files.filter { $0.hasSuffix(".csv") }
        } catch {
            print("Failed to list saved files: \(error.localizedDescription)")
        }
    }
    
    func deleteFile(named fileName: String) {
        let fileManager = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        do {
            try fileManager.removeItem(at: tempDir)
            loadSavedFiles()
        } catch {
            alertMessage = "Failed to delete file: \(error.localizedDescription)"
            showAlert = true
        }
    }
    
    func removeAllFiles() {
        let fileManager = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        for file in savedFiles {
            let filePath = tempDir.appendingPathComponent(file)
            do {
                try fileManager.removeItem(at: filePath)
            } catch {
                alertMessage = "Failed to delete file: \(error.localizedDescription)"
                showAlert = true
            }
        }
        loadSavedFiles()
    }
    
    func exportFiles() -> [URL] {
        _ = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        return savedFiles.map { tempDir.appendingPathComponent($0) }
    }

}

extension float4x4 {
    init(rotationMatrix r: CMRotationMatrix) {
        self.init([
            simd_float4(Float(-r.m11), Float(r.m13), Float(r.m12), 0.0),
            simd_float4(Float(-r.m31), Float(r.m33), Float(r.m32), 0.0),
            simd_float4(Float(-r.m21), Float(r.m23), Float(r.m22), 0.0),
            simd_float4(0.0, 0.0, 0.0, 1.0)
        ])
    }
}
