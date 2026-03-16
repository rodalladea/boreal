# Boreal

A minimal floating camera overlay and screen recorder for macOS. Keep your webcam visible in a small window that stays on top of everything while you record your screen.

## Features

- Floating camera window that stays on top of all apps and spaces
- Screen recording with configurable resolution (Native, 1440p, 1080p, 720p) and frame rate (15, 24, 30, 60 fps)
- System audio and microphone recording
- Camera and microphone selector directly in the control panel
- Audio level visualizer showing microphone activity in real time
- Switch between multiple cameras via the menu bar (Cmd+1, Cmd+2, …) or the control panel
- Control panel excluded from screen capture — it never appears in your recordings
- Draggable — move the camera overlay anywhere on your screen
- No window chrome, just your camera with rounded corners
- Automatically repositions when your display setup changes
- Detects cameras and microphones being plugged in or unplugged

## Requirements

- macOS 14.0+
- A camera (built-in or external)

## Installation

1. Clone the repository
2. Open `Boreal.xcodeproj` in Xcode
3. Build and run (Cmd+R)

## Usage

Launch the app and the camera overlay appears in the top-right corner of your screen. Drag it wherever you want.

The control panel sits just below the camera. Use it to:

- **Select camera** — click the camera icon to pick from available devices
- **Select microphone** — click the mic icon to pick from available devices
- **Monitor audio** — the animated bars show whether your microphone is capturing sound
- **Record** — click the red button to start, click again to stop

Use the **Record** menu in the menu bar to configure resolution, FPS, system audio, and microphone before recording.

Recordings are saved to `~/Movies/Boreal/`.

## License

[MIT](LICENSE)
