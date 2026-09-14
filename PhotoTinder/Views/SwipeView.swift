import SwiftUI

struct SwipeView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let item = model.currentItem {
                    SwipeItemView(item: item, model: model).id(item.id)
                } else {
                    ContentUnavailableView {
                        Label(model.review.session == nil ? "Nothing to Review" : "That's this session.", systemImage: "checkmark.circle")
                    } description: {
                        Text("\(model.review.session?.completedCount ?? 0) reviewed · \(model.review.session?.skippedCount ?? 0) skipped\nSkipped items will be available in your next session.")
                    } actions: {
                        Button("Review Queue") { model.selectedTab = 1; dismiss() }
                            .buttonStyle(.borderedProminent).foregroundStyle(Color("OnAccentColor"))
                        if model.review.canUndo {
                            Button("Undo Last Decision") { model.undo() }
                                .disabled(model.persistenceFailed || model.isDeleting || model.isUpdatingProgress)
                        }
                        Button("Back to Clean") { dismiss() }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(model.review.session?.title ?? "Clean Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close Session", systemImage: "xmark") { dismiss() }.accessibilityIdentifier("closeSession")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.selectedTab = 1; dismiss() } label: { Label("\(model.review.queueCount)", systemImage: "tray") }
                        .accessibilityLabel("Review queue, \(model.review.queueCount) items").accessibilityIdentifier("sessionQueue")
                }
            }
        }.onDisappear { model.library.clearPrefetch() }
    }
}

