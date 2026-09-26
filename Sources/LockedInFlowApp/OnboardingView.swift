import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var permissionTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                permissionsPage.tag(1)
                modelPage.tag(2)
            }
            .tabViewStyle(.automatic)

            Divider()

            HStack {
                if page > 0 {
                    Button("Back") { page -= 1 }
                }
                Spacer()
                if page < 2 {
                    Button("Continue") { page += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start Dictating") {
                        state.completeOnboarding()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!state.canDictate)
                }
            }
            .padding(16)
        }
        .onAppear { startPermissionPolling() }
        .onDisappear { permissionTimer?.invalidate() }
    }

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color(nsColor: .systemTeal))
            Text("Private voice input that runs\nentirely on your Mac.")
                .font(.title3)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                Label("Audio never leaves this device", systemImage: "lock.shield")
                Label("Uses only pre-provisioned, verified models", systemImage: "wifi.slash")
                Label(
                    "No accounts, analytics upload, or telemetry",
                    systemImage: "eye.slash"
                )
                Label(
                    "Dictation history stays in memory until quit by default",
                    systemImage: "memorychip")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private var permissionsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Two permissions are required.")
                .font(.title3)
            permissionRow(
                title: "Microphone",
                detail: "Captures your voice for on-device transcription.",
                granted: state.microphoneAuthorized,
                action: { state.requestMicrophoneAccess() }
            )
            permissionRow(
                title: "Accessibility",
                detail: "Inserts text at your cursor and blocks password fields.",
                granted: state.accessibilityTrusted,
                action: { state.requestAccessibilityAccess() }
            )
            Text(
                "Accessibility identifies the focused editor, refuses secure fields, and inserts text. If you enable Learn from edits, LockedIn Flow briefly re-reads only the exact field it just wrote so it can learn a correction; that value stays in memory on this Mac."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private func permissionRow(
        title: String, detail: String, granted: Bool, action: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(
                    granted ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)
                )
                .font(.title3)
            VStack(alignment: .leading) {
                Text(title).bold()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant", action: action)
            }
        }
    }

    private var modelPage: some View {
        VStack(spacing: 16) {
            Spacer()
            if state.modelReady {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color(nsColor: .systemGreen))
                Text("Speech model ready.")
                    .font(.title3)
                Text(state.modelStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(activationInstructions)
                    .multilineTextAlignment(.center)
                    .font(.callout)
            } else {
                if state.modelSwitchInProgress {
                    ProgressView()
                        .controlSize(.large)
                    Text(state.modelStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Checking the provisioned model against the reviewed manifest…")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                    Text(state.errorMessage ?? state.modelStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(
                        "LockedIn Flow does not download models at runtime. Install the reviewed offline model bundle, or ask your administrator to provision it, then verify again."
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    Button("Verify Model") {
                        Task { await state.prepareModel() }
                    }
                }
            }
            Spacer()
        }
        .padding()
    }

    private var activationInstructions: String {
        if state.activationTrigger == .keyboard, state.activationMode == .hold {
            return
                "Hold \(state.activationHint) anywhere while you speak, then release — text lands at your cursor."
        }
        return
            "Use \(state.activationHint) anywhere to start, speak, then use it again to stop — text lands at your cursor."
    }

    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in state.refreshPermissions() }
        }
    }
}
