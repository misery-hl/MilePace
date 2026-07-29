import PhotosUI
import SwiftUI
import UIKit

struct RunShareButton: View {
    let record: RunRecord

    @State private var isComposerPresented = false

    var body: some View {
        Button {
            isComposerPresented = true
        } label: {
            Label("Share \(record.activityKind.displayName)", systemImage: "square.and.arrow.up")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                .foregroundStyle(.black)
        }
        .accessibilityHint("Opens the share card composer")
        .fullScreenCover(isPresented: $isComposerPresented) {
            RunShareComposer(record: record, isPresented: $isComposerPresented)
        }
    }
}

private struct RunShareComposer: View {
    let record: RunRecord
    @Binding var isPresented: Bool

    @State private var selectedStyle: ShareCanvasStyle = .brandedMap
    @State private var photoItem: PhotosPickerItem?
    @State private var backgroundImage: UIImage?
    @State private var mapImage: UIImage?
    @State private var isLoadingPhoto = false
    @State private var isRendering = false
    @State private var shareItem: ShareItem?
    @State private var renderFailed = false
    @State private var photoLoadFailed = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    TabView(selection: $selectedStyle) {
                        ForEach(ShareCanvasStyle.allCases) { style in
                            ShareCanvas(
                                record: record,
                                style: style,
                                mapImage: mapImage,
                                backgroundImage: backgroundImage
                            )
                            .aspectRatio(4 / 5, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                            .padding(.horizontal, 26)
                            .tag(style)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: min(max(proxy.size.height * 0.48, 280), 510))

                    styleDescription
                        .padding(.top, 12)

                    photoControls
                        .padding(.top, 18)

                    Button(action: render) {
                        Label(isRendering ? "Preparing…" : "Share Image", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(.mint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(.black)
                    }
                    .disabled(isRendering || isLoadingPhoto)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .task {
            await prepareMap()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(from: item) }
        }
        .sheet(item: $shareItem) { item in
            ShareActivityView(activityItems: item.activityItems)
        }
        .alert("Couldn’t create share image", isPresented: $renderFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
        .alert("Couldn’t load photo", isPresented: $photoLoadFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Choose a different photo.")
        }
    }

    private var header: some View {
        HStack {
            Button("Close") {
                isPresented = false
            }
            .foregroundStyle(.white)

            Spacer()

            Text("Share your run")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            Color.clear
                .frame(width: 44, height: 1)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var styleDescription: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                ForEach(ShareCanvasStyle.allCases) { style in
                    Capsule()
                        .fill(style == selectedStyle ? Color.mint : Color.white.opacity(0.28))
                        .frame(width: style == selectedStyle ? 22 : 7, height: 7)
                        .animation(.easeInOut(duration: 0.18), value: selectedStyle)
                }
            }
            .accessibilityLabel("\(selectedStyle.title), \(selectedStyle.position) of \(ShareCanvasStyle.allCases.count)")

            Text(selectedStyle.title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(selectedStyle.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var photoControls: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(
                    backgroundImage == nil ? "Add Photo" : "Replace Photo",
                    systemImage: backgroundImage == nil ? "photo.badge.plus" : "photo"
                )
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(.white.opacity(0.12), in: Capsule())
            }
            .foregroundStyle(.white)
            .disabled(isLoadingPhoto)

            if backgroundImage != nil {
                Button("Remove Photo", role: .destructive) {
                    backgroundImage = nil
                    photoItem = nil
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background(.white.opacity(0.12), in: Capsule())
            }

            if isLoadingPhoto {
                ProgressView()
                    .tint(.mint)
                    .accessibilityLabel("Loading photo")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func prepareMap() async {
        guard record.hasRoute else { return }
        mapImage = await RouteSnapshotter.snapshot(
            segments: record.shareRouteSegments,
            size: CGSize(width: 956, height: 550)
        )
    }

    private func loadPhoto(from item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = ShareImageLoader.image(from: data) else {
                photoLoadFailed = true
                photoItem = nil
                return
            }
            backgroundImage = image
        } catch {
            photoLoadFailed = true
            photoItem = nil
        }
    }

    private func render() {
        guard !isRendering else { return }
        isRendering = true

        Task { @MainActor in
            let exportPixelSize = ShareImageLoader.exportPixelSize
            var renderedMap = mapImage
            if selectedStyle == .brandedMap, renderedMap == nil, record.hasRoute {
                renderedMap = await RouteSnapshotter.snapshot(
                    segments: record.shareRouteSegments,
                    size: CGSize(width: 956, height: 550)
                )
                mapImage = renderedMap
            }

            let content = ShareCanvas(
                record: record,
                style: selectedStyle,
                mapImage: renderedMap,
                backgroundImage: backgroundImage
            )
            .frame(width: exportPixelSize.width, height: exportPixelSize.height)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            renderer.isOpaque = selectedStyle == .brandedMap || backgroundImage != nil

            isRendering = false
            guard let image = renderer.uiImage,
                  image.cgImage?.width == Int(exportPixelSize.width),
                  image.cgImage?.height == Int(exportPixelSize.height) else {
                renderFailed = true
                return
            }

            shareItem = ShareItem(
                image: image,
                caption: caption,
                includeCaption: selectedStyle == .brandedMap
            )
        }
    }

    private var caption: String {
        let verb = record.activityKind.pastTenseVerb
        return "I \(verb) \(record.distanceText) in \(record.activeDuration.clockText) at \(record.paceText) with MilePace — a free, open-source running app. https://github.com/misery-hl/MilePace"
    }
}

private enum ShareCanvasStyle: CaseIterable, Identifiable {
    case brandedMap
    case metricStack
    case routeFocus
    case compact

    var id: Self { self }

    var title: String {
        switch self {
        case .brandedMap: "Branded map"
        case .metricStack: "Metric stack"
        case .routeFocus: "Route focus"
        case .compact: "Compact"
        }
    }

    var subtitle: String {
        switch self {
        case .brandedMap: "A finished card with the saved route map."
        case .metricStack: "A clear metric overlay for a photo or a post."
        case .routeFocus: "Your route with metrics, without a map tile."
        case .compact: "A small summary that leaves more of the photo visible."
        }
    }

    var position: Int {
        ShareCanvasStyle.allCases.firstIndex(of: self).map { $0 + 1 } ?? 1
    }
}

private struct ShareCanvas: View {
    let record: RunRecord
    let style: ShareCanvasStyle
    let mapImage: UIImage?
    let backgroundImage: UIImage?

    var body: some View {
        Group {
            if style == .brandedMap {
                BrandedMapCanvas(record: record, mapImage: mapImage, backgroundImage: backgroundImage)
            } else {
                ZStack {
                    if let backgroundImage {
                        SharePhotoBackground(image: backgroundImage)
                    }
                    ShareOverlayCanvas(record: record, style: style)
                }
            }
        }
        .compositingGroup()
        .clipped()
    }
}

private struct BrandedMapCanvas: View {
    let record: RunRecord
    let mapImage: UIImage?
    let backgroundImage: UIImage?

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 1_080, proxy.size.height / 1_350)

            ZStack {
                if let backgroundImage {
                    SharePhotoBackground(image: backgroundImage)
                    Color.black.opacity(0.48)
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.01, green: 0.08, blue: 0.06), Color(red: 0.03, green: 0.22, blue: 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                Circle()
                    .fill(.mint.opacity(0.12))
                    .frame(width: 760 * scale, height: 760 * scale)
                    .offset(x: 420 * scale, y: -500 * scale)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 20 * scale) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 48 * scale, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 88 * scale, height: 88 * scale)
                            .background(.mint, in: Circle())
                        VStack(alignment: .leading, spacing: 4 * scale) {
                            Text("MilePace")
                                .font(.system(size: 52 * scale, weight: .bold, design: .rounded))
                            Text("\(record.activityKind.displayName.uppercased()) COMPLETE")
                                .font(.system(size: 22 * scale, weight: .bold))
                                .tracking(4 * scale)
                                .foregroundStyle(.mint)
                        }
                    }

                    mapPanel(scale: scale)
                        .padding(.top, 38 * scale)

                    Spacer(minLength: 24 * scale)

                    Text(record.distanceMetric.value)
                        .font(.system(size: 152 * scale, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)
                    Text(record.distanceUnitHeadline)
                        .font(.system(size: 30 * scale, weight: .bold))
                        .tracking(7 * scale)
                        .foregroundStyle(.white.opacity(0.7))

                    HStack(spacing: 14 * scale) {
                        CanvasMetric(title: "TIME", value: record.activeDuration.clockText, scale: scale)
                        CanvasMetric(title: record.paceMetric.title, value: record.paceText, scale: scale)
                    }
                    .padding(.top, 34 * scale)

                    HStack {
                        Text(record.startedAt.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text("MilePace")
                            .foregroundStyle(.mint)
                    }
                    .font(.system(size: 22 * scale, weight: .semibold))
                    .padding(.top, 34 * scale)
                }
                .foregroundStyle(.white)
                .padding(72 * scale)
            }
        }
    }

    @ViewBuilder
    private func mapPanel(scale: CGFloat) -> some View {
        if let mapImage {
            Image(uiImage: mapImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 490 * scale)
                .clipShape(RoundedRectangle(cornerRadius: 30 * scale, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 2 * scale)
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                    .fill(.black.opacity(0.30))
                ShareRouteDrawing(segments: record.routeSegments)
                    .padding(50 * scale)
                if !record.hasRoute {
                    Text("No saved route")
                        .font(.system(size: 28 * scale, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 490 * scale)
        }
    }
}

private struct ShareOverlayCanvas: View {
    let record: RunRecord
    let style: ShareCanvasStyle

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 1_080, proxy.size.height / 1_350)

            switch style {
            case .metricStack:
                metricStack(scale: scale)
            case .routeFocus:
                routeFocus(scale: scale)
            case .compact:
                compact(scale: scale)
            case .brandedMap:
                EmptyView()
            }
        }
    }

    private func metricStack(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20 * scale) {
            ShareCanvasBrand(scale: scale)
            Spacer()
            Text(record.distanceMetric.value)
                .font(.system(size: 188 * scale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(record.distanceUnitHeadline)
                .font(.system(size: 34 * scale, weight: .bold))
                .tracking(8 * scale)
                .foregroundStyle(.white.opacity(0.8))

            VStack(spacing: 14 * scale) {
                OverlayMetricRow(title: "ACTIVE TIME", value: record.activeDuration.clockText, scale: scale)
                OverlayMetricRow(title: "AVERAGE \(record.paceMetric.title == "AVG SPEED" ? "SPEED" : "PACE")", value: record.paceText, scale: scale)
                if let fastest = record.fastestMile {
                    OverlayMetricRow(title: "FASTEST MILE", value: fastest.duration.paceText, scale: scale)
                }
            }
            .padding(.top, 26 * scale)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.72), radius: 12 * scale, y: 5 * scale)
        .padding(76 * scale)
    }

    private func routeFocus(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ShareCanvasBrand(scale: scale)
            Spacer()
            Group {
                if record.hasRoute {
                    ShareRouteDrawing(segments: record.routeSegments)
                } else {
                    VStack(spacing: 20 * scale) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 92 * scale, weight: .semibold))
                            .foregroundStyle(.mint)
                        Text("No saved route")
                            .font(.system(size: 32 * scale, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
                .frame(height: 520 * scale)
                .padding(.horizontal, 36 * scale)
            Spacer()
            Text(record.distanceText)
                .font(.system(size: 126 * scale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(record.activeDuration.clockText)  •  \(record.paceText)")
                .font(.system(size: 36 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 10 * scale)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.76), radius: 12 * scale, y: 5 * scale)
        .padding(76 * scale)
    }

    private func compact(scale: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 18 * scale) {
                ShareCanvasBrand(scale: scale)
                HStack(alignment: .lastTextBaseline, spacing: 18 * scale) {
                    Text(record.distanceMetric.value)
                        .font(.system(size: 112 * scale, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Text(record.distanceMetric.unit.uppercased())
                        .font(.system(size: 36 * scale, weight: .bold))
                        .foregroundStyle(.mint)
                }
                Text("\(record.activeDuration.clockText)  •  \(record.paceText)")
                    .font(.system(size: 34 * scale, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.78), radius: 12 * scale, y: 5 * scale)
            .padding(58 * scale)
            .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 38 * scale, style: .continuous))
        }
        .padding(58 * scale)
    }
}

private struct ShareCanvasBrand: View {
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 16 * scale) {
            Image(systemName: "figure.run")
                .font(.system(size: 34 * scale, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 62 * scale, height: 62 * scale)
                .background(.mint, in: Circle())
            Text("MilePace")
                .font(.system(size: 38 * scale, weight: .bold, design: .rounded))
        }
    }
}

private struct CanvasMetric: View {
    let title: String
    let value: String
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            Text(title)
                .font(.system(size: 18 * scale, weight: .bold))
                .foregroundStyle(.white.opacity(0.66))
            Text(value)
                .font(.system(size: 40 * scale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20 * scale)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 22 * scale, style: .continuous))
    }
}

private struct OverlayMetricRow: View {
    let title: String
    let value: String
    let scale: CGFloat

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 22 * scale, weight: .bold))
                .foregroundStyle(.white.opacity(0.76))
            Spacer()
            Text(value)
                .font(.system(size: 42 * scale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .padding(.horizontal, 26 * scale)
        .padding(.vertical, 20 * scale)
        .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 24 * scale, style: .continuous))
    }
}

