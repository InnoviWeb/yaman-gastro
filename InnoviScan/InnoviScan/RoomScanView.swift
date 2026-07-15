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
    let address: ScanAddress
    @Binding var isPresented: Bool
    var onDone: (Bool) -> Void

    func makeUIViewController(context: Context) -> RoomScanViewController {
        RoomScanViewController(schadensnummer: schadensnummer, address: address) { success in
            onDone(success)
            isPresented = false
        }
    }

    func updateUIViewController(_ uiViewController: RoomScanViewController, context: Context) {}
}

// MARK: - UIViewController

class RoomScanViewController: UIViewController {
    private let schadensnummer: String
    private let address: ScanAddress
    private let onDone: (Bool) -> Void

    private var roomCaptureView: RoomCaptureView!
    private var stopButton: UIButton!
    private var loadingOverlay: UIView!
    private var loadingLabel: UILabel!
    private var instructionLabel: UILabel!
    private var isProcessing = false

    private var roomCounter: Int = 1
    private var counterLabel: UILabel!
    private var cancelButton: UIButton!

    private var capturedRooms: [CapturedRoom] = []
    private var collectedRoomNames: [String] = []

    init(schadensnummer: String, address: ScanAddress, onDone: @escaping (Bool) -> Void) {
        self.schadensnummer = schadensnummer
        self.address        = address
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
        setupInstructionLabel()
        setupRoomCounter()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        roomCaptureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
        showHintIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        roomCaptureView.captureSession.stop()
    }

    // MARK: - UI Setup

