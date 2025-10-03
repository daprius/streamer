## iPhone → PC RTMP streaming to OBS (Virtual Camera)

### iOS setup
- **Dependency**: Add `HaishinKit` via Swift Package Manager
  - Xcode → Project → Package Dependencies → `https://github.com/shogo4405/HaishinKit.swift`
  - Add to the `streamer` target
- **Privacy keys**: Add to `Info.plist`
  - `NSCameraUsageDescription` = "Camera access is required for streaming"
  - `NSMicrophoneUsageDescription` = "Microphone access is required for streaming"
- Build/Run on a real device. The app shows a live preview and Start/Stop buttons.

### PC side (Windows/macOS/Linux)
Option A (Windows quickstart): MediaMTX local RTMP server

1) Download MediaMTX for Windows: `https://github.com/bluenviron/mediamtx/releases`
   - Run `mediamtx.exe` (allow on Windows Firewall). It listens on `rtmp://<PC_IP>:1935`.

2) In the iPhone app, set the URL to `rtmp://<PC_IP>/live/stream`.

3) In OBS: Sources → + → Media Source → uncheck Local File → Input: `rtmp://127.0.0.1/live/stream` → OK.

4) Tools → Start Virtual Camera. Use the OBS Virtual Camera in your YOLO pipeline.

Option B: Nginx with RTMP module (Windows/macOS/Linux)
1) Install Nginx with RTMP module (Windows: prebuilt, macOS: `brew install nginx-full --with-rtmp-module` via third-party taps, Linux: distro packages or compile)

Example `nginx.conf` snippet:

```conf
rtmp {
    server {
        listen 1935;
        chunk_size 4096;
        application live {
            live on;
            record off;
        }
    }
}
```

Run Nginx, ensure port 1935 is open on your firewall.

2) In OBS, add a Media Source with Input: `rtmp://<PC_IP>/live/stream` or add an RTMP input via plugin. Alternatively, add a VLC source pointing to the RTMP URL.

3) Turn on OBS Virtual Camera (Tools → Start Virtual Camera). Now anything in OBS can be used as a webcam in apps.

Option B: Use an external RTMP service (e.g. `rtmp://a.rtmp.youtube.com/live2/<key>`) and pull into OBS via a browser/source. For low latency on local network, prefer local Nginx RTMP.

### Notes
- Ensure iPhone and PC are on the same network. Use the PC IP, not hostname.
- Default settings: 720p30, ~1.8Mbps video, 64kbps audio. Adjust in `StreamingManager`.
- The text field accepts either a full RTMP URL with stream key at the end, or a base URL plus you can modify code to separate key.

