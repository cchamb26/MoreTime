import SwiftUI
import AVFoundation

struct VoiceInputView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = AudioRecorder()
    @State private var permissionGranted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Waveform visualization
                WaveformView(level: recorder.audioLevel, isActive: recorder.isRecording)
                    .frame(height: 80)
                    .padding(.horizontal, 40)

                // Status text
                Text(recorder.isRecording ? "Listening..." : "Tap and hold to record")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Record button
                Button {
                    // Toggle recording
                } label: {
                    Circle()
                        .fill(recorder.isRecording ? .red : .primary)
                        .frame(width: 80, height: 80)
                        .overlay {
                            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                .font(.title)
                                .foregroundStyle(recorder.isRecording ? Color.white : Color(.systemBackground))
                        }
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.1)
                        .onEnded { _ in
                            startRecording()
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { _ in
                            if recorder.isRecording {
                                stopAndSend()
                            }
                        }
                )
                .sensoryFeedback(.impact, trigger: recorder.isRecording)

                if chatStore.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Processing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .navigationTitle("Voice Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await requestMicPermission()
            }
        }
    }

    private func requestMicPermission() async {
        let status = AVAudioApplication.shared.recordPermission
        switch status {
        case .granted:
            permissionGranted = true
        case .undetermined:
            permissionGranted = await AVAudioApplication.requestRecordPermission()
        default:
            permissionGranted = false
        }
    }

    private func startRecording() {
        guard permissionGranted else { return }
        Task {
            _ = await recorder.startRecording()
        }
    }

    private func stopAndSend() {
        guard let url = recorder.stopRecording() else { return }
        Task {
            await chatStore.sendVoice(audioURL: url)
            recorder.deleteRecording()
            dismiss()
        }
    }
}

struct WaveformView: View {
    let level: Float
    let isActive: Bool

    private let barCount = 20

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary.opacity(0.3)))
                    .frame(width: 3, height: barHeight(for: i))
                    .animation(.easeInOut(duration: 0.1), value: level)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard isActive else { return 4 }
        let center = Float(barCount) / 2
        let distance = abs(Float(index) - center) / center
        let base: Float = 0.2
        let amplitude = max(base, level * (1 - distance * 0.5))
        return CGFloat(amplitude * 80)
    }
}
