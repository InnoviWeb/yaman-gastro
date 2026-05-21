//
//
//  RoomScanView.swift
//  InnoviScan
//

import SwiftUI
import RoomPlan
import simd

// MARK: - SwiftUI Wrapper

struct RoomScanView: UIViewControllerRepresentable {
    let schadensnummer: String
    @Binding var isPresented: Bool
    var onDone: (Bool) -> Void

    func makeUIViewController(context: Context) -> RoomScanViewController {
        RoomScanViewController(schadensnummer: schadensnummer) { success in
            onDone(success)
            isPresented = false
        }
    }

    func updateUIViewController(_ uiViewController: RoomScanViewController, context: Context) {}
}

// MARK: - UIViewController

class RoomScanViewController: UIViewController {
    private let schadensnummer: String
    private let onDone: (Bool) -> Void

    private var roomCaptureView: RoomCaptureView!
    private var stopButton: UIButton!
    private var loadingOverlay: UIView!
    private var isProcessing = false

    init(schadensnummer: String, onDone: @escaping (Bool) -> Void) {
        self.schadensnummer = schadensnummer
        self.onDone         = onDone
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // RoomPlan Capture View
        roomCaptureView = RoomCaptureView(frame: view.bounds)
        roomCaptureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        roomCaptureView.captureSession.delegate = self
        roomCaptureView.delegate = self
        view.addSubview(roomCaptureView)

        setupStopButton()
        setupLoadingOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        roomCaptureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        roomCaptureView.captureSession.stop()
    }

    // MARK: - UI Setup

