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
    private var loadingLabel: UILabel!
    private var isProcessing = false

    private var capturedRooms: [CapturedRoom] = []
    private var collectedNames: [String] = []

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
        stopButton.setTitle("Raum fertig", for: .normal)
        stopButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        stopButton.backgroundColor = .systemBlue
        stopButton.setTitleColor(.white, for: .normal)
        stopButton.layer.cornerRadius = 12
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.addTarget(self, action: #selector(roomDone), for: .touchUpInside)
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

        loadingLabel = UILabel()
        loadingLabel.text = "Wird verarbeitet…"
        loadingLabel.textColor = .white
        loadingLabel.font = .systemFont(ofSize: 16)
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [spinner, loadingLabel])
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

    @objc private func roomDone() {
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
            DispatchQueue.main.async { self.showError(error.localizedDescription) }
            return
        }

        DispatchQueue.main.async {
            self.loadingLabel.text = "Raum wird verarbeitet…"
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

// MARK: - Scan-Loop

private extension RoomScanViewController {

    func startNewScan() {
        isProcessing = false
        stopButton.isEnabled = true
        roomCaptureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }

    func showNamingScreen(for room: CapturedRoom) {
        // roomCount: 1 — jeder Scan-Durchgang entspricht genau einem Raum
        let namingVC = UIHostingController(rootView: RoomNamingView(roomCount: 1) { [weak self] names in
            guard let self = self else { return }
            let name = names.first ?? "Raum \(self.capturedRooms.count + 1)"
            self.capturedRooms.append(room)
            self.collectedNames.append(name)
            let area = room.floors.reduce(0.0) { $0 + Double($1.dimensions.x * $1.dimensions.z) }
            self.dismiss(animated: true) {
                self.showRoomSummaryAlert(roomName: name, area: area)
            }
        })
        namingVC.isModalInPresentation = true
        present(namingVC, animated: true)
    }

    func showRoomSummaryAlert(roomName: String, area: Double) {
        let areaStr = String(format: "%.1f", area)
        let count = capturedRooms.count
        let plural = count == 1 ? "Raum" : "Räume"
        let alert = UIAlertController(
            title: "Raum gespeichert",
            message: "\(roomName)  ·  \(areaStr) m²\n\n\(count) \(plural) erfasst",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Nächster Raum", style: .default) { _ in
            self.startNewScan()
        })
        alert.addAction(UIAlertAction(title: "Wohnung abschließen", style: .default) { _ in
            self.runStructureBuilder()
        })
        present(alert, animated: true)
    }

    func runStructureBuilder() {
        guard !capturedRooms.isEmpty else { showError("Keine Räume gescannt."); return }
        loadingLabel.text = "Räume werden verbunden…"
        loadingOverlay.isHidden = false

        Task {
            do {
                let builder = StructureBuilder(options: [.beautifyObjects])
                let structure = try await builder.capturedStructure(from: capturedRooms)
                let record = try saveResults(structure: structure, roomNames: collectedNames)
                await MainActor.run {
                    ScanStore.shared.add(record)
                    onDone(true)
                }
            } catch {
                // StructureBuilder fehlgeschlagen — Einzelräume als Fallback speichern
                do {
                    let record = try saveFallback(rooms: capturedRooms, roomNames: collectedNames)
                    await MainActor.run {
                        ScanStore.shared.add(record)
                        onDone(true)
                    }
                } catch let fallbackError {
                    await MainActor.run {
                        self.loadingOverlay.isHidden = true
                        self.showError(fallbackError.localizedDescription)
                    }
                }
            }
        }
    }

    // MARK: - StructureBuilder: saveResults

    func saveResults(structure: CapturedStructure, roomNames: [String]) throws -> ScanRecord {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let relativePath = "Scans/\(schadensnummer)"
        let folder = docs.appendingPathComponent(relativePath, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // 1. Maße aus der zusammengeführten Struktur (alle Räume, Weltkoordinaten)
        let wallM = structure.walls.map {
            WallMeasurement(
                width:      (Double($0.dimensions.x) * 100).rounded() / 100,
                height:     (Double($0.dimensions.y) * 100).rounded() / 100,
                confidence: $0.confidence.germanLabel
            )
        }
        let doorM = structure.doors.map {
            SurfaceMeasurement(
                width:  (Double($0.dimensions.x) * 100).rounded() / 100,
                height: (Double($0.dimensions.y) * 100).rounded() / 100
            )
        }
        let windowM = structure.windows.map {
            SurfaceMeasurement(
                width:  (Double($0.dimensions.x) * 100).rounded() / 100,
                height: (Double($0.dimensions.y) * 100).rounded() / 100
            )
        }

        // 2. Bodenfläche pro Raum (parallel zu structure.rooms)
        let roomFloorAreas: [Double] = structure.rooms.map {
            $0.floors.reduce(0.0) { $0 + Double($1.dimensions.x * $1.dimensions.z) }
        }
        var totalArea = roomFloorAreas.reduce(0, +)
        if totalArea < 0.01 {
            // Fallback: structure.floors enthält alle Bodenflächen der Gesamtstruktur
            totalArea = structure.floors.reduce(0.0) { $0 + Double($1.dimensions.x * $1.dimensions.z) }
        }

        // 3. 2D-Geometrie für Grundriss (XZ-Projektion, Weltkoordinaten der Struktur)
        func makeWallGeo(_ t: simd_float4x4, _ dimX: Float) -> WallGeometry2D {
            let dx = Double(t.columns.0.x), dz = Double(t.columns.0.z)
            let len = sqrt(dx*dx + dz*dz)
            return WallGeometry2D(
                cx: Double(t.columns.3.x), cz: Double(t.columns.3.z),
                dirX: len > 1e-6 ? dx/len : 1, dirZ: len > 1e-6 ? dz/len : 0,
                width: Double(dimX)
            )
        }
        func makeOpeningGeo(_ t: simd_float4x4, _ dimX: Float) -> OpeningGeometry2D {
            let dx = Double(t.columns.0.x), dz = Double(t.columns.0.z)
            let len = sqrt(dx*dx + dz*dz)
            return OpeningGeometry2D(
                cx: Double(t.columns.3.x), cz: Double(t.columns.3.z),
                dirX: len > 1e-6 ? dx/len : 1, dirZ: len > 1e-6 ? dz/len : 0,
                width: Double(dimX)
            )
        }
        let wallGeos   = structure.walls.map   { makeWallGeo($0.transform, $0.dimensions.x) }
        let doorGeos   = structure.doors.map   { makeOpeningGeo($0.transform, $0.dimensions.x) }
        let windowGeos = structure.windows.map { makeOpeningGeo($0.transform, $0.dimensions.x) }

        // 4. USDZ — CapturedStructure exportiert alle Räume zusammen
        let usdzURL = folder.appendingPathComponent("scan.usdz")
        try autoreleasepool { try structure.export(to: usdzURL) }

        // 5. Raumbezeichnungen — zip mit structure.rooms (Anzahl kann abweichen)
        let resolvedNames: [String] = (0..<structure.rooms.count).map { i in
            i < roomNames.count ? roomNames[i] : "Raum \(i + 1)"
        }

        // 6. PDF
        let pdfURL = folder.appendingPathComponent("bericht.pdf")
        try FloorPlanRenderer.generateReport(
            wallMeasurements: wallM,
            doorMeasurements: doorM,
            windowMeasurements: windowM,
            wallGeometry: wallGeos,
            doorGeometry: doorGeos,
            windowGeometry: windowGeos,
            floorAreaM2: totalArea,
            address: nil,
            roomNames: resolvedNames,
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
            wallCount: structure.walls.count,
            doorCount: structure.doors.count,
            windowCount: structure.windows.count,
            objectCount: structure.objects.count,
            floorAreaM2: totalArea,
            wallMeasurements: wallM,
            doorMeasurements: doorM,
            windowMeasurements: windowM,
            wallGeometry: wallGeos,
            doorGeometry: doorGeos,
            windowGeometry: windowGeos,
            address: nil,
            roomNames: resolvedNames,
            roomFloorAreas: roomFloorAreas,
            roomPhotos: nil,
            moistureMeasurements: nil
        )
    }

    // MARK: - Fallback: Einzelräume wenn StructureBuilder fehlschlägt

    func saveFallback(rooms: [CapturedRoom], roomNames: [String]) throws -> ScanRecord {
        guard !rooms.isEmpty else {
            throw NSError(domain: "InnoviScan", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Keine Räume vorhanden."])
        }

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let relativePath = "Scans/\(schadensnummer)"
        let folder = docs.appendingPathComponent(relativePath, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // Maße aller Räume zusammenfassen (Größen korrekt; Positionen lokaler Koordinaten)
        let wallM = rooms.flatMap { room in
            room.walls.map {
                WallMeasurement(
                    width:      (Double($0.dimensions.x) * 100).rounded() / 100,
                    height:     (Double($0.dimensions.y) * 100).rounded() / 100,
                    confidence: $0.confidence.germanLabel
                )
            }
        }
        let doorM = rooms.flatMap { room in
            room.doors.map {
                SurfaceMeasurement(
                    width:  (Double($0.dimensions.x) * 100).rounded() / 100,
                    height: (Double($0.dimensions.y) * 100).rounded() / 100
                )
            }
        }
        let windowM = rooms.flatMap { room in
            room.windows.map {
                SurfaceMeasurement(
                    width:  (Double($0.dimensions.x) * 100).rounded() / 100,
                    height: (Double($0.dimensions.y) * 100).rounded() / 100
                )
            }
        }

        let roomFloorAreas: [Double] = rooms.map {
            $0.floors.reduce(0.0) { $0 + Double($1.dimensions.x * $1.dimensions.z) }
        }
        let totalArea = roomFloorAreas.reduce(0, +)

        // 2D-Geometrie nur vom ersten Raum (kein gemeinsames Koordinatensystem ohne StructureBuilder)
        let firstRoom = rooms[0]
        func makeWallGeo(_ t: simd_float4x4, _ dimX: Float) -> WallGeometry2D {
            let dx = Double(t.columns.0.x), dz = Double(t.columns.0.z)
            let len = sqrt(dx*dx + dz*dz)
            return WallGeometry2D(
                cx: Double(t.columns.3.x), cz: Double(t.columns.3.z),
                dirX: len > 1e-6 ? dx/len : 1, dirZ: len > 1e-6 ? dz/len : 0,
                width: Double(dimX)
            )
        }
        func makeOpeningGeo(_ t: simd_float4x4, _ dimX: Float) -> OpeningGeometry2D {
            let dx = Double(t.columns.0.x), dz = Double(t.columns.0.z)
            let len = sqrt(dx*dx + dz*dz)
            return OpeningGeometry2D(
                cx: Double(t.columns.3.x), cz: Double(t.columns.3.z),
                dirX: len > 1e-6 ? dx/len : 1, dirZ: len > 1e-6 ? dz/len : 0,
                width: Double(dimX)
            )
        }
        let wallGeos   = firstRoom.walls.map   { makeWallGeo($0.transform, $0.dimensions.x) }
        let doorGeos   = firstRoom.doors.map   { makeOpeningGeo($0.transform, $0.dimensions.x) }
        let windowGeos = firstRoom.windows.map { makeOpeningGeo($0.transform, $0.dimensions.x) }

        // USDZ vom ersten Raum
        let usdzURL = folder.appendingPathComponent("scan.usdz")
        try autoreleasepool { try firstRoom.export(to: usdzURL) }

        let resolvedNames: [String] = (0..<rooms.count).map { i in
            i < roomNames.count ? roomNames[i] : "Raum \(i + 1)"
        }

        let pdfURL = folder.appendingPathComponent("bericht.pdf")
        try FloorPlanRenderer.generateReport(
            wallMeasurements: wallM,
            doorMeasurements: doorM,
            windowMeasurements: windowM,
            wallGeometry: wallGeos,
            doorGeometry: doorGeos,
            windowGeometry: windowGeos,
            floorAreaM2: totalArea,
            address: nil,
            roomNames: resolvedNames,
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
            wallCount: wallM.count,
            doorCount: doorM.count,
            windowCount: windowM.count,
            objectCount: rooms.flatMap(\.objects).count,
            floorAreaM2: totalArea,
            wallMeasurements: wallM,
            doorMeasurements: doorM,
            windowMeasurements: windowM,
            wallGeometry: wallGeos,
            doorGeometry: doorGeos,
            windowGeometry: windowGeos,
            address: nil,
            roomNames: resolvedNames,
            roomFloorAreas: roomFloorAreas,
            roomPhotos: nil,
            moistureMeasurements: nil
        )
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
        // Gesamtseitenzahl vorab berechnen
        // Maßtabellen-Seitenanzahl schätzen (bei vielen Wänden > 1 Seite)
        let approxUsableH: CGFloat = 842 - 130 - 42
        var tableContentH: CGFloat = 118  // Intro: Schadensnummer + Datum + RAUMMAẞE
        tableContentH += 40 + (wallMeasurements.isEmpty   ? 19 : 22 + CGFloat(wallMeasurements.count)   * 19)
        tableContentH += 40 + (doorMeasurements.isEmpty   ? 19 : 22 + CGFloat(doorMeasurements.count)   * 19)
        tableContentH += 40 + (windowMeasurements.isEmpty ? 19 : 22 + CGFloat(windowMeasurements.count) * 19)
        tableContentH += 30
        let tablePageCount = max(1, Int(ceil(Double(tableContentH / approxUsableH))))
        var totalPages = 1 + tablePageCount  // Grundriss + geschätzte Maßtabellen-Seiten
        if let photos = roomPhotos {
            let roomOrder = roomNames ?? Array(photos.keys.sorted())
            for roomName in roomOrder {
                if let fileNames = photos[roomName], !fileNames.isEmpty {
                    let hasAny = fileNames.contains {
                        FileManager.default.fileExists(atPath: folderURL.appendingPathComponent($0).path)
                    }
                    if hasAny { totalPages += 1 }
                }
            }
        }
        if let moisture = moistureMeasurements, !moisture.isEmpty { totalPages += 1 }

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
        let pdfData = UIGraphicsPDFRenderer(bounds: pageRect).pdfData { ctx in

            // Seite 1: Grundriss
            drawPDFPage(context: ctx, walls: wallGeometry, doors: doorGeometry, windows: windowGeometry,
                        schadensnummer: schadensnummer, date: date, floorAreaM2: floorAreaM2,
                        address: address, roomNames: roomNames, roomFloorAreas: roomFloorAreas,
                        pageNum: 1, totalPages: totalPages)

            // Seite 2+: Maßtabelle (automatischer Seitenumbruch bei Überlauf)
            var currentPage = 2

            ctx.beginPage()
            var tblG = ctx.cgContext

            var tblHH = drawKRAFTHeader(g: tblG, pageW: 595, schadensnummer: schadensnummer,
                                        date: date, address: address, roomNames: roomNames,
                                        floorAreaM2: floorAreaM2)

            let sectionAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.systemBlue]
            let boldAttrs:    [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: UIColor.black]
            let bodyAttrs:    [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12),     .foregroundColor: UIColor.darkGray]

            let formatter = DateFormatter()
            formatter.dateStyle = .long; formatter.timeStyle = .short
            formatter.locale = Locale(identifier: "de_DE")

            var ty: CGFloat = tblHH + 14
            let pageBottom: CGFloat = 842 - 46  // Sicherheitsabstand zum Footer

            // Neue Seite innerhalb der Maßtabelle
            func tblNewPage() {
                drawFooter(g: tblG, pageW: 595, y: 842 - 28, pageNum: currentPage, totalPages: totalPages)
                currentPage += 1
                ctx.beginPage()
                tblG = ctx.cgContext
                tblHH = drawKRAFTHeader(g: tblG, pageW: 595, schadensnummer: schadensnummer,
                                         date: date, address: address, roomNames: roomNames,
                                         floorAreaM2: floorAreaM2)
                ty = tblHH + 14
            }

            func ttext(_ s: String, x: CGFloat = 40, attrs: [NSAttributedString.Key: Any] = bodyAttrs) {
                s.draw(at: CGPoint(x: x, y: ty), withAttributes: attrs)
            }
            func tnl(_ dy: CGFloat = 20) { ty += dy }
            func ensure(_ needed: CGFloat) { if ty + needed > pageBottom { tblNewPage() } }

            func tableHeader(_ cols: [(String, CGFloat)]) {
                tblG.setStrokeColor(UIColor.lightGray.cgColor); tblG.setLineWidth(0.5)
                tblG.move(to: CGPoint(x: 40, y: ty + 18)); tblG.addLine(to: CGPoint(x: 555, y: ty + 18)); tblG.strokePath()
                for (title, x) in cols { title.draw(at: CGPoint(x: x, y: ty), withAttributes: boldAttrs) }
                tnl(22)
            }
            func tableRow(_ cols: [(String, CGFloat)]) {
                ensure(19)
                for (val, x) in cols { val.draw(at: CGPoint(x: x, y: ty), withAttributes: bodyAttrs) }
                tnl(19)
            }

            ttext("Schadensnummer:", attrs: boldAttrs); ttext(schadensnummer, x: 200); tnl()
            ttext("Datum / Uhrzeit:", attrs: boldAttrs); ttext(formatter.string(from: date), x: 200); tnl(28)

            ttext("RAUMMAẞE", attrs: sectionAttrs); tnl(20)  // Fix 4: korrekte Schreibweise
            let areaText = floorAreaM2 > 0 ? String(format: "%.2f m²", floorAreaM2) : "–"
            ttext("Bodenfläche:", attrs: boldAttrs); ttext(areaText, x: 200); tnl()
            if let h = wallMeasurements.map(\.height).max() {
                ttext("Raumhöhe:", attrs: boldAttrs); ttext(String(format: "%.2f m", h), x: 200); tnl()
            }
            tnl(10)

            ensure(80)  // Section-Titel + Tabellenkopf + min. 1 Zeile
            ttext("WÄNDE  (\(wallMeasurements.count))", attrs: sectionAttrs); tnl(20)
            if wallMeasurements.isEmpty {
                ttext("Keine Wände erkannt.", attrs: bodyAttrs); tnl()
            } else {
                // Fix 5: neue Spalte "Fläche (m²)" = Länge × Höhe
                tableHeader([("Nr.", 40), ("Länge", 90), ("Höhe", 185), ("Fläche (m²)", 290)])
                for (i, w) in wallMeasurements.enumerated() {
                    let area = (w.width * w.height * 100).rounded() / 100
                    tableRow([("\(i+1)", 40), (String(format: "%.2f m", w.width), 90),
                              (String(format: "%.2f m", w.height), 185),
                              (String(format: "%.2f", area), 290)])
                }
            }
            tnl(10)

            ensure(80)
            ttext("TÜREN  (\(doorMeasurements.count))", attrs: sectionAttrs); tnl(20)
            if doorMeasurements.isEmpty {
                ttext("Keine Türen erkannt.", attrs: bodyAttrs); tnl()
            } else {
                tableHeader([("Nr.", 40), ("Breite", 90), ("Höhe", 200)])
                for (i, d) in doorMeasurements.enumerated() {
                    tableRow([("\(i+1)", 40), (String(format: "%.2f m", d.width), 90),
                              (String(format: "%.2f m", d.height), 200)])
                }
            }
            tnl(10)

            ensure(80)
            ttext("FENSTER  (\(windowMeasurements.count))", attrs: sectionAttrs); tnl(20)
            if windowMeasurements.isEmpty {
                ttext("Keine Fenster erkannt.", attrs: bodyAttrs); tnl()
            } else {
                tableHeader([("Nr.", 40), ("Breite", 90), ("Höhe", 200)])
                for (i, w) in windowMeasurements.enumerated() {
                    tableRow([("\(i+1)", 40), (String(format: "%.2f m", w.width), 90),
                              (String(format: "%.2f m", w.height), 200)])
                }
            }
            tnl(16)

            ensure(30)
            tblG.setStrokeColor(UIColor.lightGray.cgColor)
            tblG.move(to: CGPoint(x: 40, y: ty)); tblG.addLine(to: CGPoint(x: 555, y: ty)); tblG.strokePath()
            tnl(8)
            ttext("3D-Modell: Scan_\(schadensnummer).usdz  |  Erstellt mit InnoviScan", attrs: bodyAttrs)

            drawFooter(g: tblG, pageW: 595, y: 842 - 28, pageNum: currentPage, totalPages: totalPages)

            // Seite 3+: Fotos pro Raum (nur wenn vorhanden)
            // Bilder werden einzeln in autoreleasepool geladen, gezeichnet und sofort freigegeben.
            if let photos = roomPhotos, !photos.isEmpty {
                let roomOrder = roomNames ?? Array(photos.keys.sorted())
                for roomName in roomOrder {
                    guard let fileNames = photos[roomName], !fileNames.isEmpty else { continue }

                    // Prüfen ob mindestens eine Datei lesbar ist – ohne alle gleichzeitig zu laden
                    let hasAny = fileNames.contains { name in
                        FileManager.default.fileExists(atPath: folderURL.appendingPathComponent(name).path)
                    }
                    guard hasAny else { continue }

                    currentPage += 1
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

                    // Jedes Bild einzeln laden, zeichnen, sofort freigeben
                    for (i, name) in fileNames.enumerated() {
                        let col = CGFloat(i % cols)
                        let row = CGFloat(i / cols)
                        let px = 40 + col * (photoW + gap)
                        let py = photoY + row * (photoH + gap)
                        guard py + photoH <= 800 else { break }

                        autoreleasepool {
                            let imgURL = folderURL.appendingPathComponent(name)
                            guard let data = try? Data(contentsOf: imgURL),
                                  let img = UIImage(data: data) else { return }
                            img.draw(in: CGRect(x: px, y: py, width: photoW, height: photoH))
                            // img und data werden am Ende dieses autoreleasepool-Blocks freigegeben
                        }
                    }

                    drawFooter(g: gp, pageW: 595, y: 842 - 28, pageNum: currentPage, totalPages: totalPages)
                }
            }

            // Letzte Seite: Feuchtigkeitsmessung (nur wenn vorhanden)
            if let moisture = moistureMeasurements, !moisture.isEmpty {
                currentPage += 1
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

                drawFooter(g: gm, pageW: 595, y: 842 - 28, pageNum: currentPage, totalPages: totalPages)
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
        roomFloorAreas: [Double]? = nil,
        pageNum: Int = 1,
        totalPages: Int = 1
    ) {
        context.beginPage()
        let g = context.cgContext
        let pageW: CGFloat = 595
        let pageH: CGFloat = 842
        let footerH: CGFloat = 24
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
            height: pageH - headerH - 4 - footerH - 10
        )
        drawFloorPlan(g: g, in: drawRect,
                      walls: walls, doors: doors, windows: windows,
                      floorAreaM2: floorAreaM2, roomNames: roomNames,
                      roomFloorAreas: roomFloorAreas,
                      etage: address?.etage,
                      pageNum: pageNum, totalPages: totalPages)

        drawFooter(g: g, pageW: pageW, y: pageH - footerH + 4,
                   pageNum: pageNum, totalPages: totalPages)
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
        roomFloorAreas: [Double]? = nil,
        etage: String? = nil,
        pageNum: Int = 0,
        totalPages: Int = 0
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

        // Etage-Bezeichnung oben links im Grundriss-Bereich
        if let et = etage, !et.isEmpty {
            let etAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 8),
                .foregroundColor: UIColor(white: 0.35, alpha: 1)
            ]
            ("Etage: \(et)" as NSString).draw(at: CGPoint(x: ox + 4, y: oy + 4), withAttributes: etAttrs)
        }

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

        // Maßangaben + Wandnummern entlang der Wände (senkrecht versetzt)
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5),
            .foregroundColor: UIColor(white: 0.3, alpha: 1)
        ]
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 7),
            .foregroundColor: UIColor(red: 0.15, green: 0.3, blue: 0.85, alpha: 1)
        ]
        for (i, wall) in walls.enumerated() {
            let hw = wall.width / 2
            let p1 = cv(wall.cx + hw * wall.dirX, wall.cz + hw * wall.dirZ)
            let p2 = cv(wall.cx - hw * wall.dirX, wall.cz - hw * wall.dirZ)
            let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            let ang = atan2(Double(p2.y - p1.y), Double(p2.x - p1.x))
            let px = CGFloat(-sin(ang)) * 15
            let py = CGFloat( cos(ang)) * 15
            // Maßangabe (außen)
            let label = String(format: "%.2f m", wall.width)
                .replacingOccurrences(of: ".", with: ",")
            let sz = (label as NSString).size(withAttributes: dimAttrs)
            (label as NSString).draw(
                at: CGPoint(x: mid.x + px - sz.width/2, y: mid.y + py - sz.height/2),
                withAttributes: dimAttrs
            )
            // Wandnummer (innen, passend zur Tabelle)
            let numLabel = "\(i + 1)"
            let nsz = (numLabel as NSString).size(withAttributes: numAttrs)
            (numLabel as NSString).draw(
                at: CGPoint(x: mid.x - px - nsz.width/2, y: mid.y - py - nsz.height/2),
                withAttributes: numAttrs
            )
        }

        // Raumname + Fläche + Abmessungen in der Raummitte
        let hasRoomNames = !(roomNames?.filter { !$0.isEmpty }.isEmpty ?? true)
        if floorAreaM2 > 0.01 || hasRoomNames {
            let ps = NSMutableParagraphStyle(); ps.alignment = .center
            let roomLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor(white: 0.2, alpha: 1),
                .paragraphStyle: ps
            ]
            let names = roomNames?.filter { !$0.isEmpty } ?? []
            let areas = roomFloorAreas ?? []
            var lines: [String] = []
            let dimStr = String(format: "(%.2f × %.2f m)", worldW, worldH)
                .replacingOccurrences(of: ".", with: ",")
            for (i, name) in names.enumerated() {
                let areaStr = i < areas.count
                    ? String(format: "%.2f m²", areas[i]).replacingOccurrences(of: ".", with: ",")
                    : String(format: "%.2f m²", floorAreaM2).replacingOccurrences(of: ".", with: ",")
                lines.append("\(name)  \(areaStr)  \(dimStr)")
            }
            if lines.isEmpty {
                let areaStr = String(format: "%.2f m²", floorAreaM2).replacingOccurrences(of: ".", with: ",")
                lines.append("\(areaStr)  \(dimStr)")
            }
            let roomLabel = lines.joined(separator: "\n")
            let lw: CGFloat = 180, lh: CGFloat = CGFloat(lines.count) * 16 + 4
            (roomLabel as NSString).draw(
                in: CGRect(x: ox + scaledW/2 - lw/2, y: oy + scaledH/2 - lh/2,
                           width: lw, height: lh),
                withAttributes: roomLabelAttrs
            )
        }

        // Maßstabsleiste mit Ticks (0 – 0.5 – 1.0 – 1.5 – 2.0 – 2.5 m) + Maßstabszahl
        let barMeters: [Double] = [0, 0.5, 1.0, 1.5, 2.0, 2.5]
        let totalBarLen = CGFloat(barMeters.last ?? 2.5) * scale
        let bx = ox + (scaledW - totalBarLen) / 2
        let by = oy + scaledH + 16
        let sAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.5),
            .foregroundColor: UIColor(white: 0.25, alpha: 1)
        ]
        if by + 20 < rect.maxY {
            g.saveGState()
            g.setStrokeColor(UIColor(white: 0.25, alpha: 1).cgColor)
            g.setLineWidth(1.2)
            // Hauptlinie
            g.move(to: CGPoint(x: bx, y: by))
            g.addLine(to: CGPoint(x: bx + totalBarLen, y: by))
            // Ticks + Labels
            for m in barMeters {
                let tx = bx + CGFloat(m) * scale
                // Langer Tick nur bei vollen Metern, kurzer Tick bei 0,5-Werten
                let tickLen: CGFloat = m.truncatingRemainder(dividingBy: 1) == 0 ? 6 : 4
                g.move(to: CGPoint(x: tx, y: by - tickLen))
                g.addLine(to: CGPoint(x: tx, y: by + 3))
                // Beschriftung nur bei 0 und vollen Metern (kein 0.5, 1.5, 2.5)
                if m == 0 || m.truncatingRemainder(dividingBy: 1) == 0 {
                    let lbl = m == 0 ? "0" : String(format: "%.0f m", m)
                    let lsz = (lbl as NSString).size(withAttributes: sAttrs)
                    (lbl as NSString).draw(at: CGPoint(x: tx - lsz.width/2, y: by + 5),
                                           withAttributes: sAttrs)
                }
            }
            g.strokePath()
            g.restoreGState()
            // Maßstabszahl (1:XX)
            let mmPerPoint: Double = 210.0 / 595.0   // A4: 210mm = 595pt
            let scaleRatio = 1000.0 / (Double(scale) * mmPerPoint)
            let standards = [20, 25, 50, 75, 100, 125, 150, 200, 250, 500]
            let nearestScale = standards.min(by: { abs($0 - Int(scaleRatio.rounded())) < abs($1 - Int(scaleRatio.rounded())) }) ?? Int(scaleRatio.rounded())
            let scaleStr = "M 1:\(nearestScale)"
            let ssz = (scaleStr as NSString).size(withAttributes: sAttrs)
            (scaleStr as NSString).draw(
                at: CGPoint(x: bx + totalBarLen + 8, y: by - 2),
                withAttributes: sAttrs)
        }

        // Seitenzahl unten rechts
        if pageNum > 0 && totalPages > 0 {
            let pgAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor(white: 0.4, alpha: 1)
            ]
            let pgStr = "\(pageNum) / \(totalPages)"
            let psz = (pgStr as NSString).size(withAttributes: pgAttrs)
            (pgStr as NSString).draw(
                at: CGPoint(x: rect.maxX - psz.width, y: rect.maxY - psz.height - 2),
                withAttributes: pgAttrs)
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
    /// Links: Objekt-Infos gestapelt. Rechts: logokraftsystem.png (aspect-fit).
    /// Gibt die Höhe des Headers zurück.
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
        df.dateStyle = .medium; df.timeStyle = .short
        df.locale = Locale(identifier: "de_DE")

        let capAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 6.5),
            .foregroundColor: UIColor(white: 0.55, alpha: 1)
        ]
        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9.5),
            .foregroundColor: UIColor.black
        ]

        // ─── Rechts: Logo (aspect-fit in 130 × 55) ───
        let logoAreaW: CGFloat = 130, logoAreaH: CGFloat = 55
        let logoAreaX = pageW - margin - logoAreaW
        let logoAreaY: CGFloat = 10
        if let logo = UIImage(named: "kraft_logo") {
            let s = logo.size
            let r = min(logoAreaW / s.width, logoAreaH / s.height)
            let dw = s.width * r, dh = s.height * r
            logo.draw(in: CGRect(x: logoAreaX + (logoAreaW - dw) / 2,
                                 y: logoAreaY + (logoAreaH - dh) / 2,
                                 width: dw, height: dh))
        }

        // ─── Links: Objekt-Infos ───
        var y: CGFloat = 10
        let rowH: CGFloat = 19

        func infoRow(label: String, value: String) {
            let v = value.trimmingCharacters(in: .whitespaces)
            guard !v.isEmpty else { return }
            (label as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: capAttrs)
            y += 8
            (v as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: valAttrs)
            y += rowH
        }

        infoRow(label: "SCHADENSNUMMER", value: schadensnummer)
        infoRow(label: "DATUM / UHRZEIT", value: df.string(from: date))

        if let addr = address {
            let addrStr = [addr.street, addr.cityLine].filter { !$0.isEmpty }.joined(separator: ", ")
            infoRow(label: "ADRESSE", value: addrStr)
            infoRow(label: "ETAGE / LAGE", value: addr.etage)
        }

        if floorAreaM2 > 0 {
            let aStr = String(format: "%.2f m²", floorAreaM2)
                .replacingOccurrences(of: ".", with: ",")
            infoRow(label: "GRUNDFLÄCHE (SCAN)", value: aStr)
        }

        if let names = roomNames?.filter({ !$0.isEmpty }), !names.isEmpty {
            infoRow(label: "RÄUME", value: names.joined(separator: " · "))
        }

        // Unterkante: das Größere von Textblock und Logo
        let contentBottom = max(y, logoAreaY + logoAreaH + 6)

        // Trennlinie (volle Breite, dunkel)
        g.saveGState()
        g.setStrokeColor(UIColor(white: 0.2, alpha: 1).cgColor)
        g.setLineWidth(0.75)
        g.move(to: CGPoint(x: 0, y: contentBottom + 4))
        g.addLine(to: CGPoint(x: pageW, y: contentBottom + 4))
        g.strokePath()
        g.restoreGState()

        return contentBottom + 12
    }

    /// Fußzeile mit Firmenadresse und optionaler Seitenzahl.
    private static func drawFooter(g: CGContext, pageW: CGFloat, y: CGFloat,
                                   pageNum: Int = 0, totalPages: Int = 0) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.5),
            .foregroundColor: UIColor(white: 0.45, alpha: 1)
        ]
        // Trennlinie
        g.saveGState()
        g.setStrokeColor(UIColor(white: 0.3, alpha: 1).cgColor)
        g.setLineWidth(0.5)
        g.move(to: CGPoint(x: 0, y: y - 4))
        g.addLine(to: CGPoint(x: pageW, y: y - 4))
        g.strokePath()
        g.restoreGState()

        let company = "Kraft Systemtrocknung GmbH  ·  Mozartweg 2c, 63225 Langen  ·  Tel. 06103 270 54 50  ·  info@kraft-system.de"
        (company as NSString).draw(at: CGPoint(x: 36, y: y + 2), withAttributes: attrs)

        if pageNum > 0 && totalPages > 0 {
            let ps = "Seite \(pageNum) / \(totalPages)"
            let sz = (ps as NSString).size(withAttributes: attrs)
            (ps as NSString).draw(at: CGPoint(x: pageW - 36 - sz.width, y: y + 2),
                                  withAttributes: attrs)
        }
    }
}