    private func showHintIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "multiRoomHintShown") else { return }
        UserDefaults.standard.set(true, forKey: "multiRoomHintShown")

        let overlay = UIView()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let label = UILabel()
        label.text = "Scanne jeden Raum einzeln.\n\nHalte das iPhone beim Wechsel zwischen den Räumen weiter hoch, damit die Räume korrekt zusammengesetzt werden."
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .regular)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        let btn = UIButton(type: .system)
        btn.setTitle("Verstanden", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        btn.backgroundColor = .systemBlue
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 12
        btn.translatesAutoresizingMaskIntoConstraints = false

        overlay.addSubview(label)
        overlay.addSubview(btn)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -40),
            label.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32),
            btn.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            btn.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 32),
            btn.widthAnchor.constraint(equalToConstant: 160),
            btn.heightAnchor.constraint(equalToConstant: 48),
        ])

        let dismiss: () -> Void = { [weak overlay] in
            UIView.animate(withDuration: 0.25) { overlay?.alpha = 0 } completion: { _ in overlay?.removeFromSuperview() }
        }
        btn.addAction(UIAction { _ in dismiss() }, for: .touchUpInside)
    }

    private func setupStopButton() {
        // Primary: "Raum fertig"
        stopButton = UIButton(type: .system)
        stopButton.setTitle("Raum fertig", for: .normal)
        stopButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        stopButton.backgroundColor = .systemBlue
        stopButton.setTitleColor(.white, for: .normal)
        stopButton.layer.cornerRadius = 12
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        stopButton.addTarget(self, action: #selector(roomDone), for: .touchUpInside)
        view.addSubview(stopButton)

        // Secondary: "Scan abbrechen"
        cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Scan abbrechen", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 15)
        cancelButton.setTitleColor(UIColor.white.withAlphaComponent(0.75), for: .normal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelScan), for: .touchUpInside)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            stopButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stopButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -52),
            stopButton.widthAnchor.constraint(equalToConstant: 200),
            stopButton.heightAnchor.constraint(equalToConstant: 50),

            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.topAnchor.constraint(equalTo: stopButton.bottomAnchor, constant: 8),
        ])
    }

    private func setupInstructionLabel() {
        instructionLabel = UILabel()
        instructionLabel.text = "Kamera langsam durch den Raum bewegen"
        instructionLabel.textColor = .white
        instructionLabel.font = .systemFont(ofSize: 15, weight: .medium)
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 2
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        instructionLabel.layer.cornerRadius = 10
        instructionLabel.layer.masksToBounds = true
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)

        NSLayoutConstraint.activate([
            instructionLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            instructionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            instructionLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            instructionLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])
        instructionLabel.layoutMargins = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    }

    private func setupRoomCounter() {
        counterLabel = UILabel()
        counterLabel.textColor = .white
        counterLabel.font = .systemFont(ofSize: 14, weight: .medium)
        counterLabel.textAlignment = .center
        counterLabel.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        counterLabel.layer.cornerRadius = 8
        counterLabel.layer.masksToBounds = true
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(counterLabel)
        NSLayoutConstraint.activate([
            counterLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            counterLabel.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 8),
            counterLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            counterLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
        updateRoomCounter()
    }

    private func updateRoomCounter() {
        DispatchQueue.main.async {
            self.counterLabel.text = "  Raum \(self.roomCounter) wird gescannt  "
        }
    }

    private func suggestedRoomName(for room: CapturedRoom) -> String {
        // CapturedRoom.Section.Label → German room type name
        // Use the section with the most walls as the primary label
        guard #available(iOS 17, *) else { return "" }
        let labelCounts = room.sections
            .reduce(into: [CapturedRoom.Section.Label: Int]()) { dict, section in
                dict[section.label, default: 0] += 1
            }
        guard let dominant = labelCounts.max(by: { $0.value < $1.value })?.key else { return "" }
        switch dominant {
        case .livingRoom:  return "Wohnzimmer"
        case .kitchen:     return "Küche"
        case .bathroom:    return "Bad"
        case .bedroom:     return "Schlafzimmer"
        case .diningRoom:  return "Esszimmer"
        case .unidentified: return ""
        @unknown default:  return ""
        }
    }

    private func updateInstruction(_ text: String) {
        DispatchQueue.main.async {
            UIView.transition(with: self.instructionLabel,
                              duration: 0.25, options: .transitionCrossDissolve) {
                self.instructionLabel.text = "  \(text)  "
            }
        }
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

    @objc private func cancelScan() {
        roomCaptureView.captureSession.stop()
        onDone(false)
    }
}

// MARK: - RoomCaptureSessionDelegate

extension RoomScanViewController: RoomCaptureSessionDelegate {

    func captureSession(_ session: RoomCaptureSession,
                        didProvide instruction: RoomCaptureSession.Instruction) {
        let text: String
        switch instruction {
        case .normal:
            text = "Kamera langsam durch den Raum bewegen"
        case .moveCloseToWall:
            text = "Näher an die Wand herangehen"
        case .moveAwayFromWall:
            text = "Weiter von der Wand entfernen"
        case .slowDown:
            text = "Bitte langsamer bewegen"
        case .turnOnLight:
            text = "Bitte Licht einschalten"
        case .lowTexture:
            text = "Geringe Oberflächentextur – weiter bewegen"
        @unknown default:
            text = "Kamera langsam durch den Raum bewegen"
        }
        updateInstruction(text)
    }

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
                print("[DIAG] RoomBuilder erfolgreich. Wände: \(room.walls.count), Türen: \(room.doors.count), Objekte: \(room.objects.count)")
                let area = wallsAreaAndCentroid(room.walls).area
                let suggested = suggestedRoomName(for: room)
                let roomNum = roomCounter   // capture before async dispatch
                await MainActor.run {
                    self.capturedRooms.append(room)
                    print("[DIAG] capturedRooms.count nach append: \(self.capturedRooms.count)")
                    self.loadingOverlay.isHidden = true

                    // Show per-room naming sheet
                    let sheet = UIHostingController(rootView: RoomNameSheet(
                        roomNumber: roomNum,
                        suggestedName: suggested,
                        areaM2: area,
                        onNextRoom: { [weak self] name in
                            guard let self else { return }
                            self.collectedRoomNames.append(name)
                            self.dismiss(animated: true) {
                                self.roomCounter += 1
                                self.updateRoomCounter()
                                self.isProcessing = false  // allow next didEndWith
                                self.stopButton.isEnabled = true
                                self.cancelButton.isEnabled = true
                                self.roomCaptureView.captureSession.run(
                                    configuration: RoomCaptureSession.Configuration()
                                )
                            }
                        },
                        onAllDone: { [weak self] name in
                            guard let self else { return }
                            self.collectedRoomNames.append(name)
                            self.dismiss(animated: true) {
                                self.runStructureBuilder()
                            }
                        }
                    ))
                    sheet.modalPresentationStyle = .pageSheet
                    if let sheet2 = sheet.sheetPresentationController {
                        sheet2.detents = [.medium()]
                        sheet2.prefersGrabberVisible = false
                    }
                    self.present(sheet, animated: true)
                }
            } catch {
                print("[DIAG] RoomBuilder FEHLER: \(error)")
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

    /// Zeigt Benennungs-Screen mit Grundriss-Vorschau und m²-Werten für alle Räume
    func showNamingScreen(
        roomCount: Int,
        previewWalls: [WallGeometry2D] = [],
        previewDoors: [OpeningGeometry2D] = [],
        previewWindows: [OpeningGeometry2D] = [],
        previewCentroids: [ScanCentroid] = [],
        previewAreas: [Double] = [],
        presetNames: [String] = [],
        onConfirm: @escaping ([String]) -> Void
    ) {
        let view = RoomNamingView(
            roomCount: roomCount,
            previewWalls: previewWalls,
            previewDoors: previewDoors,
            previewWindows: previewWindows,
            previewCentroids: previewCentroids,
            roomAreas: previewAreas,
            presetNames: presetNames
        ) { [weak self] names in
            self?.dismiss(animated: true) { onConfirm(names) }
        }
        let namingVC = UIHostingController(rootView: view)
        namingVC.isModalInPresentation = true
        present(namingVC, animated: true)
    }

    func runStructureBuilder() {
        guard !capturedRooms.isEmpty else { showError("Keine Räume gescannt."); return }
        loadingLabel.text = "Räume werden verbunden…"
        loadingOverlay.isHidden = false

        Task {
            do {
                print("[DIAG] StructureBuilder startet mit \(capturedRooms.count) CapturedRoom(s)")
                let builder = StructureBuilder(options: [.beautifyObjects])
                let structure = try await builder.capturedStructure(from: capturedRooms)
                print("[DIAG] StructureBuilder erfolgreich. structure.rooms.count = \(structure.rooms.count), Wände: \(structure.walls.count), Türen: \(structure.doors.count)")

                // Geometrie für Grundriss-Vorschau im Benennungs-Screen vorberechnen
                func geoW(_ t: simd_float4x4, _ d: Float) -> WallGeometry2D {
                    let dx = Double(t.columns.0.x), dz = Double(t.columns.0.z)
                    let l = sqrt(dx*dx + dz*dz)
                    return WallGeometry2D(cx: Double(t.columns.3.x), cz: Double(t.columns.3.z),
                                         dirX: l > 1e-6 ? dx/l : 1, dirZ: l > 1e-6 ? dz/l : 0, width: Double(d))
                }
                func geoO(_ t: simd_float4x4, _ d: Float) -> OpeningGeometry2D {
                    let dx = Double(t.columns.0.x), dz = Double(t.columns.0.z)
                    let l = sqrt(dx*dx + dz*dz)
                    return OpeningGeometry2D(cx: Double(t.columns.3.x), cz: Double(t.columns.3.z),
                                             dirX: l > 1e-6 ? dx/l : 1, dirZ: l > 1e-6 ? dz/l : 0, width: Double(d))
                }
                let prevWalls    = structure.walls.map   { geoW($0.transform, $0.dimensions.x) }
                let prevDoors    = structure.doors.map   { geoO($0.transform, $0.dimensions.x) }
                let prevWindows  = structure.windows.map { geoO($0.transform, $0.dimensions.x) }
                let prevRoomData   = structure.rooms.map { self.wallsAreaAndCentroid($0.walls) }
                let prevCentroids  = prevRoomData.map { ScanCentroid(cx: $0.cx, cz: $0.cz) }
                let prevAreas      = prevRoomData.map(\.area)

                await MainActor.run {
                    self.loadingOverlay.isHidden = true
                    self.showNamingScreen(
                        roomCount: structure.rooms.count,
                        previewWalls: prevWalls,
                        previewDoors: prevDoors,
                        previewWindows: prevWindows,
                        previewCentroids: prevCentroids,
                        previewAreas: prevAreas,
                        presetNames: self.collectedRoomNames
                    ) { [weak self] names in
                        guard let self else { return }
                        self.loadingLabel.text = "Daten werden gespeichert…"
                        self.loadingOverlay.isHidden = false
                        Task {
                            do {
                                let record = try self.saveResults(structure: structure, roomNames: names)
                                await MainActor.run { ScanStore.shared.add(record); self.onDone(true) }
                            } catch {
                                await MainActor.run {
                                    self.loadingOverlay.isHidden = true
                                    self.showError(error.localizedDescription)
                                }
                            }
                        }
                    }
                }
            } catch {
                // StructureBuilder fehlgeschlagen — Fallback mit Einzelräumen
                print("[DIAG] StructureBuilder FEHLER → Fallback wird genutzt. Fehler: \(error)")
                // Vorschau aus dem ersten Raum (Fallback = lokale Koordinaten, nur 1 Raum zeigbar)
                let roomCount = self.capturedRooms.count
                print("[DIAG] Fallback: roomCount = \(roomCount)")
                let fbFirst = self.capturedRooms.first
                func fbGeoW(_ t: simd_float4x4, _ d: Float) -> WallGeometry2D {
                    let dx = Double(t.columns.0.x), dz = Double(t.columns.0.z)
                    let l = sqrt(dx*dx + dz*dz)
                    return WallGeometry2D(cx: Double(t.columns.3.x), cz: Double(t.columns.3.z),
                                         dirX: l > 1e-6 ? dx/l : 1, dirZ: l > 1e-6 ? dz/l : 0, width: Double(d))
                }
                func fbGeoO(_ t: simd_float4x4, _ d: Float) -> OpeningGeometry2D {
                    let dx = Double(t.columns.0.x), dz = Double(t.columns.0.z)
                    let l = sqrt(dx*dx + dz*dz)
                    return OpeningGeometry2D(cx: Double(t.columns.3.x), cz: Double(t.columns.3.z),
                                             dirX: l > 1e-6 ? dx/l : 1, dirZ: l > 1e-6 ? dz/l : 0, width: Double(d))
                }
                let fbWalls   = fbFirst.map { r in r.walls.map   { fbGeoW($0.transform, $0.dimensions.x) } } ?? []
                let fbDoors   = fbFirst.map { r in r.doors.map   { fbGeoO($0.transform, $0.dimensions.x) } } ?? []
                let fbWindows = fbFirst.map { r in r.windows.map { fbGeoO($0.transform, $0.dimensions.x) } } ?? []
                let fbRoomData  = self.capturedRooms.map { self.wallsAreaAndCentroid($0.walls) }
                let fbCentroid  = fbRoomData.map { ScanCentroid(cx: $0.cx, cz: $0.cz) }
                let fbAreas     = fbRoomData.map(\.area)
                await MainActor.run {
                    self.loadingOverlay.isHidden = true
                    self.showNamingScreen(
                        roomCount: roomCount,
                        previewWalls: fbWalls,
                        previewDoors: fbDoors,
                        previewWindows: fbWindows,
                        previewCentroids: fbCentroid,
                        previewAreas: fbAreas,
                        presetNames: self.collectedRoomNames
                    ) { [weak self] names in
                        guard let self else { return }
                        self.loadingLabel.text = "Daten werden gespeichert…"
                        self.loadingOverlay.isHidden = false
                        Task {
                            do {
                                let record = try self.saveFallback(rooms: self.capturedRooms, roomNames: names)
                                await MainActor.run { ScanStore.shared.add(record); self.onDone(true) }
                            } catch let fallbackError {
                                await MainActor.run {
                                    self.loadingOverlay.isHidden = true
                                    self.showError(fallbackError.localizedDescription)
                                }
                            }
                        }
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

        // 2. Bodenfläche + Schwerpunkt pro Raum via Wand-Polygon (Shoelace).
        // structure.rooms[i].floors ist in RoomPlan häufig leer (Floor-Detektor unzuverlässig
        // bei Teppich / glatten Böden). Daher Fläche aus den Wand-Eckpunkten berechnen.
        let roomData = structure.rooms.map { wallsAreaAndCentroid($0.walls) }
        var roomFloorAreas: [Double] = roomData.map(\.area)
        // Letzter Fallback auf structure.floors wenn kein Polygon eine sinnvolle Fläche ergibt
        if roomFloorAreas.allSatisfy({ $0 < 0.01 }) {
            let floorsAreas = structure.rooms.map {
                $0.floors.reduce(0.0) { $0 + Double($1.dimensions.x * $1.dimensions.z) }
            }
            if floorsAreas.contains(where: { $0 > 0.01 }) { roomFloorAreas = floorsAreas }
        }
        var totalArea = roomFloorAreas.reduce(0, +)
        if totalArea < 0.01 {
            totalArea = structure.floors.reduce(0.0) { $0 + Double($1.dimensions.x * $1.dimensions.z) }
        }

        // 2b. Raum-Schwerpunkte aus Wand-Polygon
        let roomCentroids: [ScanCentroid] = roomData.map { ScanCentroid(cx: $0.cx, cz: $0.cz) }

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
        let objectGeos: [ObjectGeometry2D] = structure.objects.map { obj in
            let t = obj.transform
            let dx = Double(t.columns.0.x), dz = Double(t.columns.0.z)
            let len = sqrt(dx*dx + dz*dz)
            return ObjectGeometry2D(
                cx:    Double(t.columns.3.x),
                cz:    Double(t.columns.3.z),
                dirX:  len > 1e-6 ? dx/len : 1,
                dirZ:  len > 1e-6 ? dz/len : 0,
                width: Double(obj.dimensions.x),
                depth: Double(obj.dimensions.z),
                label: objectLabel(for: obj.category)
            )
        }

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
            objectGeometry: objectGeos,
            roomCentroids: roomCentroids,
            floorAreaM2: totalArea,
            address: address,
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
            address: address,
            roomNames: resolvedNames,
            roomFloorAreas: roomFloorAreas,
            roomPhotos: nil,
            moistureMeasurements: nil,
            objectGeometry: objectGeos,
            manualWallMeasurements: nil,
            roomCentroids: roomCentroids
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

        // Fläche via Wand-Polygon (floors oft leer, s. wallsAreaAndCentroid)
        let fallbackRoomData = rooms.map { wallsAreaAndCentroid($0.walls) }
        let roomFloorAreas: [Double] = fallbackRoomData.map(\.area)
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
        let objectGeos: [ObjectGeometry2D] = rooms.flatMap { room in
            room.objects.map { obj in
                let t = obj.transform
                let dx = Double(t.columns.0.x), dz = Double(t.columns.0.z)
                let len = sqrt(dx*dx + dz*dz)
                return ObjectGeometry2D(
                    cx:    Double(t.columns.3.x),
                    cz:    Double(t.columns.3.z),
                    dirX:  len > 1e-6 ? dx/len : 1,
                    dirZ:  len > 1e-6 ? dz/len : 0,
                    width: Double(obj.dimensions.x),
                    depth: Double(obj.dimensions.z),
                    label: objectLabel(for: obj.category)
                )
            }
        }
        // Raum-Schwerpunkte aus Wand-Polygon (floors oft leer)
        let roomCentroids: [ScanCentroid] = fallbackRoomData.map { ScanCentroid(cx: $0.cx, cz: $0.cz) }

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
            objectGeometry: objectGeos,
            roomCentroids: roomCentroids,
            floorAreaM2: totalArea,
            address: address,
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
            address: address,
            roomNames: resolvedNames,
            roomFloorAreas: roomFloorAreas,
            roomPhotos: nil,
            moistureMeasurements: nil,
            objectGeometry: objectGeos,
            manualWallMeasurements: nil,
            roomCentroids: roomCentroids
        )
    }

    /// Berechnet Raumfläche (Shoelace über Wand-Eckpunkte) und Schwerpunkt.
    /// Fallback wenn structure.rooms[i].floors leer ist – passiert häufig in RoomPlan,
    /// weil der Floor-Detektor horizontale Flächen bei Teppich/Holz nicht zuverlässig erkennt.
    func wallsAreaAndCentroid(_ walls: [CapturedRoom.Surface]) -> (area: Double, cx: Double, cz: Double) {
        var pts: [(Double, Double)] = []
        for w in walls {
            let t = w.transform
            let wx = Double(t.columns.3.x), wz = Double(t.columns.3.z)
            let dx = Double(t.columns.0.x), dz = Double(t.columns.0.z)
            let len = sqrt(dx*dx + dz*dz)
            let ux = len > 1e-6 ? dx/len : 1.0, uz = len > 1e-6 ? dz/len : 0.0
            let halfW = Double(w.dimensions.x) / 2.0
            pts.append((wx - ux*halfW, wz - uz*halfW))
            pts.append((wx + ux*halfW, wz + uz*halfW))
        }
        guard pts.count >= 3 else { return (0, 0, 0) }
        let centX = pts.map(\.0).reduce(0, +) / Double(pts.count)
        let centZ = pts.map(\.1).reduce(0, +) / Double(pts.count)
        // Punkte nach Winkel sortieren → konvexes Polygon
        let sorted = pts.sorted {
            atan2($0.1 - centZ, $0.0 - centX) < atan2($1.1 - centZ, $1.0 - centX)
        }
        var area = 0.0
        let n = sorted.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += sorted[i].0 * sorted[j].1 - sorted[j].0 * sorted[i].1
        }
        return (abs(area) / 2.0, centX, centZ)
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

// MARK: - Per-Room Naming Sheet

struct RoomNameSheet: View {
    let roomNumber: Int
    let suggestedName: String
    let areaM2: Double
    let onNextRoom: (String) -> Void
    let onAllDone:  (String) -> Void

    @State private var name: String = ""
    @FocusState private var focused: Bool

    private let kraftBlue = Color(red: 0.04, green: 0.52, blue: 1)

    init(roomNumber: Int, suggestedName: String, areaM2: Double,
         onNextRoom: @escaping (String) -> Void, onAllDone: @escaping (String) -> Void) {
        self.roomNumber    = roomNumber
        self.suggestedName = suggestedName
        self.areaM2        = areaM2
        self.onNextRoom    = onNextRoom
        self.onAllDone     = onAllDone
        self._name = State(initialValue: suggestedName)
    }

    private var resolvedName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Raum \(roomNumber)" : t
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Bezeichnung")
                        TextField("z.B. Wohnzimmer, Küche…", text: $name)
                            .multilineTextAlignment(.trailing)
                            .focused($focused)
                    }
                    if areaM2 > 0.01 {
                        HStack {
                            Text("Fläche")
                            Spacer()
                            Text(String(format: "%.1f m²", areaM2))
                                .foregroundColor(kraftBlue)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Raum \(roomNumber)")
                }

                Section {
                    Button {
                        onNextRoom(resolvedName)
                    } label: {
                        HStack {
                            Spacer()
                            Label("Nächsten Raum scannen", systemImage: "arrow.right.circle.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .foregroundColor(kraftBlue)

                    Button {
                        onAllDone(resolvedName)
                    } label: {
                        HStack {
                            Spacer()
                            Label("Alle Räume fertig", systemImage: "checkmark.circle.fill")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .foregroundColor(.green)
                }
            }
            .navigationTitle("Raum benennen")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(true)
    }
}

// MARK: - Post-Scan Raum-Benennung (Grundriss + Liste)

struct RoomNamingView: View {
    let roomCount: Int
    let previewWalls: [WallGeometry2D]
    let previewDoors: [OpeningGeometry2D]
    let previewWindows: [OpeningGeometry2D]
    let previewCentroids: [ScanCentroid]
    let roomAreas: [Double]
    let presetNames: [String]
    @State private var names: [String]
    @State private var previewImage: UIImage?
    let onConfirm: ([String]) -> Void

    private let kraftBlue = Color(red: 0.04, green: 0.52, blue: 1)

    private var totalArea: Double { roomAreas.reduce(0, +) }

    init(roomCount: Int,
         previewWalls: [WallGeometry2D] = [],
         previewDoors: [OpeningGeometry2D] = [],
         previewWindows: [OpeningGeometry2D] = [],
         previewCentroids: [ScanCentroid] = [],
         roomAreas: [Double] = [],
         presetNames: [String] = [],
         onConfirm: @escaping ([String]) -> Void) {
        self.roomCount        = roomCount
        self.previewWalls     = previewWalls
        self.previewDoors     = previewDoors
        self.previewWindows   = previewWindows
        self.previewCentroids = previewCentroids
        self.roomAreas        = roomAreas
        self.presetNames      = presetNames
        self._names = State(initialValue: (0..<max(1, roomCount)).map { i in
            i < presetNames.count && !presetNames[i].isEmpty ? presetNames[i] : "Raum \(i + 1)"
        })
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Grundriss-Vorschau ──
                if !previewWalls.isEmpty {
                    Section {
                        Group {
                            if let img = previewImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                ZStack {
                                    Color(UIColor.secondarySystemBackground)
                                    ProgressView("Grundriss wird geladen…").font(.caption)
                                }
                                .aspectRatio(1, contentMode: .fit)
                            }
                        }
                        .frame(maxHeight: 280)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    } footer: {
                        Text("Nummerierte Kreise entsprechen den Zeilen unten.")
                            .font(.caption2)
                    }
                }

                // ── Räume ──
                Section {
                    ForEach(0..<names.count, id: \.self) { i in
                        HStack(spacing: 12) {
                            // Nummernkreis
                            ZStack {
                                Circle().fill(kraftBlue).frame(width: 30, height: 30)
                                Text("\(i + 1)")
                                    .font(.system(.callout, design: .rounded).bold())
                                    .foregroundColor(.white)
                            }
                            // Bezeichnung
                            TextField("z.B. Wohnzimmer, Küche…", text: $names[i])
                                .autocorrectionDisabled()
                            Spacer()
                            // m²
                            if i < roomAreas.count && roomAreas[i] > 0.01 {
                                Text(String(format: "%.1f m²", roomAreas[i]))
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundColor(kraftBlue)
                                    .monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text("Erkannte Räume")
                } footer: {
                    Text("Felder leer lassen = Standardname (Raum 1, 2 …)")
                        .font(.caption2)
                }

                // ── Gesamtfläche ──
                if totalArea > 0.01 {
                    Section {
                        HStack {
                            Label("Gesamtfläche", systemImage: "square.dashed")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(String(format: "%.1f m²", totalArea))
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundColor(kraftBlue)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Räume benennen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let resolved = names.enumerated().map { i, n in
                            n.trimmingCharacters(in: .whitespaces).isEmpty ? "Raum \(i + 1)" : n
                        }
                        onConfirm(resolved)
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                guard !previewWalls.isEmpty else { return }
                let w = previewWalls, d = previewDoors, wi = previewWindows, c = previewCentroids
                previewImage = await Task.detached(priority: .userInitiated) {
                    FloorPlanRenderer.renderNumberedPreview(
                        walls: w, doors: d, windows: wi, roomCentroids: c)
                }.value
            }
        }
    }
}

// MARK: - RoomPlan Object Category → Deutsch

private func objectLabel(for category: CapturedRoom.Object.Category) -> String {
    switch category {
    case .toilet:       return "WC"
    case .bathtub:      return "Wanne"
    case .sink:         return "Waschb."
    case .washerDryer:  return "Wsch."
    case .bed:          return "Bett"
    case .sofa:         return "Sofa"
    case .table:        return "Tisch"
    case .chair:        return "Stuhl"
    case .television:   return "TV"
    case .refrigerator: return "Kühlschr."
    case .oven:         return "Ofen"
    case .stove:        return "Herd"
    case .dishwasher:   return "Spüler"
    case .storage:      return "Schrank"
    case .stairs:       return "Treppe"
    case .fireplace:    return "Kamin"
    @unknown default:   return "Obj."
    }
}

// MARK: - FloorPlanAnnotation

struct FloorPlanAnnotation {
    /// Relative position within the floor plan image (0…1)
    var relX: Double
    var relY: Double
    var text: String
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
        objectGeometry: [ObjectGeometry2D] = [],
        roomCentroids: [ScanCentroid] = [],
        floorAreaM2: Double,
        address: ScanAddress?,
        roomNames: [String]?,
        roomFloorAreas: [Double]?,
        schadensnummer: String,
        date: Date,
        roomPhotos: [String: [String]]?,
        photoComments: [String: String]? = nil,
        folderURL: URL,
        moistureMeasurements: [MoistureMeasurement]?,
        annotations: [FloorPlanAnnotation]? = nil,
        at url: URL
    ) throws {
        // Gesamtseitenzahl exakt berechnen (Simulation der Tabellenseiten)
        let tablePageCount = simulateTablePageCount(
            wallMeasurements: wallMeasurements,
            doorMeasurements: doorMeasurements,
            windowMeasurements: windowMeasurements,
            address: address, roomNames: roomNames, roomFloorAreas: roomFloorAreas, floorAreaM2: floorAreaM2
        )
        let hasObjects = !objectGeometry.isEmpty
        var totalPages = 1 + (hasObjects ? 1 : 0) + tablePageCount  // Grundriss(se) + Maßtabellen
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

            // Seite 1: Grundriss mit Objekten
            drawPDFPage(context: ctx, walls: wallGeometry, doors: doorGeometry, windows: windowGeometry,
                        objects: objectGeometry, roomCentroids: roomCentroids,
                        schadensnummer: schadensnummer, date: date, floorAreaM2: floorAreaM2,
                        address: address, roomNames: roomNames, roomFloorAreas: roomFloorAreas,
                        annotations: annotations, showObjects: true,
                        pageNum: 1, totalPages: totalPages)

            // Seite 2 (optional): Grundriss ohne Objekte
            var currentPage = 2
            if hasObjects {
                drawPDFPage(context: ctx, walls: wallGeometry, doors: doorGeometry, windows: windowGeometry,
                            objects: objectGeometry, roomCentroids: roomCentroids,
                            schadensnummer: schadensnummer, date: date, floorAreaM2: floorAreaM2,
                            address: address, roomNames: roomNames, roomFloorAreas: roomFloorAreas,
                            annotations: annotations, showObjects: false,
                            pageNum: 2, totalPages: totalPages)
                currentPage = 3
            }

            // Nächste Seite: Maßtabelle (automatischer Seitenumbruch bei Überlauf)

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

            // RÄUME-Tabelle (nur wenn Raumnamen vorhanden)
            if let names = roomNames, !names.isEmpty {
                ensure(80)
                ttext("RÄUME  (\(names.count))", attrs: sectionAttrs); tnl(20)
                tableHeader([("Nr.", 40), ("Bezeichnung", 90), ("Fläche (m²)", 350)])
                let areas = roomFloorAreas ?? []
                for (i, name) in names.enumerated() {
                    let areaStr = i < areas.count && areas[i] > 0
                        ? String(format: "%.2f", areas[i])
                        : "–"
                    tableRow([("\(i+1)", 40), (name.isEmpty ? "–" : name, 90), (areaStr, 350)])
                }
                // Gesamtfläche-Zeile
                let total = areas.reduce(0, +)
                if total > 0 {
                    ensure(22)
                    tblG.setStrokeColor(UIColor.lightGray.cgColor); tblG.setLineWidth(0.5)
                    tblG.move(to: CGPoint(x: 40, y: ty)); tblG.addLine(to: CGPoint(x: 555, y: ty)); tblG.strokePath()
                    tnl(4)
                    ttext("Gesamt", x: 90, attrs: boldAttrs)
                    ttext(String(format: "%.2f m²", total), x: 350, attrs: boldAttrs)
                    tnl(22)
                }
                tnl(10)
            }

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
            ttext("3D-Modell: Scan_\(schadensnummer).usdz  |  Erstellt mit ScanIQ", attrs: bodyAttrs)

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

                    let photoW: CGFloat = 160, photoH: CGFloat = 120
                    let commentH: CGFloat = 14   // Zeile für Kommentar unter jedem Foto
                    let gap: CGFloat = 12
                    let cellH = photoH + commentH + 2  // Gesamthöhe pro Zelle
                    let cols = 3
                    let commentAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.italicSystemFont(ofSize: 8.5),
                        .foregroundColor: UIColor.darkGray
                    ]

                    // Jedes Bild einzeln laden, zeichnen, Kommentar darunter, sofort freigeben
                    for (i, name) in fileNames.enumerated() {
                        let col = CGFloat(i % cols)
                        let row = CGFloat(i / cols)
                        let px = 40 + col * (photoW + gap)
                        let py = photoY + row * (cellH + gap)
                        guard py + cellH <= 800 else { break }

                        autoreleasepool {
                            let imgURL = folderURL.appendingPathComponent(name)
                            guard let data = try? Data(contentsOf: imgURL),
                                  let img = UIImage(data: data) else { return }
                            img.draw(in: CGRect(x: px, y: py, width: photoW, height: photoH))
                        }

                        if let comment = photoComments?[name], !comment.isEmpty {
                            (comment as NSString).draw(
                                in: CGRect(x: px, y: py + photoH + 2, width: photoW, height: commentH),
                                withAttributes: commentAttrs)
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
        objects: [ObjectGeometry2D] = [],
        roomCentroids: [ScanCentroid] = [],
        schadensnummer: String,
        date: Date,
        floorAreaM2: Double,
        address: ScanAddress?,
        roomNames: [String]?,
        roomFloorAreas: [Double]? = nil,
        annotations: [FloorPlanAnnotation]? = nil,
        showObjects: Bool = true,
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

        // Subtitle when objects are hidden
        var extraHeaderH: CGFloat = 0
        if !showObjects {
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 9),
                .foregroundColor: UIColor.darkGray
            ]
            ("Grundriss ohne Objekte" as NSString).draw(
                at: CGPoint(x: margin, y: headerH + 2),
                withAttributes: subtitleAttrs
            )
            extraHeaderH = 14
        }

        let drawRect = CGRect(
            x: margin,
            y: headerH + extraHeaderH + 4,
            width: pageW - 2 * margin,
            height: pageH - headerH - extraHeaderH - 4 - footerH - 10
        )
        drawFloorPlan(g: g, in: drawRect,
                      walls: walls, doors: doors, windows: windows,
                      objects: objects,
                      roomCentroids: roomCentroids,
                      floorAreaM2: floorAreaM2, roomNames: roomNames,
                      roomFloorAreas: roomFloorAreas,
                      annotations: annotations,
                      etage: address?.etage,
                      pageNum: pageNum, totalPages: totalPages,
                      showObjects: showObjects)

        drawFooter(g: g, pageW: pageW, y: pageH - footerH + 4,
                   pageNum: pageNum, totalPages: totalPages)
    }

    // MARK: Vorschau-Bild (wird von ScanDetailView aufgerufen)

    static func renderPreviewImage(
        walls: [WallGeometry2D],
        doors: [OpeningGeometry2D],
        windows: [OpeningGeometry2D],
        objects: [ObjectGeometry2D] = [],
        roomCentroids: [ScanCentroid] = [],
        floorAreaM2: Double,
        roomNames: [String]? = nil,
        roomFloorAreas: [Double]? = nil,
        annotations: [FloorPlanAnnotation]? = nil,
        showObjects: Bool = true,
        manuallyChangedIndices: Set<Int> = [],
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
                objects: objects,
                roomCentroids: roomCentroids,
                floorAreaM2: floorAreaM2, roomNames: roomNames,
                roomFloorAreas: roomFloorAreas,
                annotations: annotations,
                imageSize: size,
                showObjects: showObjects,
                manuallyChangedIndices: manuallyChangedIndices
            )
        }
    }

    // MARK: - Benennungs-Vorschau mit nummerierten Kreisen

    /// Grundriss mit KRAFT-blauen Nummernkreisen — für den Benennungs-Screen
    static func renderNumberedPreview(
        walls: [WallGeometry2D],
        doors: [OpeningGeometry2D],
        windows: [OpeningGeometry2D],
        roomCentroids: [ScanCentroid],
        size: CGSize = CGSize(width: 480, height: 480)
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            let pad: CGFloat = 24
            drawFloorPlan(
                g: ctx.cgContext,
                in: CGRect(x: pad, y: pad, width: size.width - 2*pad, height: size.height - 2*pad),
                walls: walls, doors: doors, windows: windows,
                roomCentroids: roomCentroids,
                floorAreaM2: 0,
                showRoomNumbers: true
            )
        }
    }

    // MARK: - Maßlabel-Positionen (für Tap-Erkennung in ScanDetailView)

    /// Gibt die normalisierten Mittelpunkte aller Maßlinien-Labels zurück (0..1 relativ zur Bildgröße).
    static func wallLabelPositions(
        walls: [WallGeometry2D],
        doors: [OpeningGeometry2D],
        windows: [OpeningGeometry2D],
        size: CGSize = CGSize(width: 480, height: 480)
    ) -> [(wallIndex: Int, relX: Double, relY: Double)] {
        guard !walls.isEmpty else { return [] }
        let pad: CGFloat = 20
        let rect = CGRect(x: pad, y: pad, width: size.width - 2*pad, height: size.height - 2*pad)

        let longestWall = walls.max(by: { $0.width < $1.width })
        var rotAngle: Double = 0
        if let lw = longestWall {
            rotAngle = -atan2(lw.dirZ, lw.dirX)
            if rotAngle >  Double.pi / 2 { rotAngle -= Double.pi }
            if rotAngle <= -Double.pi / 2 { rotAngle += Double.pi }
        }
        let cosR = cos(rotAngle), sinR = sin(rotAngle)
        func rotW(_ wx: Double, _ wz: Double) -> (Double, Double) {
            (wx * cosR - wz * sinR, wx * sinR + wz * cosR)
        }

        var allX: [Double] = [], allZ: [Double] = []
        for w in walls {
            let hw = w.width / 2
            let (x1, z1) = rotW(w.cx + hw * w.dirX, w.cz + hw * w.dirZ)
            let (x2, z2) = rotW(w.cx - hw * w.dirX, w.cz - hw * w.dirZ)
            allX += [x1, x2]; allZ += [z1, z2]
        }
        for o in doors + windows {
            let hw = o.width / 2
            let (x1, z1) = rotW(o.cx + hw * o.dirX, o.cz + hw * o.dirZ)
            let (x2, z2) = rotW(o.cx - hw * o.dirX, o.cz - hw * o.dirZ)
            allX += [x1, x2]; allZ += [z1, z2]
        }
        guard let minX = allX.min(), let maxX = allX.max(),
              let minZ = allZ.min(), let maxZ = allZ.max() else { return [] }

        let worldW = max(maxX - minX, 0.1), worldH = max(maxZ - minZ, 0.1)
        let labelPad: CGFloat = 48
        let scale = min((rect.width - 2*labelPad) / CGFloat(worldW),
                        (rect.height - 2*labelPad) / CGFloat(worldH))
        let scaledW = CGFloat(worldW) * scale, scaledH = CGFloat(worldH) * scale
        let ox = rect.minX + labelPad + (rect.width  - 2*labelPad - scaledW) / 2
        let oy = rect.minY + labelPad + (rect.height - 2*labelPad - scaledH) / 2

        func cv(_ wx: Double, _ wz: Double) -> CGPoint {
            let (rx, rz) = rotW(wx, wz)
            return CGPoint(x: ox + CGFloat(rx - minX) * scale,
                           y: oy + CGFloat(rz - minZ) * scale)
        }

        var result: [(wallIndex: Int, relX: Double, relY: Double)] = []
        for (i, wall) in walls.enumerated() {
            let hw = wall.width / 2
            let p1 = cv(wall.cx + hw * wall.dirX, wall.cz + hw * wall.dirZ)
            let p2 = cv(wall.cx - hw * wall.dirX, wall.cz - hw * wall.dirZ)
            let ang = atan2(Double(p2.y - p1.y), Double(p2.x - p1.x))
            let perpX = CGFloat(-sin(ang)) * 15
            let perpY = CGFloat( cos(ang)) * 15
            let p1off = CGPoint(x: p1.x + perpX, y: p1.y + perpY)
            let p2off = CGPoint(x: p2.x + perpX, y: p2.y + perpY)
            let lx = (p1off.x + p2off.x) / 2
            let ly = (p1off.y + p2off.y) / 2 - 9
            result.append((wallIndex: i,
                           relX: Double(lx / size.width),
                           relY: Double(ly / size.height)))
        }
        return result
    }

    // MARK: - Kernzeichnung

    private static func drawFloorPlan(
        g: CGContext,
        in rect: CGRect,
        walls: [WallGeometry2D],
        doors: [OpeningGeometry2D],
        windows: [OpeningGeometry2D],
        objects: [ObjectGeometry2D] = [],
        roomCentroids: [ScanCentroid] = [],
        floorAreaM2: Double,
        roomNames: [String]? = nil,
        roomFloorAreas: [Double]? = nil,
        annotations: [FloorPlanAnnotation]? = nil,
        imageSize: CGSize = .zero,
        etage: String? = nil,
        pageNum: Int = 0,
        totalPages: Int = 0,
        showRoomNumbers: Bool = false,
        showObjects: Bool = true,
        manuallyChangedIndices: Set<Int> = []
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

        // Rotation: längste Wand horizontal ausrichten
        let longestWall = walls.max(by: { $0.width < $1.width })
        var rotAngle: Double = 0
        if let lw = longestWall {
            rotAngle = -atan2(lw.dirZ, lw.dirX)
            // Auf ±90° normieren (Wand ist in beide Richtungen gleich)
            if rotAngle >  Double.pi / 2 { rotAngle -= Double.pi }
            if rotAngle <= -Double.pi / 2 { rotAngle += Double.pi }
        }
        let cosR = cos(rotAngle), sinR = sin(rotAngle)
        // Rotation: Weltkoordinate → gedrehte Koordinate
        func rotW(_ wx: Double, _ wz: Double) -> (Double, Double) {
            (wx * cosR - wz * sinR, wx * sinR + wz * cosR)
        }

        // Bounding Box nach Rotation
        var allX: [Double] = [], allZ: [Double] = []
        for w in walls {
            let hw = w.width / 2
            let (x1, z1) = rotW(w.cx + hw * w.dirX, w.cz + hw * w.dirZ)
            let (x2, z2) = rotW(w.cx - hw * w.dirX, w.cz - hw * w.dirZ)
            allX += [x1, x2]; allZ += [z1, z2]
        }
        for o in doors + windows {
            let hw = o.width / 2
            let (x1, z1) = rotW(o.cx + hw * o.dirX, o.cz + hw * o.dirZ)
            let (x2, z2) = rotW(o.cx - hw * o.dirX, o.cz - hw * o.dirZ)
            allX += [x1, x2]; allZ += [z1, z2]
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

        // Welt (XZ) → Canvas: rotieren, ARKit-X direkt als Canvas-X (kein Spiegeln)
        func cv(_ wx: Double, _ wz: Double) -> CGPoint {
            let (rx, rz) = rotW(wx, wz)
            return CGPoint(x: ox + CGFloat(rx - minX) * scale,
                           y: oy + CGFloat(rz - minZ) * scale)
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

        // 1. Wände — Außenwände (nahe Bounding-Box-Rand) dicker als Innenwände
        let exteriorThreshold = 0.8
        g.setLineCap(.square)
        g.setStrokeColor(UIColor.black.cgColor)
        // Zuerst Innenwände (dünn), dann Außenwände (dick) → Außenwände überdecken Kreuzungen
        for pass in 0...1 {
            g.saveGState()
            for wall in walls {
                let (rcx, rcz) = rotW(wall.cx, wall.cz)
                let isExterior = (rcx - minX < exteriorThreshold) ||
                                 (maxX - rcx < exteriorThreshold) ||
                                 (rcz - minZ < exteriorThreshold) ||
                                 (maxZ - rcz < exteriorThreshold)
                let wantExterior = pass == 1
                guard isExterior == wantExterior else { continue }
                g.setLineWidth(isExterior ? 5.0 : 2.0)
                let hw = wall.width / 2
                let p1 = cv(wall.cx + hw * wall.dirX, wall.cz + hw * wall.dirZ)
                let p2 = cv(wall.cx - hw * wall.dirX, wall.cz - hw * wall.dirZ)
                g.move(to: p1); g.addLine(to: p2)
                g.strokePath()
            }
            g.restoreGState()
        }

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

        // 4. Objekte (Möbel, Sanitär) — gestrichelte orange Rechtecke mit Beschriftung
        if showObjects && !objects.isEmpty {
            let objLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 6.5),
                .foregroundColor: UIColor(red: 0.65, green: 0.35, blue: 0.0, alpha: 1)
            ]
            g.saveGState()
            g.setStrokeColor(UIColor(red: 0.8, green: 0.45, blue: 0.0, alpha: 0.85).cgColor)
            g.setLineWidth(1.2)
            g.setLineDash(phase: 0, lengths: [4, 3])
            for obj in objects {
                let center = cv(obj.cx, obj.cz)
                let halfW = CGFloat(obj.width / 2) * scale
                let halfD = CGFloat(obj.depth / 2) * scale
                // Richtungsvektor rotieren, direkt in Canvas-Space (kein Spiegeln mehr)
                let (rdx, rdz) = rotW(obj.dirX, obj.dirZ)
                let axW = CGPoint(x: CGFloat(rdx), y: CGFloat(rdz))
                let axD = CGPoint(x: -axW.y, y: axW.x)
                let corner1 = CGPoint(x: center.x + axW.x*halfW + axD.x*halfD,
                                      y: center.y + axW.y*halfW + axD.y*halfD)
                let corner2 = CGPoint(x: center.x - axW.x*halfW + axD.x*halfD,
                                      y: center.y - axW.y*halfW + axD.y*halfD)
                let corner3 = CGPoint(x: center.x - axW.x*halfW - axD.x*halfD,
                                      y: center.y - axW.y*halfW - axD.y*halfD)
                let corner4 = CGPoint(x: center.x + axW.x*halfW - axD.x*halfD,
                                      y: center.y + axW.y*halfW - axD.y*halfD)
                g.move(to: corner1)
                g.addLine(to: corner2)
                g.addLine(to: corner3)
                g.addLine(to: corner4)
                g.closePath()
                g.strokePath()
                let lsz = (obj.label as NSString).size(withAttributes: objLabelAttrs)
                (obj.label as NSString).draw(
                    at: CGPoint(x: center.x - lsz.width/2, y: center.y - lsz.height/2),
                    withAttributes: objLabelAttrs
                )
            }
            g.restoreGState()
        }

        // Maßangaben, Maßpfeile + Wandnummern entlang der Wände
        let dimAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8.5),
            .foregroundColor: UIColor(white: 0.3, alpha: 1)
        ]
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 7),
            .foregroundColor: UIColor(red: 0.15, green: 0.3, blue: 0.85, alpha: 1)
        ]

        // Hilfsfunktion: gefüllten Pfeilkopf zeichnen (Dreieck, Spitze bei `tip`, zeigt in Richtung `dir`)
        func drawArrowhead(at tip: CGPoint, direction dir: CGPoint) {
            let arrowLen: CGFloat = 8
            let arrowBase: CGFloat = 4
            let len = sqrt(dir.x * dir.x + dir.y * dir.y)
            guard len > 0.01 else { return }
            let ux = dir.x / len, uy = dir.y / len
            let px = -uy, py = ux
            let base = CGPoint(x: tip.x - ux * arrowLen, y: tip.y - uy * arrowLen)
            let left  = CGPoint(x: base.x + px * arrowBase, y: base.y + py * arrowBase)
            let right = CGPoint(x: base.x - px * arrowBase, y: base.y - py * arrowBase)
            g.saveGState()
            g.setFillColor(UIColor(white: 0.3, alpha: 1).cgColor)
            g.move(to: tip); g.addLine(to: left); g.addLine(to: right); g.closePath()
            g.fillPath()
            g.restoreGState()
        }

        for (i, wall) in walls.enumerated() {
            let hw = wall.width / 2
            let p1 = cv(wall.cx + hw * wall.dirX, wall.cz + hw * wall.dirZ)
            let p2 = cv(wall.cx - hw * wall.dirX, wall.cz - hw * wall.dirZ)
            let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
            let ang = atan2(Double(p2.y - p1.y), Double(p2.x - p1.x))
            let perpX = CGFloat(-sin(ang)) * 15
            let perpY = CGFloat( cos(ang)) * 15

            // Maßlinie (senkrecht versetzt von der Wand)
            let p1off = CGPoint(x: p1.x + perpX, y: p1.y + perpY)
            let p2off = CGPoint(x: p2.x + perpX, y: p2.y + perpY)

            let isManual = manuallyChangedIndices.contains(i)
            let dimLineColor = isManual
                ? UIColor(red: 0.85, green: 0.4, blue: 0.0, alpha: 1)
                : UIColor(white: 0.45, alpha: 1)

            g.saveGState()
            g.setStrokeColor(dimLineColor.cgColor)
            g.setLineWidth(isManual ? 1.1 : 0.7)
            g.move(to: p1off); g.addLine(to: p2off)
            g.move(to: p1); g.addLine(to: p1off)
            g.move(to: p2); g.addLine(to: p2off)
            g.strokePath()
            g.restoreGState()

            drawArrowhead(at: p1off, direction: CGPoint(x: p1off.x - p2off.x, y: p1off.y - p2off.y))
            drawArrowhead(at: p2off, direction: CGPoint(x: p2off.x - p1off.x, y: p2off.y - p1off.y))

            // Maßzahl parallel zur Maßlinie (rotiert wenn Wand nicht waagerecht)
            let label = String(format: "%.2f m", wall.width)
                .replacingOccurrences(of: ".", with: ",")
            let activeDimAttrs: [NSAttributedString.Key: Any] = isManual
                ? [.font: UIFont.boldSystemFont(ofSize: 8.5), .foregroundColor: UIColor(red: 0.85, green: 0.4, blue: 0.0, alpha: 1)]
                : dimAttrs
            let sz = (label as NSString).size(withAttributes: activeDimAttrs)
            // Winkel der Maßlinie im Canvas (p1off → p2off)
            let lineAngle = atan2(Double(p2off.y - p1off.y), Double(p2off.x - p1off.x))
            // Mittelpunkt der Maßlinie
            let labelCx = (p1off.x + p2off.x) / 2
            let labelCy = (p1off.y + p2off.y) / 2 - 9
            g.saveGState()
            g.translateBy(x: labelCx, y: labelCy)
            // Text in Leserichtung halten (kein Kopf-über-Drehen)
            var drawAngle = CGFloat(lineAngle)
            if drawAngle >  .pi / 2 { drawAngle -= .pi }
            if drawAngle < -.pi / 2 { drawAngle += .pi }
            g.rotate(by: drawAngle)
            (label as NSString).draw(
                at: CGPoint(x: -sz.width / 2, y: -sz.height / 2),
                withAttributes: activeDimAttrs)
            g.restoreGState()

            // Wandnummer auf der Wandinnenseite (ebenfalls parallel)
            let numLabel = "\(i + 1)"
            let nsz = (numLabel as NSString).size(withAttributes: numAttrs)
            let numCx = (p1.x + p2.x) / 2 - perpX
            let numCy = (p1.y + p2.y) / 2 - perpY
            g.saveGState()
            g.translateBy(x: numCx, y: numCy)
            var numAngle = CGFloat(lineAngle)
            if numAngle >  .pi / 2 { numAngle -= .pi }
            if numAngle < -.pi / 2 { numAngle += .pi }
            g.rotate(by: numAngle)
            (numLabel as NSString).draw(
                at: CGPoint(x: -nsz.width / 2, y: -nsz.height / 2),
                withAttributes: numAttrs)
            g.restoreGState()
        }

        // ─── Raum-Labels: Nummernkreise (Benennungs-Screen) oder Name+Fläche (finaler Grundriss) ───
        if showRoomNumbers && !roomCentroids.isEmpty {
            // Nummerierte KRAFT-blaue Kreise für den Benennungs-Screen
            let kraftBlue = UIColor(red: 0.04, green: 0.52, blue: 1, alpha: 1)
            let circleNumAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.white
            ]
            for (i, c) in roomCentroids.enumerated() {
                let pt = cv(c.cx, c.cz)
                let r: CGFloat = 16
                g.saveGState()
                g.setShadow(offset: CGSize(width: 0, height: 1), blur: 3,
                            color: UIColor.black.withAlphaComponent(0.3).cgColor)
                g.setFillColor(kraftBlue.cgColor)
                g.fillEllipse(in: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2))
                g.restoreGState()
                let numStr = "\(i + 1)"
                let nsz = (numStr as NSString).size(withAttributes: circleNumAttrs)
                (numStr as NSString).draw(
                    at: CGPoint(x: pt.x - nsz.width/2, y: pt.y - nsz.height/2),
                    withAttributes: circleNumAttrs)
            }
        } else {
            // Name + Fläche (finaler Grundriss + normale Vorschau)
            let hasRoomNames = !(roomNames?.filter { !$0.isEmpty }.isEmpty ?? true)
            if floorAreaM2 > 0.01 || hasRoomNames {
                let ps = NSMutableParagraphStyle(); ps.alignment = .center
                let roomLabelAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10),
                    .foregroundColor: UIColor(white: 0.2, alpha: 1),
                    .paragraphStyle: ps
                ]
                let allNames: [String] = roomNames.map { arr in
                    arr.enumerated().map { i, n in n.trimmingCharacters(in: .whitespaces).isEmpty ? "Raum \(i + 1)" : n }
                } ?? []
                let areas = roomFloorAreas ?? []
                let usePerRoomLabels = !roomCentroids.isEmpty
                    && roomCentroids.count == allNames.count && !allNames.isEmpty

                if usePerRoomLabels {
                    for (i, name) in allNames.enumerated() {
                        let c = roomCentroids[i]
                        let pt = cv(c.cx, c.cz)
                        let areaStr = i < areas.count && areas[i] > 0.01
                            ? String(format: "%.1f m²", areas[i]).replacingOccurrences(of: ".", with: ",") : ""
                        let text = [name, areaStr].filter { !$0.isEmpty }.joined(separator: "\n")
                        let lw: CGFloat = 120
                        let lh: CGFloat = CGFloat(text.components(separatedBy: "\n").count) * 14 + 2
                        (text as NSString).draw(
                            in: CGRect(x: pt.x - lw/2, y: pt.y - lh/2, width: lw, height: lh),
                            withAttributes: roomLabelAttrs)
                    }
                } else {
                    var lines: [String] = []
                    let dimStr = String(format: "(%.2f × %.2f m)", worldW, worldH)
                        .replacingOccurrences(of: ".", with: ",")
                    for (i, name) in allNames.enumerated() {
                        let areaStr = i < areas.count
                            ? String(format: "%.2f m²", areas[i]).replacingOccurrences(of: ".", with: ",")
                            : String(format: "%.2f m²", floorAreaM2).replacingOccurrences(of: ".", with: ",")
                        lines.append("\(name)  \(areaStr)  \(dimStr)")
                    }
                    if lines.isEmpty {
                        lines.append(String(format: "%.2f m²", floorAreaM2)
                            .replacingOccurrences(of: ".", with: ","))
                    }
                    let roomLabel = lines.joined(separator: "\n")
                    let lw: CGFloat = 200, lh: CGFloat = CGFloat(lines.count) * 16 + 4
                    (roomLabel as NSString).draw(
                        in: CGRect(x: ox + scaledW/2 - lw/2, y: oy + scaledH/2 - lh/2,
                                   width: lw, height: lh),
                        withAttributes: roomLabelAttrs)
                }
            }
        }

        // Manuell gesetzte Beschriftungen (relX/relY relativ zu imageSize oder rect)
        if let annotations = annotations, !annotations.isEmpty {
            let annotAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: UIColor(red: 0, green: 0.45, blue: 0.2, alpha: 1)
            ]
            // Koordinatenbasis: entweder volle imageSize (Vorschau) oder drawRect (PDF)
            let baseW = imageSize.width  > 0 ? imageSize.width  : rect.width
            let baseH = imageSize.height > 0 ? imageSize.height : rect.height
            let baseX = imageSize.width  > 0 ? CGFloat(0)       : rect.minX
            let baseY = imageSize.height > 0 ? CGFloat(0)       : rect.minY
            for ann in annotations {
                let ax = baseX + CGFloat(ann.relX) * baseW
                let ay = baseY + CGFloat(ann.relY) * baseH
                let sz = (ann.text as NSString).size(withAttributes: annotAttrs)
                let pad: CGFloat = 3
                let bgRect = CGRect(x: ax - sz.width/2 - pad, y: ay - sz.height/2 - pad,
                                    width: sz.width + pad*2, height: sz.height + pad*2)
                g.saveGState()
                g.setFillColor(UIColor.white.withAlphaComponent(0.82).cgColor)
                let pill = UIBezierPath(roundedRect: bgRect, cornerRadius: 3).cgPath
                g.addPath(pill); g.fillPath()
                g.restoreGState()
                (ann.text as NSString).draw(
                    at: CGPoint(x: ax - sz.width/2, y: ay - sz.height/2),
                    withAttributes: annotAttrs)
            }
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

    // MARK: - Seitenanzahl-Simulation (Fix 4)

    /// Schätzt die Kopfzeilen-Höhe basierend auf den Adressfeldern (ohne zu rendern).
    private static func estimatedHeaderH(
        address: ScanAddress?, roomNames: [String]?, floorAreaM2: Double
    ) -> CGFloat {
        var h: CGFloat = 10
        let rowH: CGFloat = 27
        h += rowH  // SCHADENSNUMMER
        h += rowH  // DATUM / UHRZEIT
        if let addr = address {
            if !addr.street.isEmpty || !addr.cityLine.isEmpty { h += rowH }
            if !addr.etage.isEmpty { h += rowH }
        }
        if floorAreaM2 > 0 { h += rowH }
        if let names = roomNames?.filter({ !$0.isEmpty }), !names.isEmpty { h += rowH }
        return max(h, 71) + 12  // 71 = Logohöhe-Untergrenze; +12: Trennlinie + Padding
    }

    /// Simuliert Tabellenumbruch und gibt exakte Seitenzahl zurück.
    private static func simulateTablePageCount(
        wallMeasurements: [WallMeasurement],
        doorMeasurements: [SurfaceMeasurement],
        windowMeasurements: [SurfaceMeasurement],
        address: ScanAddress?, roomNames: [String]?, roomFloorAreas: [Double]? = nil, floorAreaM2: Double
    ) -> Int {
        let hH = estimatedHeaderH(address: address, roomNames: roomNames, floorAreaM2: floorAreaM2)
        var ty: CGFloat = hH + 14
        let bottom: CGFloat = 842 - 46
        var pages = 1
        func ensure(_ n: CGFloat) { if ty + n > bottom { pages += 1; ty = hH + 14 } }
        func tnl(_ d: CGFloat = 20) { ty += d }

        // Schadensnummer + Datum
        tnl(); tnl(28)
        // RAUMMAẞE + Bodenfläche + Raumhöhe + Leerzeile
        tnl(20); tnl()
        if wallMeasurements.map(\.height).max() != nil { tnl() }
        tnl(10)
        // RÄUME
        if let names = roomNames, !names.isEmpty {
            ensure(80); tnl(20); tnl(22)
            names.forEach { _ in ensure(19); tnl(19) }
            let total = (roomFloorAreas ?? []).reduce(0, +)
            if total > 0 { ensure(22); tnl(26) }
            tnl(10)
        }
        // WÄNDE
        ensure(80); tnl(20)
        if wallMeasurements.isEmpty { tnl() } else { tnl(22); wallMeasurements.forEach { _ in ensure(19); tnl(19) } }
        tnl(10)
        // TÜREN
        ensure(80); tnl(20)
        if doorMeasurements.isEmpty { tnl() } else { tnl(22); doorMeasurements.forEach { _ in ensure(19); tnl(19) } }
        tnl(10)
        // FENSTER
        ensure(80); tnl(20)
        if windowMeasurements.isEmpty { tnl() } else { tnl(22); windowMeasurements.forEach { _ in ensure(19); tnl(19) } }
        return pages
    }

    /// Zeichnet den ScanIQ-Briefkopf auf jeder PDF-Seite.
    /// Links: Objekt-Infos gestapelt. Rechts: "ScanIQ – Schadendokumentation" Branding.
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

        // ─── Rechts: ScanIQ Branding ───
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 13),
            .foregroundColor: UIColor(red: 0.04, green: 0.52, blue: 1, alpha: 1)
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 7.5),
            .foregroundColor: UIColor(white: 0.5, alpha: 1)
        ]
        let brandText = "ScanIQ"
        let subText = "Schadendokumentation"
        let brandSize = (brandText as NSString).size(withAttributes: brandAttrs)
        let subSize   = (subText   as NSString).size(withAttributes: subAttrs)
        let brandX = pageW - margin - max(brandSize.width, subSize.width)
        (brandText as NSString).draw(at: CGPoint(x: brandX, y: 12), withAttributes: brandAttrs)
        (subText   as NSString).draw(at: CGPoint(x: brandX, y: 12 + brandSize.height + 2), withAttributes: subAttrs)
        let brandBottom = 12 + brandSize.height + 2 + subSize.height + 6

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

        // Unterkante: das Größere von Textblock und Branding
        let contentBottom = max(y, brandBottom)

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

        let company = "Erstellt mit ScanIQ  ·  www.innoviweb.de"
        (company as NSString).draw(at: CGPoint(x: 36, y: y + 2), withAttributes: attrs)

        if pageNum > 0 && totalPages > 0 {
            let ps = "Seite \(pageNum) / \(totalPages)"
            let sz = (ps as NSString).size(withAttributes: attrs)
            (ps as NSString).draw(at: CGPoint(x: pageW - 36 - sz.width, y: y + 2),
                                  withAttributes: attrs)
        }
    }
}
