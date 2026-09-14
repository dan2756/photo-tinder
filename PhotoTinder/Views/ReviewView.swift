import SwiftUI

struct ReviewView: View {
    @Bindable var model: AppModel
    @State private var selected: Set<String> = []
    @State private var inspection: MediaItem?
    @State private var confirmDeletion = false
    @State private var confirmClear = false
    @State private var submitted: Set<String> = []
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var mutationsDisabled: Bool { model.persistenceFailed || model.isDeleting || model.isUpdatingProgress }
    var body: some View {
        NavigationStack {
            Group {
                if model.review.queueCount == 0 {
                    ContentUnavailableView("Your Queue Is Clear", systemImage: "tray", description: Text("Swipe left while cleaning to set items aside. Review them here before deleting anything."))
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                if !dynamicType.isAccessibilitySize {
                                    Text("A second look.").font(.title3.weight(.semibold))
                                }
                                Text(dynamicType.isAccessibilitySize ? "Select items to delete from Photos." : "Nothing here has been deleted. Select the items you're ready to remove from Photos.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            let selectionLayout = dynamicType.isAccessibilitySize
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                                : AnyLayout(HStackLayout())
                            selectionLayout {
                                Text("\(selected.count) selected").font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("selectionCount")
                                if !dynamicType.isAccessibilitySize { Spacer() }
                                Button(selected.count == model.queue.count ? "Deselect All" : "Select All") {
                                    selected = selected.count == model.queue.count ? [] : Set(model.queue.map(\.id))
                                }.font(.subheadline).accessibilityIdentifier("selectAll")
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicType.isAccessibilitySize ? 140 : 100), spacing: 10)], spacing: 16) {
                                let queuedItems = model.queue
                                ForEach(Array(queuedItems.enumerated()), id: \.element.id) { index, item in
                                    let description = "\(item.kind.title), \(item.captureDate?.formatted(date: .abbreviated, time: .shortened) ?? "date unavailable"), item \(index + 1) of \(queuedItems.count)"
                                    VStack(spacing: 7) {
                                        Button { inspection = item } label: {
                                            ThumbnailView(item: item, library: model.library)
                                                .aspectRatio(0.86, contentMode: .fit)
                                                .overlay(alignment: .bottomLeading) {
                                                    if item.kind == .video {
                                                        Label(item.durationLabel, systemImage: "video.fill").font(.caption2.weight(.medium)).padding(6).foregroundStyle(.white).background(.black.opacity(0.65), in: .capsule).padding(6)
                                                    }
                                                }.clipShape(.rect(cornerRadius: 12))
                                        }.buttonStyle(.plain).accessibilityLabel("Inspect queued \(description)").accessibilityIdentifier("queueThumbnail")
                                        Button {
                                            if !selected.insert(item.id).inserted { selected.remove(item.id) }
                                        } label: {
                                            Label(selected.contains(item.id) ? "Selected" : "Select", systemImage: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.caption).frame(maxWidth: .infinity, minHeight: 44)
                                        }.buttonStyle(.plain)
                                            .accessibilityLabel("\(selected.contains(item.id) ? "Deselect" : "Select") \(description)")
                                            .accessibilityValue(selected.contains(item.id) ? "Selected for deletion" : "Not selected")
                                            .accessibilityIdentifier("selectQueueItem")
                                        Button("Keep Instead") { model.keepInstead([item.id]); selected.remove(item.id) }
                                            .font(.caption).frame(minHeight: 44)
                                            .disabled(mutationsDisabled)
                                            .accessibilityLabel("Keep \(description) instead")
                                            .accessibilityHint("Removes this item from the queue without deleting it.")
                                            .accessibilityIdentifier("keepInstead")
                                    }
                                }
                            }
                            if model.unavailableQueueCount > 0 {
                                Text("\(model.unavailableQueueCount) queued items are currently inaccessible. Their decisions are saved. Restore photo access to review them, or clear the queue to forget those decisions.").font(.footnote).foregroundStyle(.secondary)
                            }
                        }.padding(20)
                    }
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 8) {
                            Button(role: .destructive) {
                                submitted = selected.intersection(Set(model.queue.map(\.id)))
                                confirmDeletion = true
                            } label: {
                                Label("Delete \(selected.count) \(selected.count == 1 ? "Item" : "Items")", systemImage: "trash")
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                            }.buttonStyle(.borderedProminent).tint(.red).disabled(selected.isEmpty || mutationsDisabled)
                                .accessibilityIdentifier("deleteSelected")
                            if model.isDeleting { ProgressView("Waiting for Photos…") }
                        }.padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
                    }
                }
            }
            .navigationTitle("Review")
            .toolbar {
                if model.review.queueCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Keep Selected Instead", systemImage: "checkmark") { model.keepInstead(selected); selected = [] }.disabled(selected.isEmpty)
                            Button("Clear Queue", systemImage: "tray") { confirmClear = true }
                        } label: { Label("Queue Actions", systemImage: "ellipsis") }.disabled(mutationsDisabled).accessibilityIdentifier("queueActions")
                    }
                }
            }
            .disabled(model.isDeleting)
            .alert("Delete \(submitted.count) \(submitted.count == 1 ? "item" : "items") from Photos?", isPresented: $confirmDeletion) {
                Button("Delete \(submitted.count) \(submitted.count == 1 ? "Item" : "Items") from Photos", role: .destructive) {
                    let ids = submitted
                    Task { await model.delete(ids) }
                }.disabled(mutationsDisabled)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Photos will ask you to confirm. Deleted items move to Recently Deleted for up to 30 days. With iCloud Photos, deletion also syncs to your other devices.")
            }
            .confirmationDialog("Clear the queue?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Queue", role: .destructive) { model.clearQueue(); selected = [] }.disabled(mutationsDisabled)
                Button("Cancel", role: .cancel) { }
            } message: { Text("No photos will be deleted. All queued items will become unreviewed again.") }
            .fullScreenCover(item: $inspection) { item in InspectionView(item: item, library: model.library) }
            .onChange(of: model.queue.map(\.id)) { _, ids in selected.formIntersection(ids) }
        }
    }
}
