import cv2
import argparse
import json
import os
from ultralytics import YOLO
import time
from typing import List, Dict, Optional
import tkinter as tk
from tkinter import messagebox
import threading

class NDIObjectDetector:
    def __init__(self, config_file: str = "detector_config.json"):
        self.config_file = config_file
        self.model = None
        self.cap = None
        self.class_names = {}
        self.config = self.load_config()
        self.detection_stats = {"total_detections": 0, "target_detections": 0}
        self.paused = False
        self.show_help = True
        self.last_notification_time = 0
        self.notification_cooldown = 5  # seconds between notifications
        
    def load_config(self) -> Dict:
        """Load configuration from file or create default"""
        default_config = {
            "model_path": "yolov8n.pt",
            "confidence_threshold": 0.5,
            "target_classes": ["person"],
            "video_source": -1,  # -1 means auto-detect
            "ndi_sources": [],
            "display_size": (1280, 720),
            "show_all_detections": False,
            "save_detections": False,
            "output_file": "detections.json"
        }
        
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                    # Merge with defaults for any missing keys
                    for key, value in default_config.items():
                        if key not in config:
                            config[key] = value
                    return config
            except Exception as e:
                print(f"Error loading config: {e}. Using defaults.")
                return default_config
        else:
            self.save_config(default_config)
            return default_config
    
    def save_config(self, config: Dict = None):
        """Save current configuration to file"""
        if config is None:
            config = self.config
        try:
            with open(self.config_file, 'w') as f:
                json.dump(config, f, indent=2)
        except Exception as e:
            print(f"Error saving config: {e}")
    
    def discover_ndi_sources(self) -> List[str]:
        """Discover available NDI sources"""
        # This is a simplified version - in practice, you'd use NDI SDK
        # For now, we'll check common video capture indices
        sources = []
        print("Scanning for available video sources...")
        
        for i in range(20):  # Check first 20 indices
            try:
                cap = cv2.VideoCapture(i)
                if cap.isOpened():
                    ret, frame = cap.read()
                    if ret and frame is not None:
                        # Get some info about the source
                        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
                        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
                        fps = cap.get(cv2.CAP_PROP_FPS)
                        sources.append(f"Source {i} ({width}x{height} @ {fps:.1f}fps)")
                        print(f"Found: Source {i} - {width}x{height} @ {fps:.1f}fps")
                cap.release()
            except Exception as e:
                # Silently continue if there's an error with this index
                pass
        
        if not sources:
            print("No video sources found. You may need to:")
            print("1. Connect your iPhone with NDI")
            print("2. Install NDI runtime")
            print("3. Check if OBS Virtual Camera is running")
            print("4. Try different source indices manually")
        
        return sources
    
    def select_video_source(self) -> int:
        """Allow user to select video source"""
        print("\nAvailable video sources:")
        sources = self.discover_ndi_sources()
        
        if not sources:
            print("No video sources found. Using default (0)")
            return 0
        
        for i, source in enumerate(sources):
            print(f"{i}: {source}")
        
        while True:
            try:
                choice = input(f"Select source (0-{len(sources)-1}) or press Enter for default: ").strip()
                if not choice:
                    return 0
                choice = int(choice)
                if 0 <= choice < len(sources):
                    return choice
                else:
                    print("Invalid choice. Please try again.")
            except ValueError:
                print("Please enter a valid number.")
    
    def load_model(self, model_path: str):
        """Load YOLO model"""
        try:
            self.model = YOLO(model_path)
            self.class_names = self.model.names
            print(f"Model loaded: {model_path}")
            print(f"Available classes: {list(self.class_names.values())}")
        except Exception as e:
            print(f"Error loading model: {e}")
            return False
        return True
    
    def initialize_camera(self, source: int):
        """Initialize video capture"""
        self.cap = cv2.VideoCapture(source)
        if not self.cap.isOpened():
            print(f"Failed to open video source {source}")
            return False
        
        # Set camera properties for better performance
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.config["display_size"][0])
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.config["display_size"][1])
        self.cap.set(cv2.CAP_PROP_FPS, 30)
        
        print(f"Camera initialized: {self.cap.get(cv2.CAP_PROP_FRAME_WIDTH)}x{self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT)}")
        return True
    
    def process_frame(self, frame) -> tuple:
        """Process frame with object detection"""
        if self.model is None:
            return frame, []
        
        results = self.model(frame)[0]
        detections = []
        
        for box in results.boxes:
            cls_id = int(box.cls[0])
            cls_name = self.class_names[cls_id].lower()
            conf = box.conf[0].item()
            
            if conf >= self.config["confidence_threshold"]:
                coords = box.xyxy[0].cpu().numpy().astype(int)
                x1, y1, x2, y2 = coords
                
                detection = {
                    "class": cls_name,
                    "confidence": conf,
                    "bbox": [x1, y1, x2, y2],
                    "timestamp": time.time()
                }
                detections.append(detection)
                
                # Check if it's a target class
                is_target = cls_name in [tc.lower() for tc in self.config["target_classes"]]
                
                # Show notification for person detection with cooldown
                if cls_name == "person" and is_target:
                    current_time = time.time()
                    if current_time - self.last_notification_time >= self.notification_cooldown:
                        self.show_notification(f"confidence: {conf:.2f}")
                        self.last_notification_time = current_time
                
                if is_target or self.config["show_all_detections"]:
                    color = (0, 255, 0) if is_target else (255, 0, 0)
                    cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
                    label = f"{cls_name} {conf:.2f}"
                    if is_target:
                        label += " [TARGET]"
                    cv2.putText(frame, label, (x1, y1 - 10),
                              cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
        
        return frame, detections
    
    def draw_ui_overlay(self, frame):
        """Draw UI overlay with controls and stats"""
        height, width = frame.shape[:2]
        
        # Semi-transparent overlay
        overlay = frame.copy()
        cv2.rectangle(overlay, (10, 10), (400, 200), (0, 0, 0), -1)
        cv2.addWeighted(overlay, 0.7, frame, 0.3, 0, frame)
        
        # Display information
        y_offset = 30
        cv2.putText(frame, f"Target: {', '.join(self.config['target_classes'])}", 
                   (20, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
        y_offset += 25
        
        cv2.putText(frame, f"Confidence: {self.config['confidence_threshold']:.2f}", 
                   (20, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
        y_offset += 25
        
        cv2.putText(frame, f"Detections: {self.detection_stats['target_detections']}", 
                   (20, y_offset), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
        y_offset += 25
        
        if self.paused:
            cv2.putText(frame, "PAUSED", (20, y_offset), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2)
            y_offset += 30
        
        if self.show_help:
            cv2.putText(frame, "Controls:", (20, y_offset), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1)
            y_offset += 20
            cv2.putText(frame, "SPACE: Pause/Resume", (20, y_offset), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
            y_offset += 15
            cv2.putText(frame, "H: Toggle Help", (20, y_offset), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
            y_offset += 15
            cv2.putText(frame, "C: Change Confidence", (20, y_offset), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
            y_offset += 15
            cv2.putText(frame, "T: Change Target", (20, y_offset), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
            y_offset += 15
            cv2.putText(frame, "S: Save Config", (20, y_offset), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
            y_offset += 15
            cv2.putText(frame, "Q: Quit", (20, y_offset), 
                       cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
    
    def handle_keyboard_input(self, key: int) -> bool:
        """Handle keyboard input and return True if should continue"""
        if key == ord('q'):
            return False
        elif key == ord(' '):  # Space bar
            self.paused = not self.paused
            print(f"{'Paused' if self.paused else 'Resumed'}")
        elif key == ord('h'):
            self.show_help = not self.show_help
        elif key == ord('c'):
            self.change_confidence()
        elif key == ord('t'):
            self.change_target()
        elif key == ord('s'):
            self.save_config()
            print("Configuration saved!")
        return True
    
    def change_confidence(self):
        """Change confidence threshold"""
        print(f"\nCurrent confidence threshold: {self.config['confidence_threshold']}")
        print("Enter new confidence threshold (0.0-1.0) or press Enter to keep current:")
        print("(Type in the console window, not the video window)")
        
        try:
            new_conf_input = input("Confidence (0.0-1.0): ").strip()
            if new_conf_input:
                new_conf = float(new_conf_input)
                if 0.0 <= new_conf <= 1.0:
                    self.config['confidence_threshold'] = new_conf
                    print(f"Confidence threshold set to {new_conf}")
                else:
                    print("Confidence must be between 0.0 and 1.0")
            else:
                print("Keeping current confidence threshold")
        except ValueError:
            print("Invalid input, keeping current confidence threshold")
        except (EOFError, KeyboardInterrupt):
            print("Input cancelled, keeping current confidence threshold")
        
        print("Settings updated! Video continues...")
    
    def change_target(self):
        """Change target classes"""
        print(f"\nCurrent targets: {self.config['target_classes']}")
        print("Available classes:", list(self.class_names.values())[:10], "...")
        print("Enter new target classes (comma-separated) or press Enter to keep current:")
        print("(Type in the console window, not the video window)")
        
        try:
            new_targets = input("Target classes: ").strip()
            if new_targets:
                self.config['target_classes'] = [t.strip().lower() for t in new_targets.split(',')]
                print(f"Target classes set to: {self.config['target_classes']}")
            else:
                print("Keeping current targets")
        except (EOFError, KeyboardInterrupt):
            print("Input cancelled, keeping current targets")
        
        print("Settings updated! Video continues...")
    
    def show_notification(self, detection_info: str):
        """Show notification message box in a separate thread"""
        def show_message():
            try:
                # Create a hidden root window for the messagebox
                root = tk.Tk()
                root.withdraw()  # Hide the main window
                root.attributes('-topmost', True)  # Bring to front
                
                messagebox.showinfo("Person Detected!", 
                                  f"Person detected with {detection_info}\n"
                                  f"Time: {time.strftime('%H:%M:%S')}")
                root.destroy()
            except Exception as e:
                print(f"Error showing notification: {e}")
        
        # Run notification in a separate thread to avoid blocking the main loop
        notification_thread = threading.Thread(target=show_message)
        notification_thread.daemon = True
        notification_thread.start()
    
    def save_detections(self, detections: List[Dict]):
        """Save detections to file if enabled"""
        if self.config["save_detections"] and detections:
            try:
                with open(self.config["output_file"], 'a') as f:
                    for detection in detections:
                        f.write(json.dumps(detection) + '\n')
            except Exception as e:
                print(f"Error saving detections: {e}")
    
    def run(self):
        """Main detection loop"""
        print("NDI Object Detector")
        print("=" * 50)
        
        # Load model
        if not self.load_model(self.config["model_path"]):
            return
        
        # Select video source
        if self.config["video_source"] == -1:  # Auto-detect
            source = self.select_video_source()
        else:
            source = self.config["video_source"]
        
        # Initialize camera
        if not self.initialize_camera(source):
            return
        
        print("\nStarting detection...")
        print("Press 'h' for help, 'q' to quit")
        
        try:
            while True:
                if not self.paused:
                    ret, frame = self.cap.read()
                    if not ret:
                        print("Failed to read frame")
                        break
                    
                    # Process frame
                    processed_frame, detections = self.process_frame(frame)
                    
                    # Update stats
                    self.detection_stats["total_detections"] += len(detections)
                    target_detections = [d for d in detections if d["class"] in [tc.lower() for tc in self.config["target_classes"]]]
                    self.detection_stats["target_detections"] += len(target_detections)
                    
                    # Save detections if enabled
                    self.save_detections(detections)
                else:
                    # When paused, still read frame but don't process
                    ret, frame = self.cap.read()
                    if not ret:
                        break
                    processed_frame = frame
                
                # Draw UI overlay
                self.draw_ui_overlay(processed_frame)
                
                # Display frame
                cv2.imshow("NDI Object Detection", processed_frame)
                
                # Handle keyboard input
                key = cv2.waitKey(1) & 0xFF
                if not self.handle_keyboard_input(key):
                    break
                    
        except KeyboardInterrupt:
            print("\nInterrupted by user")
        finally:
            if self.cap:
                self.cap.release()
            cv2.destroyAllWindows()
            print(f"Detection stats: {self.detection_stats}")

def main():
    parser = argparse.ArgumentParser(description="NDI Object Detection with YOLO")
    parser.add_argument("--config", default="detector_config.json", help="Configuration file")
    parser.add_argument("--model", help="YOLO model path")
    parser.add_argument("--source", type=int, help="Video source index")
    parser.add_argument("--confidence", type=float, help="Confidence threshold")
    parser.add_argument("--targets", help="Target classes (comma-separated)")
    
    args = parser.parse_args()
    
    detector = NDIObjectDetector(args.config)
    
    # Override config with command line arguments
    if args.model:
        detector.config["model_path"] = args.model
    if args.source is not None:
        detector.config["video_source"] = args.source
    if args.confidence is not None:
        detector.config["confidence_threshold"] = args.confidence
    if args.targets:
        detector.config["target_classes"] = [t.strip().lower() for t in args.targets.split(',')]
    
    detector.run()

if __name__ == "__main__":
    main()