    private func setupStopButton() {
        stopButton = UIButton(type: .system)
        stopButton.setTitle("Scan beenden", for: .normal)
        stopButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        stopButton.backgroundColor = .systemBlue
        stopButton.setTitleColor(.white, for: .normal)
        stopButton.layer.cornerRadius = 12
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.addTarget(self, action: #selector(stopScan), for: .touchUpInside)
        view.addSubview(stopButton)

        NSLayoutConstraint.activate([
            stopButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stopButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            stopButton.widthAnchor.constraint(equalToConstant: 200),
            stopButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func setupLoadingOverlay() {
        loadingOverlay = UIView(frame: view.bounds)
        loadingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        loadingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        loadingOverlay.isHidden = true

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = .white
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = "Scan wird gespeichert…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor)
        ])

        view.addSubview(loadingOverlay)
    }

    @objc private func stopScan() {
        stopButton.isEnabled = false
        roomCaptureView.captureSession.stop()
    }
}

// MARK: - RoomCaptureSessionDelegate

extension RoomScanViewController: RoomCaptureSessionDelegate {
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        guard !isProcessing else { return }
        isProcessing = true

        if let error = error {
            DispatchQueue.main.async {
                self.showError(error.localizedDescription)
            }
            return
        }

        DispatchQueue.main.async {
            self.loadingOverlay.isHidden = false
        }

        Task {
            do {
                let builder = RoomBuilder(options: [.beautifyObjects])
                let room = try await builder.capturedRoom(from: data)
                await MainActor.run {
                    self.loadingOverlay.isHidden = true
                    self.showNamingScreen(for: room)
                }
            } catch {
                await MainActor.run {
                    self.loadingOverlay.isHidden = true
                    self.showError(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - RoomCaptureViewDelegate

extension RoomScanViewController: RoomCaptureViewDelegate {
    // Wir verarbeiten selbst in captureSession(_:didEndWith:), daher false
    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
        return false
    }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {}
}

// MARK: - Speichern

private extension RoomScanViewController {

    func saveResults(room: CapturedRoom, roomNames: [String]) throws -> ScanRecord {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let relativePath = "Scans/\(schadensnummer)"
        let folder = docs.appendingPathComponent(relativePath, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // 1. Maße extrahieren
        let wallM = room.walls.map {
            WallMeasurement(
                width:      (Double($0.dimensions.x) * 100).rounded() / 100,
                height:     (Double($0.dimensions.y) * 100).rounded() / 100,
                confidence: $0.confidence.germanLabel
            )
        }
        let doorM = room.doors.map {
            SurfaceMeasurement(
                width:  (Double($0.dimensions.x) * 100).rounded() / 100,
                height: (Double($0.dimensions.y) * 100).rounded() / 100
            )
        }
        let windowM = room.windows.map {
            SurfaceMeasurement(
                width:  (Double($0.dimensions.x) * 100).rounded() / 100,
                height: (Double($0.dimensions.y) * 100).rounded() / 100
            )
        }
        let floorArea = room.floors.reduce(0.0) {
            $0 + Double($1.dimensions.x * $1.dimensions.z)
        }
        let roomFloorAreas: [Double] = room.floors.map {
            Double($0.dimensions.x * $0.dimensions.z)
        }

        // Geometrie für 2D-Grundriss (Draufsicht: Y ignoriert, XZ-Projektion)
        // columns.0 = lokale X-Achse (entlang der Wand), columns.3 = Weltposition
        func makeWallGeo(_ t: simd_float4x4, _ dimX: Float) -> WallGeometry2D {
            let dx: Double = Double(t.columns.0.x)
            let dz: Double = Double(t.columns.0.z)
            let len: Double = sqrt(dx*dx + dz*dz)
            return WallGeometry2D(
                cx: Double(t.columns.3.x), cz: Double(t.columns.3.z),
                dirX: len > 1e-6 ? dx/len : Double(1.0),
                dirZ: len > 1e-6 ? dz/len : Double(0.0),
                width: Double(dimX)
            )
        }
        func makeOpeningGeo(_ t: simd_float4x4, _ dimX: Float) -> OpeningGeometry2D {
            let dx: Double = Double(t.columns.0.x)
            let dz: Double = Double(t.columns.0.z)
            let len: Double = sqrt(dx*dx + dz*dz)
            return OpeningGeometry2D(
                cx: Double(t.columns.3.x), cz: Double(t.columns.3.z),
                dirX: len > 1e-6 ? dx/len : Double(1.0),
                dirZ: len > 1e-6 ? dz/len : Double(0.0),
                width: Double(dimX)
            )
        }
        let wallGeo   = room.walls.map   { makeWallGeo($0.transform, $0.dimensions.x) }
        let doorGeo   = room.doors.map   { makeOpeningGeo($0.transform, $0.dimensions.x) }
        let windowGeo = room.windows.map { makeOpeningGeo($0.transform, $0.dimensions.x) }

        // 2. USDZ speichern
        let usdzURL = folder.appendingPathComponent("scan.usdz")
        try room.export(to: usdzURL)

        // 3. PDF: Seite 1 = Grundriss, Seite 2 = Maßtabelle
        let pdfURL = folder.appendingPathComponent("bericht.pdf")
        try FloorPlanRenderer.generateReport(
            wallMeasurements: wallM,
            doorMeasurements: doorM,
            windowMeasurements: windowM,
            wallGeometry: wallGeo,
            doorGeometry: doorGeo,
            windowGeometry: windowGeo,
            floorAreaM2: floorArea,
            address: nil,
            roomNames: roomNames,
            roomFloorAreas: roomFloorAreas,
            schadensnummer: schadensnummer,
            date: Date(),
            roomPhotos: nil,
            folderURL: folder,
            moistureMeasurements: nil,
            at: pdfURL
        )

        return ScanRecord(
            id: UUID(),
            schadensnummer: schadensnummer,
            date: Date(),
            relativeFolderPath: relativePath,
            wallCount: room.walls.count,
            doorCount: room.doors.count,
            windowCount: room.windows.count,
            objectCount: room.objects.count,
            floorAreaM2: floorArea,
            wallMeasurements: wallM,
            doorMeasurements: doorM,
            windowMeasurements: windowM,
            wallGeometry: wallGeo,
            doorGeometry: doorGeo,
            windowGeometry: windowGeo,
            address: nil,
            roomNames: roomNames,
            roomFloorAreas: roomFloorAreas,
            roomPhotos: nil,
            moistureMeasurements: nil
        )
    }

    func showNamingScreen(for room: CapturedRoom) {
        let count = max(1, room.floors.count)
        let namingVC = UIHostingController(rootView: RoomNamingView(roomCount: count) { [weak self] names in
            guard let self = self else { return }
            self.dismiss(animated: true) {
                self.loadingOverlay.isHidden = false
                Task {
                    do {
                        let record = try self.saveResults(room: room, roomNames: names)
                        await MainActor.run {
                            ScanStore.shared.add(record)
                            self.onDone(true)
                        }
                    } catch {
                        await MainActor.run {
                            self.loadingOverlay.isHidden = true
                            self.showError(error.localizedDescription)
                        }
                    }
                }
            }
        })
        namingVC.isModalInPresentation = true
        present(namingVC, animated: true)
    }

    func showError(_ message: String) {
        let alert = UIAlertController(title: "Fehler", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            self.onDone(false)
        })
        present(alert, animated: true)
    }
}

// MARK: - RoomPlan Confidence → Deutsch

private extension CapturedRoom.Confidence {
    var germanLabel: String {
        switch self {
        case .low:    return "niedrig"
        case .medium: return "mittel"
        case .high:   return "hoch"
        @unknown default: return "–"
        }
    }
}

// MARK: - Post-Scan Raum-Benennung

struct RoomNamingView: View {
    let roomCount: Int
    @State private var names: [String]
    let onConfirm: ([String]) -> Void

    init(roomCount: Int, onConfirm: @escaping ([String]) -> Void) {
        self.roomCount = roomCount
        self._names = State(initialValue: (1...max(1, roomCount)).map { "Raum \($0)" })
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(0..<names.count, id: \.self) { i in
                        TextField("Raum \(i + 1)", text: $names[i])
                    }
                } header: {
                    Text("Erkannte Räume – Namen optional")
                } footer: {
                    Text("Felder leer lassen = Standardname wird verwendet (Raum 1, Raum 2 …)")
                        .font(.caption2)
                }
            }
            .navigationTitle("Räume benennen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Weiter") {
                        let resolved = names.enumerated().map { i, n in
                            n.trimmingCharacters(in: .whitespaces).isEmpty ? "Raum \(i + 1)" : n
                        }
                        onConfirm(resolved)
                    }
                }
            }
        }
    }
}

// MARK: - FloorPlanRenderer
//
// Zeichnet einen maßstabsgetreuen 2D-Grundriss aus WallGeometry2D / OpeningGeometry2D.
//
// Koordinatenumrechnung 3D → 2D:
//   RoomPlan: rechtshändiges Y-oben-System (Meter).
//   Draufsicht: Y ignoriert. X → Canvas-X, Z → Canvas-Y.
//   Skalierung: scale = min(canvasW/worldW, canvasH/worldH) → maßstabstreu.
//   Wandendpunkte: center ± (width/2) × normalize(columns.0.xz)

struct FloorPlanRenderer {

