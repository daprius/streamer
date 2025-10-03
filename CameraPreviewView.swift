//
//  CameraPreviewView.swift
//  streamer
//
//  Created by Prius on 10/2/25.
//

import SwiftUI
import AVFoundation
import HaishinKit

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var manager: StreamingManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = UIColor.black
        
        // Create a placeholder label that will be replaced by camera preview
        let label = UILabel()
        label.text = "Camera Preview\n(Tap Start to begin streaming)"
        label.textColor = UIColor.white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        label.tag = 999 // Tag to identify and remove later
        
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        // Attach the preview from StreamingManager
        DispatchQueue.main.async {
            self.manager.attachPreview(to: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update view if needed
        uiView.backgroundColor = UIColor.black
        
        // Update MTHKView frame when view bounds change
        DispatchQueue.main.async {
            uiView.subviews.forEach { subview in
                if let hkView = subview as? MTHKView {
                    hkView.frame = uiView.bounds
                }
            }
        }
    }
}


