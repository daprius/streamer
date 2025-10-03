//
//  ContentView.swift
//  streamer
//
//  Created by Prius on 10/2/25.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var manager = StreamingManager()
    @State private var rtmpURL: String = "rtmp://10.0.0.59:1935/iphone_stream"
    @State private var showingSettings = false
    @State private var isAnimating = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color(.secondarySystemBackground)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Live Streamer")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.primary)
                                    
                                    Text("Professional streaming made simple")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: { showingSettings.toggle() }) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.title2)
                                        .foregroundStyle(.primary)
                                        .frame(width: 44, height: 44)
                                        .background(Color(.systemGray6))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        
                        // Camera Preview Card
                        VStack(spacing: 0) {
                            CameraPreviewView(manager: manager)
                                .aspectRatio(16.0/9.0, contentMode: .fit) // Landscape aspect ratio for 720p
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(
                                            manager.isStreaming ? 
                                            LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing) :
                                            LinearGradient(colors: [.gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: manager.isStreaming ? 3 : 1
                                        )
                                )
                                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                            
                            // Status indicator
                            HStack {
                                Circle()
                                    .fill(manager.isStreaming ? .green : .gray)
                                    .frame(width: 8, height: 8)
                                    .scaleEffect(manager.isStreaming ? (isAnimating ? 1.2 : 1.0) : 1.0)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
                                
                                Text(manager.isStreaming ? "LIVE" : "Ready")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(manager.isStreaming ? .green : .secondary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                            .padding(.top, -8)
                        }
                        .padding(.horizontal, 20)
                        
                        // URL Input Card
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Stream Configuration")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            
                            VStack(spacing: 8) {
                                TextField("RTMP URL", text: $rtmpURL)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(.systemGray6))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                
                                Text("Example: rtmp://your-server:1935/app/streamkey")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(20)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                        .padding(.horizontal, 20)
                        
                        // Control Buttons
                        VStack(spacing: 12) {
                            // Start/Stop Button
                            Button(action: {
                                if manager.isStreaming {
                                    stop()
                                } else {
                                    start()
                                }
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: manager.isStreaming ? "stop.fill" : "play.fill")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                    
                                    Text(manager.isStreaming ? "Stop Stream" : "Start Stream")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    LinearGradient(
                                        colors: manager.isStreaming ? [.red, .orange] : [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .scaleEffect(manager.isStreaming ? 1.0 : (isAnimating ? 1.05 : 1.0))
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isAnimating)
                            }
                            .disabled(false)
                            .shadow(color: manager.isStreaming ? .red.opacity(0.3) : .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                            
                            // Reset Button (only show if there are issues)
                            if manager.lastStatusMessage.contains("❌") || manager.lastStatusMessage.contains("Error") {
                                Button(action: reset) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.title3)
                                        
                                        Text("Reset")
                                            .font(.headline)
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(Color.gray)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Status Message
                        if !manager.lastStatusMessage.isEmpty {
                            HStack {
                                Image(systemName: statusIcon)
                                    .foregroundStyle(statusColor)
                                
                                Text(manager.lastStatusMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(statusColor)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(statusColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 20)
                    }
                }
            }
        }
        .onAppear {
            manager.requestPermissions { granted in
                if granted {
                    manager.attachDevices()
                }
            }
            startPulseAnimation()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(rtmpURL: $rtmpURL)
        }
    }
    
    private var statusIcon: String {
        if manager.lastStatusMessage.contains("✅") || manager.lastStatusMessage.contains("Connected") {
            return "checkmark.circle.fill"
        } else if manager.lastStatusMessage.contains("❌") || manager.lastStatusMessage.contains("Error") {
            return "exclamationmark.triangle.fill"
        } else if manager.lastStatusMessage.contains("🔄") || manager.lastStatusMessage.contains("Connecting") {
            return "arrow.clockwise"
        } else {
            return "info.circle.fill"
        }
    }
    
    private var statusColor: Color {
        if manager.lastStatusMessage.contains("✅") || manager.lastStatusMessage.contains("Connected") {
            return .green
        } else if manager.lastStatusMessage.contains("❌") || manager.lastStatusMessage.contains("Error") {
            return .red
        } else if manager.lastStatusMessage.contains("🔄") || manager.lastStatusMessage.contains("Connecting") {
            return .blue
        } else {
            return .secondary
        }
    }
    
    private func startPulseAnimation() {
        isAnimating = true
    }
    
    private func start() {
        withAnimation(.easeInOut(duration: 0.3)) {
            manager.startStreaming(to: rtmpURL)
        }
    }
    
    private func stop() {
        withAnimation(.easeInOut(duration: 0.3)) {
            manager.stopStreaming()
        }
    }
    
    private func reset() {
        withAnimation(.easeInOut(duration: 0.3)) {
            manager.resetStreaming()
        }
    }
}

// Settings View
struct SettingsView: View {
    @Binding var rtmpURL: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Stream Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.bottom, 10)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("RTMP URL")
                        .font(.headline)
                    
                    TextField("Enter RTMP URL", text: $rtmpURL)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Text("This is where your stream will be sent. Make sure your MediaMTX server is running on this address.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