    // MARK: Vollständiger PDF-Bericht (Seite 1 = Grundriss, Seite 2 = Maßtabelle)

    static func generateReport(
        wallMeasurements: [WallMeasurement],
        doorMeasurements: [SurfaceMeasurement],
        windowMeasurements: [SurfaceMeasurement],
        wallGeometry: [WallGeometry2D],
        doorGeometry: [OpeningGeometry2D],
        windowGeometry: [OpeningGeometry2D],
        floorAreaM2: Double,
        address: ScanAddress?,
        roomNames: [String]?,
        roomFloorAreas: [Double]?,
        schadensnummer: String,
        date: Date,
        roomPhotos: [String: [String]]?,
        folderURL: URL,
        moistureMeasurements: [MoistureMeasurement]?,
        at url: URL
    ) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let pdfData = UIGraphicsPDFRenderer(bounds: pageRect).pdfData { ctx in

            // Seite 1: Grundriss
            drawPDFPage(context: ctx, walls: wallGeometry, doors: doorGeometry, windows: windowGeometry,
                        schadensnummer: schadensnummer, date: date, floorAreaM2: floorAreaM2,
                        address: address, roomNames: roomNames, roomFloorAreas: roomFloorAreas)

            // Seite 2: Maßtabelle
            ctx.beginPage()
            let g = ctx.cgContext

            let headerH = drawKRAFTHeader(g: g, pageW: 595, schadensnummer: schadensnummer,
                                          date: date, address: address, roomNames: roomNames,
                                          floorAreaM2: floorAreaM2)

            let sectionAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.systemBlue]
            let boldAttrs:    [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: UIColor.black]
            let bodyAttrs:    [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12),     .foregroundColor: UIColor.darkGray]

