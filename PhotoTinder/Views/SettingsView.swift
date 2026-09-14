import SwiftUI
import Photos

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    var accessTitle: String {
        switch model.library.authorization {
        case .notDetermined: "Not Requested"
        case .authorized: "Full Access"
        case .limited: "Selected Photos"
        case .denied: "Denied"
        case .restricted: "Restricted"
        @unknown default: "Unavailable"
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    LabeledContent("Photo Access", value: accessTitle)
                    if model.library.authorization == .limited {
                        Button("Manage Selected Photos") { model.library.manageLimitedSelection() }
                    }
                    if model.library.authorization == .notDetermined {
                        Button("Choose Photo Access") { Task { await model.library.requestAuthorization() } }
                    } else {
                        Button("Open Photo Access Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    }
                }
                Section {
                    Toggle("Haptics", isOn: $model.haptics)
                    Toggle("Protect Favorites", isOn: $model.protectFavorites)
                } footer: {
                    Text("Protected favorites stay out of new sessions. Keeping an item never changes its favorite status in Photos.")
                }
                Section {
                    Button("Reset Review History", role: .destructive) { confirmReset = true }.accessibilityIdentifier("resetHistory")
                    if model.persistenceFailed { Button("Retry Saving Progress") { Task { await model.retrySave() } } }
                } footer: {
                    Text("Resetting returns kept and queued items to unreviewed and ends your saved session. It never deletes photos.")
                }
                Section("Private by design") {
                    Text("Your decisions stay on this iPhone. Photo Tinder has no accounts, analytics, ads, or photo uploads. Photos may retrieve media from iCloud when you view it.")
                    Text("A left swipe only adds to your review queue. Deletion requires your confirmation here and in Photos.")
                    Text("Deleted items remain recoverable in Photos → Recently Deleted for up to 30 days. iCloud Photos syncs deletions across your devices. Swipe Undo cannot restore a deleted item.")
                    Link("About deleting and recovering photos", destination: URL(string: "https://support.apple.com/104967")!)
                }.font(.subheadline)
                Section { Text("Photo Tinder").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Reset review history?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset Review History", role: .destructive) { Task { await model.resetHistory() } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Your queue, keep decisions, and session will be cleared. Nothing will be deleted from Photos.") }
        }
    }
}
