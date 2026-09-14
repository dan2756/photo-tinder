import SwiftUI
import Photos

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView(selection: $model.selectedTab) {
            Tab("Clean", systemImage: "square.stack", value: 0) { CleanView(model: model) }
            Tab("Review", systemImage: "tray", value: 1) { ReviewView(model: model) }
                .badge(model.review.queueIDs.count)
        }
        .task { await model.load() }
        .onChange(of: model.library.revision) { model.reconcile() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.library.refresh() } }
        }
        .fullScreenCover(isPresented: $model.showSession) { SwipeView(model: model) }
        .alert("Photo Tinder", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}

struct CleanView: View {
    @Bindable var model: AppModel
    @State private var settings = false
    @State private var emptyCategory: MediaCategory?
    private var mutationsDisabled: Bool { model.persistenceFailed || model.isDeleting || model.isUpdatingProgress }
    var body: some View {
        NavigationStack {
            Group {
                if !model.isReady {
                    ProgressView("Opening library…")
                } else if !model.hasAccess {
                    PhotoAccessView(model: model)
                } else {
                    libraryList
                }
            }
            .navigationTitle("Clean Up")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { settings = true }
                        .accessibilityIdentifier("settings")
                }
            }
            .sheet(isPresented: $settings) { SettingsView(model: model) }
            .sheet(item: $emptyCategory) { category in EmptyCategoryView(category: category, isLimited: model.library.authorization == .limited) }
        }
    }

    private var libraryList: some View {
        List {
            if model.library.authorization == .limited {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Selected Photos", systemImage: "photo.badge.checkmark").font(.headline)
                        Text("Counts include only the photos and videos you shared.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Manage Selection") { model.library.manageLimitedSelection() }
                    }.padding(.vertical, 4)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "shuffle").font(.title2).foregroundStyle(Color("AccentColor"))
                            .frame(width: 44, height: 44).background(Color("AccentColor").opacity(0.1), in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("A little less clutter.").font(.title3.weight(.semibold))
                            Text("A random mix of your photos and videos.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Button { model.start(category: .all) } label: {
                        Label("Shuffle Library", systemImage: "shuffle").frame(maxWidth: .infinity).padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large).foregroundStyle(Color("OnAccentColor"))
                    .disabled(model.eligible.isEmpty || mutationsDisabled)
                    .accessibilityIdentifier("shuffle")
                    if let session = model.review.session, session.currentID != nil || session.canUndo {
                        Button { model.showSession = true } label: {
                            Label("Continue Session", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }.disabled(model.isDeleting || model.isUpdatingProgress).accessibilityIdentifier("continueSession")
                    }
                }.padding(.vertical, 8)
            } footer: {
                Text(model.protectFavorites ? "Favorites are protected. Kept and queued items stay out of new sessions." : "Kept and queued items stay out of new sessions.")
            }
            Section("Browse by category") {
                ForEach(MediaCategory.allCases.filter { $0 != .all }, id: \.self) { category in
                    let items = category.filter(model.eligible)
                    if category == .places {
                        NavigationLink { PlacesView(model: model) } label: {
                            CategoryRow(category: category, count: items.count, item: items.first, library: model.library)
                        }.accessibilityIdentifier("category-places")
                    } else {
                        Button {
                            if items.isEmpty { emptyCategory = category }
                            else { model.start(category: category) }
                        } label: {
                            HStack {
                                CategoryRow(category: category, count: items.count, item: items.first, library: model.library)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!items.isEmpty && mutationsDisabled).accessibilityIdentifier("category-\(category.rawValue)")
                    }
                }
            }
            if model.library.items.isEmpty {
                Section { ContentUnavailableView("No Accessible Media", systemImage: "photo.on.rectangle", description: Text("Add photos or videos to Photos, or update your selected photos in Settings.")) }
            } else if model.eligible.isEmpty {
                Section { Text("You're caught up. Add more photos, clear your queue, or reset review history to start again.").foregroundStyle(.secondary) }
            }
            if let error = model.library.errorMessage { Section { Text(error).foregroundStyle(.secondary); Button("Retry") { Task { await model.library.refresh() } } } }
        }
        .refreshable { await model.library.refresh() }
    }
}

struct CategoryRow: View {
    let category: MediaCategory
    let count: Int
    let item: MediaItem?
    let library: PhotoLibrary
    var subtitle: String? {
        switch category {
        case .recent: "Captured in the past 30 days"
        case .older: "Captured more than one year ago"
        case .places: "Grouped by saved photo locations"
        default: nil
        }
    }
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill))
                if let item { ThumbnailView(item: item, library: library) }
                else { Image(systemName: category.symbol).font(.title3).foregroundStyle(.secondary) }
            }.frame(width: 50, height: 50).clipShape(.rect(cornerRadius: 10)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 4)
            Text(count, format: .number).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }.padding(.vertical, 3).accessibilityElement(children: .combine)
            .accessibilityLabel("\(category.title), \(count) items left to review")
    }
}

struct PhotoAccessView: View {
    let model: AppModel
    var body: some View {
        ContentUnavailableView {
            Label(model.library.authorization == .notDetermined ? "Make room for what matters." : "Photo Access Needed", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(model.library.authorization == .restricted ? "Photo access is restricted on this iPhone. Check the device's restrictions with its owner or administrator." : "Review one photo at a time. Nothing is deleted until you review your queue and confirm.")
        } actions: {
            if model.library.authorization == .notDetermined {
                Button("Choose Photo Access") { Task { await model.library.requestAuthorization() } }
                    .buttonStyle(.borderedProminent).controlSize(.large).foregroundStyle(Color("OnAccentColor")).accessibilityIdentifier("requestAccess")
            } else if model.library.authorization != .restricted {
                Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                    .buttonStyle(.borderedProminent).foregroundStyle(Color("OnAccentColor"))
            }
        }
    }
}

struct PlacesView: View {
    let model: AppModel
    var body: some View {
        List {
            Section {
                Text("Groups use locations already saved with your photos. Coordinates are approximate; your current location is never requested.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(PlaceGroup.groups(from: model.eligible)) { group in
                Button { model.start(category: .places, items: group.items, title: group.title) } label: {
                    HStack {
                        Label(group.title, systemImage: "mappin.and.ellipse")
                        Spacer()
                        Text("\(group.items.count)").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }.disabled(model.persistenceFailed || model.isDeleting || model.isUpdatingProgress)
                    .accessibilityLabel("\(group.title), \(group.items.count) items left to review")
                    .accessibilityValue("\(group.items.count) items")
                    .accessibilityIdentifier("placeGroup")
            }
            if PlaceGroup.groups(from: model.eligible).isEmpty {
                ContentUnavailableView("No Saved Locations", systemImage: "mappin.slash", description: Text("Eligible photos with location metadata will appear here."))
            }
        }.navigationTitle("Places")
    }
}

struct EmptyCategoryView: View {
    let category: MediaCategory
    let isLimited: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ContentUnavailableView("No \(category.title) to Review", systemImage: category.symbol, description: Text("\(category.subtitle). No eligible items are available\(isLimited ? " in your selected photos" : ""). Kept, queued, and protected favorites are excluded. Your saved session is unchanged."))
                .navigationTitle(category.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}