struct SwipeItemView: View {
    let item: MediaItem
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var loader: MediaLoader
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.28, dampingFraction: 0.8))) private var drag = CGSize.zero
    @State private var inspecting = false
    @State private var committed = false

    init(item: MediaItem, model: AppModel) {
        self.item = item
        self.model = model
        _loader = State(initialValue: model.library.makeLoader())
    }
    private var canAct: Bool { !committed && !model.persistenceFailed && !model.isDeleting && !model.isUpdatingProgress }
    var ready: Bool { loader.image != nil && !loader.isLoading && loader.errorMessage == nil && canAct }
    var body: some View {
        GeometryReader { geometry in
            if dynamicType.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: 16) {
                        sessionProgress
                        mediaCard.frame(height: geometry.size.height * 0.35)
                        mediaMetadata
                    }.padding(.vertical, 8)
                }
                .safeAreaInset(edge: .bottom) {
                    decisionControls.padding(.vertical, 8).background(.bar)
                }
            } else {
                VStack(spacing: 12) {
                    sessionProgress
                    mediaCard
                    mediaMetadata
                    decisionControls
                }.padding(.top, 8).padding(.bottom, 4)
            }
        }
        .fullScreenCover(isPresented: $inspecting) { InspectionView(item: item, library: model.library) }
        .onDisappear { loader.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { loader.pause() } }
    }

    private var sessionProgress: some View {
        VStack(spacing: 7) {
            if let session = model.review.session {
                Text("\(session.cursor + 1) of \(session.totalCount) · \(session.completedCount) reviewed")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).accessibilityIdentifier("sessionProgress")
                ProgressView(value: Double(session.cursor), total: Double(max(1, session.totalCount))).tint(Color("AccentColor"))
            }
        }.padding(.horizontal, 24)
    }

    private var mediaCard: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground))
                    .padding(.horizontal, 12).offset(y: 7).accessibilityHidden(true)
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground))
                    if let player = loader.player {
                        VideoSurface(player: player).clipShape(.rect(cornerRadius: 18))
                    } else if let image = loader.image {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(.rect(cornerRadius: 14)).padding(4)
                    }
                    if abs(drag.width) > 12 {
                        VStack {
                            HStack {
                                Label(drag.width > 0 ? "Keep" : "Delete", systemImage: drag.width > 0 ? "checkmark" : "trash")
                                    .font(.title2.weight(.bold)).padding(14)
                                    .foregroundStyle(drag.width > 0 ? Color("AccentColor") : Color.red)
                                    .background(.regularMaterial, in: .capsule)
                                    .opacity(min(1, abs(drag.width) / 95))
                                Spacer()
                            }
                            Spacer()
                        }.padding(20).allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .offset(x: drag.width, y: reduceMotion ? 0 : drag.height * 0.1)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(drag.width / 35)))
                .transaction { if reduceMotion { $0.animation = nil } }
                .simultaneousGesture(DragGesture(minimumDistance: 20)
                    .updating($drag) { value, state, transaction in
                        transaction.animation = nil
                        guard ready, !inspecting, isHorizontal(value.translation) else { return }
                        state = value.translation
                    }
                    .onEnded { value in
                        guard ready, !inspecting, isHorizontal(value.translation) else { return }
                        let distance = value.translation.width
                        let predicted = value.predictedEndTranslation.width
                        if abs(distance) >= 110 || (abs(distance) > 55 && abs(predicted) > 240 && distance * predicted > 0) {
                            commit(distance > 0 ? .keep : .delete)
                        }
                    })
                .onTapGesture { inspect() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(item.kind.title), \(item.captureDate?.formatted(date: .abbreviated, time: .omitted) ?? "date unavailable")")
                .accessibilityHint("Use the Keep and Delete actions to decide. Double tap to inspect.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { inspect() }
                .accessibilityAction(named: "Keep") { if ready { commit(.keep) } }
                .accessibilityAction(named: "Queue for deletion") { if ready { commit(.delete) } }
                .accessibilityIdentifier("mediaCard")

                if let error = loader.errorMessage {
                    MediaErrorView(message: error, retry: loader.retry)
                } else if loader.isLoading {
                    ProgressView(loader.progress > 0 ? "Loading \(Int(loader.progress * 100))%" : "Loading media…")
                        .padding().background(.regularMaterial, in: .capsule)
                }
            }
            .task(id: [geometry.size.width, geometry.size.height, displayScale]) {
                guard geometry.size.width > 1, geometry.size.height > 1 else { return }
                loader.load(item: item, targetSize: CGSize(width: geometry.size.width * displayScale, height: geometry.size.height * displayScale))
                if let session = model.review.session {
                    model.library.prefetch(ids: Array(session.orderedIDs.dropFirst(session.cursor + 1).prefix(3)), targetSize: CGSize(width: 1200, height: 1600))
                }
            }
        }.padding(.horizontal, 16)
    }

    private var mediaMetadata: some View {
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.captureDate?.formatted(date: .abbreviated, time: .omitted) ?? "Date unavailable")
                    .font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Label(item.kind == .video ? "Video · \(item.durationLabel)" : item.kind.title, systemImage: item.kind.symbol)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if item.isFavorite { Image(systemName: "star.fill").accessibilityLabel("Favorite") }
                        if item.hasLocation { Image(systemName: "mappin").accessibilityLabel("Has saved location") }
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
            if !dynamicType.isAccessibilitySize { Spacer() }
            playbackControls
        }.padding(.horizontal, 24)
    }

    private var playbackControls: some View {
        HStack(spacing: 8) {
            if item.kind == .video {
                Button(loader.isPlaying ? "Pause" : "Play", systemImage: loader.isPlaying ? "pause.fill" : "play.fill") { loader.togglePlayback() }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).disabled(loader.player == nil).accessibilityIdentifier("playVideo")
                Button(loader.isMuted ? "Unmute" : "Mute", systemImage: loader.isMuted ? "speaker.slash" : "speaker.wave.2") { loader.setMuted(!loader.isMuted) }
                    .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).disabled(loader.player == nil)
            }
            Button("Inspect", systemImage: "arrow.up.left.and.arrow.down.right") { inspect() }
                .labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).disabled(loader.image == nil).accessibilityIdentifier("inspect")
        }
    }

    private var decisionControls: some View {
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 14))
        return VStack(spacing: 12) {
            GlassEffectContainer {
                layout {
                    DecisionButton(title: "Delete", symbol: "trash", color: .red) { commit(.delete) }.disabled(!ready).accessibilityIdentifier("deleteCard")
                    Button { loader.pause(); model.undo() } label: {
                        if dynamicType.isAccessibilitySize {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 58)
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.uturn.backward").font(.title3)
                                Text("Undo").font(.caption).fixedSize(horizontal: false, vertical: true)
                            }.frame(minWidth: 60, minHeight: 58)
                        }
                    }.buttonStyle(.glass).disabled(!model.review.canUndo || !canAct).accessibilityIdentifier("undo")
                    DecisionButton(title: "Keep", symbol: "checkmark", color: Color("AccentColor")) { commit(.keep) }.disabled(!ready).accessibilityIdentifier("keepCard")
                }
            }.padding(.horizontal, 22)
            Button("Skip for Now") { commit(.skip) }.font(.subheadline).frame(minHeight: 44).accessibilityIdentifier("skip")
                .disabled(!canAct)
        }
    }

    private func isHorizontal(_ translation: CGSize) -> Bool { abs(translation.width) > abs(translation.height) * 1.25 }
    private func inspect() {
        guard loader.image != nil else { return }
        loader.pause()
        inspecting = true
    }
    private func commit(_ action: ReviewAction) {
        guard canAct, model.review.session?.currentID == item.id, action == .skip || ready else { return }
        committed = true
        loader.pause()
        model.decide(id: item.id, action: action)
    }
}

struct DecisionButton: View {
    let title: String
    let symbol: String
    let color: Color
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        Button(action: action) {
            Group {
                if dynamicType.isAccessibilitySize {
                    Label(title, systemImage: symbol)
                        .font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: symbol).font(.title2)
                        Text(title).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
                .frame(maxWidth: .infinity, minHeight: 58)
        }.buttonStyle(.glass).tint(color).foregroundStyle(color)
    }
}
