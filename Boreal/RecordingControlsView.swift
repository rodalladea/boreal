import AVFoundation
import SwiftUI

struct RecordingControlsView: View {
    @ObservedObject private var recorder = ScreenRecorder.shared
    @ObservedObject private var camera = CameraManager.shared
    @ObservedObject private var mic = MicrophoneManager.shared
    @ObservedObject private var audioMonitor = AudioLevelMonitor.shared

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(recorder.isRecording ? Color.red : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)

            Text(timeString(recorder.recordingDuration))
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundStyle(recorder.isRecording ? .primary : .secondary)
                .frame(width: 40, alignment: .leading)

            // Camera visibility toggle
            Button {
                camera.isCameraVisible.toggle()
            } label: {
                Image(systemName: camera.isCameraVisible ? "video.fill" : "video.slash.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(camera.isCameraVisible ? .secondary : .primary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(camera.isCameraVisible ? String(localized: "Hide Camera") : String(localized: "Show Camera"))

            Spacer()

            // Camera selector
            Menu {
                ForEach(camera.availableCameras, id: \.uniqueID) { device in
                    Button {
                        camera.switchCamera(to: device)
                    } label: {
                        if device.uniqueID == camera.currentCamera?.uniqueID {
                            Label(device.localizedName, systemImage: "checkmark")
                        } else {
                            Text(device.localizedName)
                        }
                    }
                }
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "Select Camera"))

            // Microphone selector
            Menu {
                ForEach(mic.availableMicrophones, id: \.uniqueID) { device in
                    Button {
                        mic.switchMicrophone(to: device)
                    } label: {
                        if device.uniqueID == mic.currentMicrophone?.uniqueID {
                            Label(device.localizedName, systemImage: "checkmark")
                        } else {
                            Text(device.localizedName)
                        }
                    }
                }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "Select Microphone"))

            // Audio level visualizer
            AudioLevelBarsView(level: audioMonitor.level)

            Button(action: toggle) {
                Group {
                    if recorder.isStopping {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle.fill")
                            .foregroundStyle(recorder.isRecording ? Color.primary : Color.red)
                            .font(.system(size: 18))
                    }
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(recorder.isStopping)
            .help(recorder.isStopping ? String(localized: "Finishing…") : recorder.isRecording ? String(localized: "Stop Recording") : String(localized: "Start Recording"))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
        .padding(4)
        .onAppear { audioMonitor.start() }
        .onDisappear { audioMonitor.stop() }
    }

    private func toggle() {
        if recorder.isRecording {
            recorder.stopRecording()
        } else {
            recorder.startRecording()
        }
    }

    private func timeString(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct AudioLevelBarsView: View {
    let level: Float

    private let multipliers: [Double] = [0.6, 1.0, 0.8, 0.65]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(multipliers.indices, id: \.self) { i in
                let height = max(3.0, CGFloat(level) * 14.0 * CGFloat(multipliers[i]))
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(level > 0.04 ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 3, height: height)
                    .animation(.easeOut(duration: 0.06), value: level)
            }
        }
        .frame(width: 20, height: 18, alignment: .center)
    }
}