/// Draws each recorded segment as an independent path. A pause remains a gap
/// in every transparent route layout.
private struct ShareRouteDrawing: View {
    let segments: [[TrackPoint]]

    var body: some View {
        Canvas { context, size in
            let points = segments.flatMap { $0 }
            guard points.count >= 2,
                  let minLatitude = points.map(\.latitude).min(),
                  let maxLatitude = points.map(\.latitude).max(),
                  let minLongitude = points.map(\.longitude).min(),
                  let maxLongitude = points.map(\.longitude).max() else { return }

            let latitudeSpan = max(maxLatitude - minLatitude, 0.000_01)
            let longitudeSpan = max(maxLongitude - minLongitude, 0.000_01)
            let inset = min(size.width, size.height) * 0.08
            let drawWidth = max(size.width - inset * 2, 1)
            let drawHeight = max(size.height - inset * 2, 1)
            let coordinateScale = min(drawWidth / longitudeSpan, drawHeight / latitudeSpan)
            let routeWidth = longitudeSpan * coordinateScale
            let routeHeight = latitudeSpan * coordinateScale
            let originX = (size.width - routeWidth) / 2
            let originY = (size.height - routeHeight) / 2

            func point(for trackPoint: TrackPoint) -> CGPoint {
                CGPoint(
                    x: originX + (trackPoint.longitude - minLongitude) * coordinateScale,
                    y: originY + (maxLatitude - trackPoint.latitude) * coordinateScale
                )
            }

            for segment in segments where segment.count >= 2 {
                var path = Path()
                path.move(to: point(for: segment[0]))
                for trackPoint in segment.dropFirst() {
                    path.addLine(to: point(for: trackPoint))
                }
                context.stroke(
                    path,
                    with: .color(.mint),
                    style: StrokeStyle(lineWidth: max(8, min(size.width, size.height) * 0.025), lineCap: .round, lineJoin: .round)
                )
            }

            if let first = points.first, let last = points.last {
                let markerSize = max(20, min(size.width, size.height) * 0.065)
                let firstPoint = point(for: first)
                let lastPoint = point(for: last)
                let markerFrameSize = CGSize(width: markerSize, height: markerSize)
                context.fill(
                    Path(ellipseIn: CGRect(
                        origin: CGPoint(x: firstPoint.x - markerSize / 2, y: firstPoint.y - markerSize / 2),
                        size: markerFrameSize
                    )),
                    with: .color(.mint)
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        origin: CGPoint(x: lastPoint.x - markerSize / 2, y: lastPoint.y - markerSize / 2),
                        size: markerFrameSize
                    )),
                    with: .color(.white)
                )
            }
        }
    }
}

private struct SharePhotoBackground: View {
    let image: UIImage

    var body: some View {
        Color.black
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipped()
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let caption: String
    let includeCaption: Bool

    var activityItems: [Any] {
        includeCaption ? [image, caption] : [image]
    }
}

private struct ShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension RunRecord {
    var shareRouteSegments: [[RoutePoint]] {
        routeSegments.map { segment in
            segment.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude) }
        }
    }
}