            let formatter = DateFormatter()
            formatter.dateStyle = .long; formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "de_DE")

            var y: CGFloat = headerH + 14

            func text(_ s: String, x: CGFloat = 40, attrs: [NSAttributedString.Key: Any] = bodyAttrs) {
                s.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            }
            func nl(_ dy: CGFloat = 20) { y += dy }

            text("Schadensnummer:", attrs: boldAttrs); text(schadensnummer, x: 200); nl()
            text("Datum / Uhrzeit:", attrs: boldAttrs); text(formatter.string(from: date), x: 200); nl(28)

            text("RAUMMASZE", attrs: sectionAttrs); nl(20)
            let areaText = floorAreaM2 > 0 ? String(format: "%.2f m²", floorAreaM2) : "–"
            text("Bodenfläche:", attrs: boldAttrs); text(areaText, x: 200); nl()
            if let h = wallMeasurements.map(\.height).max() {
                text("Raumhöhe:", attrs: boldAttrs); text(String(format: "%.2f m", h), x: 200); nl()
            }
            nl(10)

            func tableHeader(_ cols: [(String, CGFloat)]) {
                g.setStrokeColor(UIColor.lightGray.cgColor); g.setLineWidth(0.5)
                g.move(to: CGPoint(x: 40, y: y + 18)); g.addLine(to: CGPoint(x: 555, y: y + 18)); g.strokePath()
                for (title, x) in cols { title.draw(at: CGPoint(x: x, y: y), withAttributes: boldAttrs) }
                nl(22)
            }
            func tableRow(_ cols: [(String, CGFloat)]) {
                for (val, x) in cols { val.draw(at: CGPoint(x: x, y: y), withAttributes: bodyAttrs) }
                nl(19)
            }

            text("WÄNDE  (\(wallMeasurements.count))", attrs: sectionAttrs); nl(20)
            if wallMeasurements.isEmpty { text("Keine Wände erkannt.", attrs: bodyAttrs); nl() } else {
                tableHeader([("Nr.", 40), ("Länge", 90), ("Höhe", 200)])
                for (i, w) in wallMeasurements.enumerated() {
                    tableRow([("\(i+1)", 40), (String(format:"%.2f m", w.width), 90),
                              (String(format:"%.2f m", w.height), 200)])
                }
            }
            nl(10)

            text("TÜREN  (\(doorMeasurements.count))", attrs: sectionAttrs); nl(20)
            if doorMeasurements.isEmpty { text("Keine Türen erkannt.", attrs: bodyAttrs); nl() } else {
                tableHeader([("Nr.", 40), ("Breite", 90), ("Höhe", 200)])
                for (i, d) in doorMeasurements.enumerated() {
                    tableRow([("\(i+1)", 40), (String(format:"%.2f m", d.width), 90), (String(format:"%.2f m", d.height), 200)])
                }
            }
            nl(10)

            text("FENSTER  (\(windowMeasurements.count))", attrs: sectionAttrs); nl(20)
            if windowMeasurements.isEmpty { text("Keine Fenster erkannt.", attrs: bodyAttrs); nl() } else {
                tableHeader([("Nr.", 40), ("Breite", 90), ("Höhe", 200)])
                for (i, w) in windowMeasurements.enumerated() {
                    tableRow([("\(i+1)", 40), (String(format:"%.2f m", w.width), 90), (String(format:"%.2f m", w.height), 200)])
                }
            }
            nl(16)

            g.setStrokeColor(UIColor.lightGray.cgColor)
            g.move(to: CGPoint(x: 40, y: y)); g.addLine(to: CGPoint(x: 555, y: y)); g.strokePath()
            nl(8)
            text("3D-Modell: Scan_\(schadensnummer).usdz  |  Erstellt mit InnoviScan", attrs: bodyAttrs)

            // Seite 3: Fotos pro Raum (nur wenn vorhanden)
            if let photos = roomPhotos, !photos.isEmpty {
                let roomOrder = roomNames ?? Array(photos.keys.sorted())
                for roomName in roomOrder {
                    guard let fileNames = photos[roomName], !fileNames.isEmpty else { continue }
                    let images = fileNames.compactMap { name -> UIImage? in
                        let imgURL = folderURL.appendingPathComponent(name)
                        guard let data = try? Data(contentsOf: imgURL) else { return nil }
                        return UIImage(data: data)
                    }
                    guard !images.isEmpty else { continue }

                    ctx.beginPage()
                    let gp = ctx.cgContext
                    let _ = drawKRAFTHeader(g: gp, pageW: 595, schadensnummer: schadensnummer,
                                            date: date, address: address, roomNames: roomNames,
                                            floorAreaM2: floorAreaM2)

                    var photoY: CGFloat = 130
                    let titleAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 14),
                        .foregroundColor: UIColor.systemBlue
                    ]
                    (roomName as NSString).draw(at: CGPoint(x: 40, y: photoY), withAttributes: titleAttrs)
                    photoY += 22

                    let photoW: CGFloat = 160, photoH: CGFloat = 120, gap: CGFloat = 10
                    let cols = 3
                    for (i, img) in images.enumerated() {
                        let col = CGFloat(i % cols)
                        let row = CGFloat(i / cols)
                        let px = 40 + col * (photoW + gap)
                        let py = photoY + row * (photoH + gap)
                        if py + photoH > 800 { break }
                        img.draw(in: CGRect(x: px, y: py, width: photoW, height: photoH))
                    }
                }
            }

            // Seite 4: Feuchtigkeitsmessung (nur wenn vorhanden)
            if let moisture = moistureMeasurements, !moisture.isEmpty {
                ctx.beginPage()
                let gm = ctx.cgContext
                let headerHm = drawKRAFTHeader(g: gm, pageW: 595, schadensnummer: schadensnummer,
                                               date: date, address: address, roomNames: roomNames,
                                               floorAreaM2: floorAreaM2)
                var my: CGFloat = headerHm + 14

                let mSectionAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.systemBlue]
                let mBoldAttrs:    [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.black]

                ("FEUCHTIGKEITSMESSUNG" as NSString).draw(at: CGPoint(x: 40, y: my), withAttributes: mSectionAttrs)
                my += 24

                func mtext(_ s: String, x: CGFloat, color: UIColor = .black) {
                    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: color]
                    (s as NSString).draw(at: CGPoint(x: x, y: my), withAttributes: attrs)
                }

                let wand = moisture.filter { $0.kategorie == .wandflaeche }
                if !wand.isEmpty {
                    ("Wandfläche" as NSString).draw(at: CGPoint(x: 40, y: my), withAttributes: mBoldAttrs)
                    my += 18
                    ("Nr." as NSString).draw(at: CGPoint(x: 40,  y: my), withAttributes: mBoldAttrs)
                    ("Wert" as NSString).draw(at: CGPoint(x: 100, y: my), withAttributes: mBoldAttrs)
                    ("Einheit" as NSString).draw(at: CGPoint(x: 200, y: my), withAttributes: mBoldAttrs)
                    my += 18
                    for m in wand {
                        mtext("\(m.nummer).", x: 40,  color: .systemBlue)
                        mtext(String(format: "%.1f", m.wert), x: 100, color: .systemBlue)
                        mtext(m.einheit, x: 200, color: .systemBlue)
                        my += 16
                    }
                    my += 10
                }

                let daemm = moisture.filter { $0.kategorie == .daemmschicht }
                if !daemm.isEmpty {
                    ("Dämmschicht" as NSString).draw(at: CGPoint(x: 40, y: my), withAttributes: mBoldAttrs)
                    my += 18
                    ("Nr." as NSString).draw(at: CGPoint(x: 40,  y: my), withAttributes: mBoldAttrs)
                    ("Wert" as NSString).draw(at: CGPoint(x: 100, y: my), withAttributes: mBoldAttrs)
                    ("Einheit" as NSString).draw(at: CGPoint(x: 200, y: my), withAttributes: mBoldAttrs)
                    my += 18
                    for m in daemm {
                        mtext("\(m.nummer).", x: 40,  color: .systemRed)
                        mtext(String(format: "%.1f", m.wert), x: 100, color: .systemRed)
                        mtext(m.einheit, x: 200, color: .systemRed)
                        my += 16
                    }
                }
            }
        }
        try pdfData.write(to: url)
    }

    static func drawPDFPage(
        context: UIGraphicsPDFRendererContext,
        walls: [WallGeometry2D],
        doors: [OpeningGeometry2D],
        windows: [OpeningGeometry2D],
        schadensnummer: String,
        date: Date,
        floorAreaM2: Double,
        address: ScanAddress?,
        roomNames: [String]?,
        roomFloorAreas: [Double]? = nil
    ) {
        context.beginPage()
        let g = context.cgContext
        let pageW: CGFloat = 595
        let pageH: CGFloat = 842
        let footerH: CGFloat = 36
        let margin:  CGFloat = 36

        let headerH = drawKRAFTHeader(
            g: g, pageW: pageW,
            schadensnummer: schadensnummer, date: date,
            address: address, roomNames: roomNames,
            floorAreaM2: floorAreaM2
        )

        let drawRect = CGRect(
            x: margin,
            y: headerH + 4,
            width: pageW - 2 * margin,
            height: pageH - headerH - 4 - footerH - margin
        )
        drawFloorPlan(g: g, in: drawRect,
                      walls: walls, doors: doors, windows: windows,
                      floorAreaM2: floorAreaM2, roomNames: roomNames,
                      roomFloorAreas: roomFloorAreas)

        drawFooter(g: g, pageW: pageW, y: pageH - footerH + 4)
    }

    // MARK: Vorschau-Bild (wird von ScanDetailView aufgerufen)

    static func renderPreviewImage(
        walls: [WallGeometry2D],
        doors: [OpeningGeometry2D],
        windows: [OpeningGeometry2D],
        floorAreaM2: Double,
        roomNames: [String]? = nil,
        roomFloorAreas: [Double]? = nil,
        size: CGSize = CGSize(width: 480, height: 480)
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let pad: CGFloat = 20
            drawFloorPlan(
                g: ctx.cgContext,
                in: CGRect(x: pad, y: pad,
                           width: size.width - 2*pad,
                           height: size.height - 2*pad),
                walls: walls, doors: doors, windows: windows,
                floorAreaM2: floorAreaM2, roomNames: roomNames,
                roomFloorAreas: roomFloorAreas
            )
        }
    }

    // MARK: - Kernzeichnung

    private static func drawFloorPlan(
        g: CGContext,
        in rect: CGRect,
        walls: [WallGeometry2D],
        doors: [OpeningGeometry2D],
        windows: [OpeningGeometry2D],
        floorAreaM2: Double,
        roomNames: [String]? = nil,
        roomFloorAreas: [Double]? = nil
    ) {
        guard !walls.isEmpty else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.lightGray
            ]
            ("Keine Grundriss-Geometrie verfügbar" as NSString)
                .draw(at: CGPoint(x: rect.midX - 110, y: rect.midY - 8), withAttributes: attrs)
            return
        }

        // Bounding Box aller Wandendpunkte (Weltkoordinaten)
        var allX: [Double] = [], allZ: [Double] = []
        for w in walls {
            let hw = w.width / 2
            allX += [w.cx + hw * w.dirX, w.cx - hw * w.dirX]
            allZ += [w.cz + hw * w.dirZ, w.cz - hw * w.dirZ]
        }
        for o in doors + windows {
            let hw = o.width / 2
            allX += [o.cx + hw * o.dirX, o.cx - hw * o.dirX]
            allZ += [o.cz + hw * o.dirZ, o.cz - hw * o.dirZ]
        }
        guard let minX = allX.min(), let maxX = allX.max(),
              let minZ = allZ.min(), let maxZ = allZ.max() else { return }

        let worldW = max(maxX - minX, 0.1)
        let worldH = max(maxZ - minZ, 0.1)

        // Maßstabsgetreue Skalierung mit Rand für Maßbeschriftungen
        let labelPad: CGFloat = 48
        let scale = min((rect.width  - 2*labelPad) / CGFloat(worldW),
                        (rect.height - 2*labelPad) / CGFloat(worldH))

        let scaledW = CGFloat(worldW) * scale
        let scaledH = CGFloat(worldH) * scale
        let ox = rect.minX + labelPad + (rect.width  - 2*labelPad - scaledW) / 2
        let oy = rect.minY + labelPad + (rect.height - 2*labelPad - scaledH) / 2

        // Welt (XZ) → Canvas
        // X wird gespiegelt (wie im RoomPlan-2D-Standard: posX = -worldX),
        // damit die Raumgeometrie die korrekte Händigkeit bekommt.
        func cv(_ wx: Double, _ wz: Double) -> CGPoint {
            CGPoint(x: ox + CGFloat(maxX - wx) * scale,
                    y: oy + CGFloat(wz - minZ) * scale)
        }

        drawGrid(g: g, rect: CGRect(x: ox, y: oy, width: scaledW, height: scaledH))

        // 1. Wände (schwarze, dicke Linien) – zuerst, damit Öffnungen darüber sichtbar sind
        g.saveGState()
        g.setStrokeColor(UIColor.black.cgColor)
        g.setLineWidth(3.5)
        g.setLineCap(.square)
        for wall in walls {
            let hw = wall.width / 2
            let p1 = cv(wall.cx + hw * wall.dirX, wall.cz + hw * wall.dirZ)
            let p2 = cv(wall.cx - hw * wall.dirX, wall.cz - hw * wall.dirZ)
            g.move(to: p1); g.addLine(to: p2)
        }
        g.strokePath()
        g.restoreGState()

        // 2. Türen (grüne Linie + Viertelbogen als Schwungsymbol)
        g.saveGState()
        g.setStrokeColor(UIColor.systemGreen.cgColor)
        g.setLineWidth(2)
        for door in doors {
            let hw = door.width / 2
            let p1 = cv(door.cx + hw * door.dirX, door.cz + hw * door.dirZ)
            let p2 = cv(door.cx - hw * door.dirX, door.cz - hw * door.dirZ)
            g.move(to: p1); g.addLine(to: p2)
            // Viertelbogen: Scharnier bei p1, Schwung von p2 aus
            let r = sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2))
            let startAngle = atan2(p2.y - p1.y, p2.x - p1.x)
            g.move(to: p2)
            g.addArc(center: p1, radius: r,
                     startAngle: startAngle,
                     endAngle: startAngle - .pi / 2,
                     clockwise: true)
        }
        g.strokePath()
        g.restoreGState()

        // 3. Fenster (blaue gestrichelte Linie) – zuletzt, damit über Wänden sichtbar
        g.saveGState()
        g.setStrokeColor(UIColor.systemBlue.cgColor)
        g.setLineWidth(3)
        g.setLineDash(phase: 0, lengths: [7, 4])
        for win in windows {
            let hw = win.width / 2
            let p1 = cv(win.cx + hw * win.dirX, win.cz + hw * win.dirZ)
            let p2 = cv(win.cx - hw * win.dirX, win.cz - hw * win.dirZ)
            g.move(to: p1); g.addLine(to: p2)
        }
        g.strokePath()
        g.restoreGState()

        // Maßangaben entlang der Wände (senkrecht versetzt)
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5),
            .foregroundColor: UIColor(white: 0.3, alpha: 1)
        ]
        for wall in walls {
            let hw = wall.width / 2
            let p1 = cv(wall.cx + hw * wall.dirX, wall.cz + hw * wall.dirZ)
            let p2 = cv(wall.cx - hw * wall.dirX, wall.cz - hw * wall.dirZ)
            let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            let ang = atan2(Double(p2.y - p1.y), Double(p2.x - p1.x))
            let px = CGFloat(-sin(ang)) * 15
            let py = CGFloat( cos(ang)) * 15
            let label = String(format: "%.2f m", wall.width)
                .replacingOccurrences(of: ".", with: ",")
            let sz = (label as NSString).size(withAttributes: dimAttrs)
            (label as NSString).draw(
                at: CGPoint(x: mid.x + px - sz.width/2, y: mid.y + py - sz.height/2),
                withAttributes: dimAttrs
            )
        }

        // Raumname(n) + Fläche in der Raummitte
        if floorAreaM2 > 0.01 {
            let ps = NSMutableParagraphStyle()
            ps.alignment = .center
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.darkGray,
                .paragraphStyle: ps
            ]
            let names = roomNames?.filter { !$0.isEmpty } ?? []
            let areas = roomFloorAreas ?? []
            var lines: [String] = []
            for (i, name) in names.enumerated() {
                if i < areas.count {
                    let areaStr = String(format: "%.1f m²", areas[i])
                        .replacingOccurrences(of: ".", with: ",")
                    lines.append("\(name)  \(areaStr)")
                } else {
                    lines.append(name)
                }
            }
            if lines.isEmpty {
                let areaStr = String(format: "%.1f m²", floorAreaM2)
                    .replacingOccurrences(of: ".", with: ",")
                lines.append(areaStr)
            }
            let roomLabel = lines.joined(separator: "\n")
            let w: CGFloat = 110, h: CGFloat = CGFloat(lines.count) * 16 + 4
            (roomLabel as NSString).draw(
                in: CGRect(x: ox + scaledW/2 - w/2, y: oy + scaledH/2 - h/2,
                           width: w, height: h),
                withAttributes: labelAttrs
            )
        }

        // Maßstabsleiste (1 m)
        let barLen = scale
        let bx = rect.minX + (rect.width - barLen) / 2
        let by = oy + scaledH + 22
        if by < rect.maxY - 4 {
            g.saveGState()
            g.setStrokeColor(UIColor.darkGray.cgColor)
            g.setLineWidth(1.5)
            g.move(to: CGPoint(x: bx, y: by))
            g.addLine(to: CGPoint(x: bx + barLen, y: by))
            for tx in [bx, bx + barLen] {
                g.move(to: CGPoint(x: tx, y: by - 4)); g.addLine(to: CGPoint(x: tx, y: by + 4))
            }
            g.strokePath()
            let sAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor.darkGray
            ]
            ("1 m" as NSString).draw(
                at: CGPoint(x: bx + barLen/2 - 8, y: by + 6), withAttributes: sAttrs)
            g.restoreGState()
        }
    }

    // MARK: - Hilfsfunktionen

    private static func drawGrid(g: CGContext, rect: CGRect) {
        g.saveGState()
        g.setStrokeColor(UIColor(white: 0.92, alpha: 1).cgColor)
        g.setLineWidth(0.5)
        let step: CGFloat = 30
        var x = rect.minX
        while x <= rect.maxX + 0.1 { g.move(to: CGPoint(x: x, y: rect.minY)); g.addLine(to: CGPoint(x: x, y: rect.maxY)); x += step }
        var y = rect.minY
        while y <= rect.maxY + 0.1 { g.move(to: CGPoint(x: rect.minX, y: y)); g.addLine(to: CGPoint(x: rect.maxX, y: y)); y += step }
        g.strokePath()
        g.restoreGState()
    }

    /// Zeichnet den KRAFT-Briefkopf auf jeder PDF-Seite.
    /// Gibt die Höhe des Headers zurück, damit der Aufrufer den Inhalt korrekt positioniert.
    @discardableResult
    static func drawKRAFTHeader(
        g: CGContext,
        pageW: CGFloat,
        schadensnummer: String,
        date: Date,
        address: ScanAddress?,
        roomNames: [String]?,
        floorAreaM2: Double
    ) -> CGFloat {
        let margin: CGFloat = 36
        let df = DateFormatter()
        df.dateStyle = .medium; df.timeStyle = .none
        df.locale = Locale(identifier: "de_DE")

        let bold11: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.black]
        let reg9:   [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9),      .foregroundColor: UIColor.darkGray]
        let label9: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 8.5),.foregroundColor: UIColor(white: 0.45, alpha: 1)]
        let val9:   [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9),      .foregroundColor: UIColor.black]

        var y: CGFloat = 14

        // Zeile 1: Logo + Firmenname + Kurzinfo
        if let logo = UIImage(named: "kraft_logo") {
            logo.draw(in: CGRect(x: margin, y: y, width: 52, height: 38))
        }
        let logoRight: CGFloat = margin + 58
        ("KRAFT System GmbH" as NSString).draw(at: CGPoint(x: logoRight, y: y + 2), withAttributes: bold11)
        let companyInfo = "Musterstr. 1  ·  12345 Stadt  ·  Tel: 0800 / 000 000  ·  www.kraft-system.de"
        (companyInfo as NSString).draw(at: CGPoint(x: logoRight, y: y + 16), withAttributes: reg9)
        ("Aufmaßbericht / Schadensdokumentation" as NSString).draw(at: CGPoint(x: logoRight, y: y + 28), withAttributes: reg9)

        y += 50

        // Dünne Trennlinie
        g.setStrokeColor(UIColor(white: 0.78, alpha: 1).cgColor)
        g.setLineWidth(0.5)
        g.move(to: CGPoint(x: margin, y: y)); g.addLine(to: CGPoint(x: pageW - margin, y: y))
        g.strokePath()
        y += 8

        // Zeile 2: Metadaten in 4 Spalten
        let col: [(CGFloat, String, String)] = [
            (margin,       "SCHADENSNR.",  schadensnummer),
            (margin + 120, "DATUM",        df.string(from: date)),
            (margin + 240, "GESAMTFLÄCHE", floorAreaM2 > 0 ? String(format: "%.2f m²", floorAreaM2).replacingOccurrences(of: ".", with: ",") : "–"),
            (margin + 360, "WÄNDE / TÜR / FENSTER", "–")   // wird vom Aufrufer nicht genutzt; leer lassen
        ]
        for (x, lbl, val) in col.dropLast() {
            (lbl as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: label9)
            (val as NSString).draw(at: CGPoint(x: x, y: y + 11), withAttributes: val9)
        }
        y += 26

        // Zeile 3: Objekt + Räume (nur wenn Daten vorhanden)
        var addrParts: [String] = []
        if let addr = address {
            if !addr.street.isEmpty   { addrParts.append(addr.street) }
            if !addr.cityLine.isEmpty { addrParts.append(addr.cityLine) }
            if !addr.etage.isEmpty    { addrParts.append(addr.etage) }
        }
        let roomStr = roomNames?.filter { !$0.isEmpty }.joined(separator: " · ")

        if !addrParts.isEmpty || roomStr != nil {
            ("OBJEKT" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: label9)
            if !addrParts.isEmpty {
                (addrParts.joined(separator: "  ·  ") as NSString)
                    .draw(at: CGPoint(x: margin + 52, y: y), withAttributes: val9)
            }
            if let rs = roomStr {
                ("RÄUME" as NSString).draw(at: CGPoint(x: margin + 280, y: y), withAttributes: label9)
                (rs as NSString).draw(at: CGPoint(x: margin + 320, y: y), withAttributes: val9)
            }
            y += 18
        }

        // Abschlusslinie (dicker)
        g.setStrokeColor(UIColor(white: 0.55, alpha: 1).cgColor)
        g.setLineWidth(0.75)
        g.move(to: CGPoint(x: 0, y: y + 4)); g.addLine(to: CGPoint(x: pageW, y: y + 4))
        g.strokePath()

        return y + 12
    }

    private static func drawFooter(g: CGContext, pageW: CGFloat, y: CGFloat) {
        g.setStrokeColor(UIColor.lightGray.cgColor)
        g.setLineWidth(0.5)
        g.move(to: CGPoint(x: 36, y: y - 6)); g.addLine(to: CGPoint(x: pageW - 36, y: y - 6))
        g.strokePath()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5),
            .foregroundColor: UIColor.lightGray
        ]
        ("Seite 1 – Grundriss (Draufsicht)  |  Erstellt mit InnoviScan" as NSString)
            .draw(at: CGPoint(x: 36, y: y), withAttributes: attrs)
        ("Handnotizen / Messpunkte eintragbar" as NSString)
            .draw(at: CGPoint(x: pageW - 218, y: y), withAttributes: attrs)
    }
}
