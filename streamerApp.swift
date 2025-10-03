//
//  streamerApp.swift
//  streamer
//
//  Created by Prius on 10/2/25.
//

import SwiftUI
import AVFoundation

@main
struct streamerApp: App {
    init() {
        // Ensure audio can play/record while screen is locked if needed
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
