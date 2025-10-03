//
//  StreamingManager.swift
//  streamer
//
//  Created by Prius on 10/2/25.
//

import Foundation
import AVFoundation
import Combine
import UIKit
import HaishinKit
import VideoToolbox

final class StreamingManager: NSObject, ObservableObject {
    @Published var isStreaming: Bool = false
    @Published var lastStatusMessage: String = ""
    
    // HaishinKit components - using weak references to prevent retain cycles
    private let rtmpConnection = RTMPConnection()
    private let rtmpStream: RTMPStream
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    // Connection monitoring with proper cleanup
    private var connectionTimer: Timer?
    private var isInitialConnection = true
    private var isDestroyed = false
    
    // Thread safety
    private let streamingQueue = DispatchQueue(label: "com.streamer.rtmp", qos: .userInitiated)
    private let statusQueue = DispatchQueue.main
    
    // Resource management
    private var attachedCamera: AVCaptureDevice?
    private var attachedMicrophone: AVCaptureDevice?
    
    override init() {
        rtmpStream = RTMPStream(connection: rtmpConnection)
        super.init()
        setupRTMPConnection()
        setupRTMPStream()
    }
    
    deinit {
        cleanup()
    }
    
    private func setupRTMPConnection() {
        // Configure RTMP connection for ULTRA LOW LATENCY (OBS-style)
        rtmpConnection.addEventListener(.rtmpStatus, selector: #selector(rtmpStatusHandler), observer: self)
        
        // ULTRA LOW LATENCY RTMP settings
        rtmpConnection.objectEncoding = RTMPObjectEncoding.amf0  // AMF0 for compatibility
    }
    
    @objc private func rtmpStatusHandler(_ notification: Notification) {
        // HaishinKit 1.9.9 uses Event type
        guard let event = notification.userInfo?["event"] as? Event else { return }
        
        print("RTMP Status: \(event)")
        DispatchQueue.main.async {
            if let data = event.data as? [String: Any],
               let code = data["code"] as? String {
                switch code {
                case "NetConnection.Connect.Success":
                    self.lastStatusMessage = "✅ Connected to server"
                case "NetConnection.Connect.Rejected":
                    self.lastStatusMessage = "❌ Connection rejected"
                case "NetConnection.Connect.Failed":
                    self.lastStatusMessage = "❌ Connection failed"
                default:
                    self.lastStatusMessage = "RTMP: \(code)"
                }
            }
        }
    }
    
    private func setupCaptureSession() {
        // HaishinKit will handle the capture session internally
        // We just need to ensure permissions are granted
        lastStatusMessage = "Capture session ready"
    }
    
    private func setupRTMPStream() {
        // ULTRA LOW LATENCY configuration (OBS-style)
        var videoSettings = VideoCodecSettings()
        videoSettings.bitRate = 800_000 // 800 kbps - lower bitrate = less buffering
        rtmpStream.videoSettings = videoSettings
        
        var audioSettings = AudioCodecSettings()
        audioSettings.bitRate = 48_000 // 48 kbps - minimal audio bitrate
        rtmpStream.audioSettings = audioSettings
        
        // ULTRA LOW LATENCY settings (like OBS)
        rtmpStream.frameRate = 30
        rtmpStream.sessionPreset = .hd1280x720
        rtmpStream.videoOrientation = .landscapeRight
        
        print("Stream configured for ULTRA LOW LATENCY (OBS-style)")
        updateStatus("Stream ready - ultra low latency")
    }
    
    // MARK: - Thread-safe status updates
    private func updateStatus(_ message: String) {
        statusQueue.async { [weak self] in
            guard let self = self, !self.isDestroyed else { return }
            self.lastStatusMessage = message
        }
    }

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var cameraGranted = false
        var micGranted = false

        group.enter()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            cameraGranted = granted
            group.leave()
        }

        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            micGranted = granted
            group.leave()
        }

        group.notify(queue: .main) {
            completion(cameraGranted && micGranted)
        }
    }

    func attachDevices() {
        // Devices are already attached in setupCaptureSession
        lastStatusMessage = "Camera and audio ready"
    }

    func attachPreview(to view: UIView) {
        // Ensure this runs on main thread for UI operations
        statusQueue.async { [weak self] in
            guard let self = self, !self.isDestroyed else { return }
            
            // Set up the view for HaishinKit's preview
            view.backgroundColor = UIColor.black
            
            // Remove any existing placeholder labels
            view.subviews.forEach { subview in
                if subview.tag == 999 {
                    subview.removeFromSuperview()
                }
            }
            
            // Remove any existing MTHKView to prevent memory leaks
            view.subviews.forEach { subview in
                if let hkView = subview as? MTHKView {
                    hkView.attachStream(nil) // Detach stream first
                    hkView.removeFromSuperview()
                }
            }
            
            // Create and configure the HaishinKit view for proper aspect ratio
            let hkView = MTHKView(frame: view.bounds)
            hkView.videoGravity = .resizeAspect // Show full video without cropping
            hkView.attachStream(self.rtmpStream)
            
            // Optimize for performance
            hkView.layer.masksToBounds = true
            hkView.layer.cornerRadius = 16
            
            // Add the HaishinKit view to the container view
            view.addSubview(hkView)
            
            // Set up auto layout constraints
            hkView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hkView.topAnchor.constraint(equalTo: view.topAnchor),
                hkView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                hkView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                hkView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            
            print("HaishinKit preview view attached successfully with performance optimizations")
        }
    }

    func startStreaming(to urlOrBase: String, streamKey: String? = nil) {
        guard !isStreaming else { return }
        
        // IMMEDIATE UI update - no blocking operations
        isStreaming = true
        updateStatus("Starting stream...")
        
        // Move ALL heavy operations to background thread
        streamingQueue.async { [weak self] in
            guard let self = self, !self.isDestroyed else { return }
            
            // Parse URL on background thread
            guard let url = URL(string: urlOrBase) else {
                self.updateStatus("Invalid RTMP URL")
                self.statusQueue.async { self.isStreaming = false }
                return
            }
            
            // Extract connection details
            let host = url.host ?? "localhost"
            let port = url.port ?? 1935
            let app = url.pathComponents.count > 1 ? url.pathComponents[1] : "live"
            let streamKey = url.lastPathComponent
            
            print("🎥 Streaming Configuration:")
            print("   Host: \(host)")
            print("   Port: \(port)")
            print("   App: \(app)")
            print("   Stream Key: \(streamKey)")
            
            // Configure audio session on background thread
            self.configureAudioSession()
            
            // Update status
            self.updateStatus("Connecting to \(host):\(port)...")
            
            // Connect to RTMP server
            let connectionURL = "rtmp://\(host):\(port)/\(app)"
            print("🔗 Connecting to: \(connectionURL)")
            
            self.rtmpConnection.connect(connectionURL)
            
            // Attach camera and audio AFTER connection (lazy loading)
            self.attachCameraAndAudio()
            
            // Publish immediately when ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.rtmpConnection.connected {
                    self.rtmpStream.publish(streamKey)
                    self.updateStatus("✅ Connected and streaming")
                    print("📡 Publishing stream: \(streamKey)")
                    self.isInitialConnection = false
                    self.startConnectionMonitoring()
                } else {
                    // Quick retry
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if self.rtmpConnection.connected {
                            self.rtmpStream.publish(streamKey)
                            self.updateStatus("✅ Connected and streaming")
                            self.isInitialConnection = false
                            self.startConnectionMonitoring()
                        } else {
                            self.updateStatus("❌ Connection failed")
                            self.isStreaming = false
                        }
                    }
                }
            }
        }
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try audioSession.setActive(true)
            
            // ULTRA LOW LATENCY audio (like OBS)
            try audioSession.setPreferredSampleRate(44100)
            try audioSession.setPreferredIOBufferDuration(0.005) // 5ms buffer - minimal latency
        } catch {
            print("Audio session configuration error: \(error)")
        }
    }
    
    private func attachCameraAndAudio() {
        // LIGHTWEIGHT camera attachment - minimal configuration
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            self.attachedCamera = camera
            
            // MINIMAL camera configuration for speed
            do {
                try camera.lockForConfiguration()
                camera.videoZoomFactor = 1.0 // No zoom
                camera.unlockForConfiguration()
            } catch {
                print("Camera config error: \(error)")
            }
            
            // Attach camera immediately
            self.rtmpStream.attachCamera(camera) { [weak self] _, error in
                if let error = error {
                    print("Camera error: \(error)")
                } else {
                    print("Camera attached")
                }
            }
        }
        
        // Attach audio
        if let microphone = AVCaptureDevice.default(for: .audio) {
            self.attachedMicrophone = microphone
            self.rtmpStream.attachAudio(microphone) { [weak self] _, error in
                if let error = error {
                    print("Audio error: \(error)")
                } else {
                    print("Audio attached")
                }
            }
        }
    }

    func stopStreaming() {
        guard isStreaming else { return }
        
        streamingQueue.async { [weak self] in
            guard let self = self, !self.isDestroyed else { return }
            
            // Stop connection monitoring
            self.stopConnectionMonitoring()
            
            // Detach devices to free resources
            self.detachDevices()
            
            // Stop RTMP streaming
            self.rtmpStream.close()
            self.rtmpConnection.close()
            
            // Reset state on main thread
            self.statusQueue.async {
                self.isStreaming = false
                self.isInitialConnection = true
                self.updateStatus("Stopped")
            }
            
            print("Streaming stopped and resources cleaned up")
        }
    }
    
    func resetStreaming() {
        // Force reset everything to prevent crashes
        stopConnectionMonitoring()
        detachDevices()
        rtmpConnection.close()
        rtmpStream.close()
        
        statusQueue.async { [weak self] in
            guard let self = self, !self.isDestroyed else { return }
            self.isStreaming = false
            self.isInitialConnection = true
            self.updateStatus("Ready to stream")
        }
        print("Streaming reset")
    }
    
    // MARK: - Resource Management
    private func detachDevices() {
        // Detach camera
        if attachedCamera != nil {
            rtmpStream.attachCamera(nil) { _, _ in }
            attachedCamera = nil
        }
        
        // Detach audio
        if attachedMicrophone != nil {
            rtmpStream.attachAudio(nil) { _, _ in }
            attachedMicrophone = nil
        }
    }
    
    private func cleanup() {
        isDestroyed = true
        stopConnectionMonitoring()
        detachDevices()
        rtmpConnection.close()
        rtmpStream.close()
    }
    
    // MARK: - Connection Monitoring
    private func startConnectionMonitoring() {
        stopConnectionMonitoring() // Ensure no duplicate timers
        
        statusQueue.async { [weak self] in
            guard let self = self, !self.isDestroyed else { return }
            
            self.connectionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.checkConnectionStatus()
            }
        }
    }
    
    private func stopConnectionMonitoring() {
        statusQueue.async { [weak self] in
            self?.connectionTimer?.invalidate()
            self?.connectionTimer = nil
        }
    }
    
    private func checkConnectionStatus() {
        guard !isDestroyed else { return }
        
        // Check if we're still connected
        if rtmpConnection.connected {
            updateStatus("✅ Connected and streaming")
            print("✅ RTMP Connection is active")
        } else if isInitialConnection {
            // Still trying to connect initially
            updateStatus("🔄 Connecting...")
            print("🔄 Still connecting...")
        } else {
            // Connection lost after initial connection
            updateStatus("⚠️ Connection lost - check network")
            print("⚠️ RTMP Connection lost - not auto-reconnecting to avoid conflicts")
        }
    }
}

// MARK: - RTMP Connection Status Handling
extension StreamingManager {
    // Note: Modern HaishinKit uses different status handling
    // For now, we'll use simple status updates
    private func updateConnectionStatus(_ status: String) {
        DispatchQueue.main.async {
            self.lastStatusMessage = status
        }
    }
}


