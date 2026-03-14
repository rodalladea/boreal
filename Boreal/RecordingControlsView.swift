import SwiftUI

struct RecordingControlsView: View {
    @ObservedObject private var recorder = ScreenRecorder.shared

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(recorder.isRecording ? Color.red : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)

            Text(timeString(recorder.recordingDuration))
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .foregroundStyle(recorder.isRecording ? .primary : .secondary)
                .frame(width: 40, alignment: .leading)

            Spacer()

            Button(action: toggle) {
                Image(systemName: recorder.isRecording ? "stop.fill" : "record.circle.fill")
                    .foregroundStyle(recorder.isRecording ? Color.primary : Color.red)
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .help(recorder.isRecording ? String(localized: "Stop Recording") : String(localized: "Start Recording"))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(in: RoundedRectangle(cornerRadius: 10))
        .padding(4)
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
