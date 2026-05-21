//
//  ScanDetailView.swift
//  InnoviScan
//

import SwiftUI
import SceneKit
import MessageUI
import UIKit

struct ScanDetailView: View {
    let record: ScanRecord

    @State private var scene: SCNScene? = nil
    @State private var floorPlanImage: UIImage? = nil
    @State private var showMail = false
    @State private var mailNotAvailableAlert = false
    @State private var mailResultMessage: String? = nil

    // Bearbeitbare Kopfdaten
    @State private var street: String = ""
    @State private var zip:    String = ""
    @State private var city:   String = ""
    @State private var etage:  String = ""
    @State private var roomNames: [String] = []
    @State private var saveConfirmation: String? = nil

    // Fotos pro Raum (nur Dateinamen im State – kein UIImage-RAM-Hold)
    @State private var roomPhotoFileNames: [String: [String]] = [:]
    @State private var showPhotoPicker: Bool = false
    @State private var photoPickerRoom: String = ""

    // Feuchtigkeitsmessungen
    @State private var moistureMeasurements: [MoistureMeasurement] = []
    @State private var showMoistureSheet: Bool = false

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    var body: some View {
        List {

            // MARK: 3D-Vorschau
            Section {
                if scene != nil {
                    SceneView(
                        scene: scene,
                        options: [.allowsCameraControl, .autoenablesDefaultLighting]
                    )
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("3D-Modell wird geladen…")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 32)
                }
            } header: {
                Text("3D-Vorschau")
            } footer: {
                Text("Mit einem Finger drehen · Mit zwei Fingern zoomen")
                    .font(.caption2)
            }

            // MARK: Grundriss-Vorschau
            if let img = floorPlanImage {
                Section {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 320)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                } header: {
                    Text("Grundriss (Draufsicht)")
                } footer: {
                    Text("Schwarz = Wände · Grün = Türen · Blau gestrichelt = Fenster · Seite 1 des PDF-Berichts")
                        .font(.caption2)
                }
            }

            // MARK: Metadaten
            Section {
                LabeledContent("Schadensnummer", value: record.schadensnummer)
                LabeledContent("Datum", value: dateFormatter.string(from: record.date))
            } header: {
                Text("Auftrag")
            }

            // MARK: Kopfdaten bearbeiten
            Section {
                TextField("Straße + Hausnummer", text: $street)
                HStack(spacing: 8) {
                    TextField("PLZ", text: $zip)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: 80)
                    TextField("Ort", text: $city)
                }
                TextField("Etage (z.B. 2. OG, EG)", text: $etage)

                if !roomNames.isEmpty {
                    ForEach(0..<roomNames.count, id: \.self) { i in
                        HStack {
                            TextField("Raum \(i + 1)", text: $roomNames[i])
                            if let areas = record.roomFloorAreas, i < areas.count {
                                Text(String(format: "%.1f m²", areas[i]))
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                }

                Button {
                    saveKopfdaten()
                } label: {
                    Label("Speichern & PDF aktualisieren", systemImage: "checkmark.circle")
                }

                if let msg = saveConfirmation {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } header: {
                Text("Adresse & Räume")
            } footer: {
                Text("Wird im PDF-Bericht verwendet.")
                    .font(.caption2)
            }

            // MARK: Raumdaten Übersicht
            Section {
                if record.floorAreaM2 > 0 {
                    LabeledContent("Bodenfläche",
                                   value: String(format: "%.2f m²", record.floorAreaM2))
                }
                if let h = record.roomHeightM {
                    LabeledContent("Raumhöhe", value: String(format: "%.2f m", h))
                }
                LabeledContent("Wände",   value: "\(record.wallCount)")
                LabeledContent("Türen",   value: "\(record.doorCount)")
                LabeledContent("Fenster", value: "\(record.windowCount)")
                LabeledContent("Objekte", value: "\(record.objectCount)")
            } header: {
                Text("Raummaße")
            }

            // MARK: Wände Detailtabelle
            if let walls = record.wallMeasurements, !walls.isEmpty {
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            Text("Nr.").bold()
                            Text("Länge").bold()
                            Text("Höhe").bold()
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(Array(walls.enumerated()), id: \.offset) { i, w in
                            GridRow {
                                Text("\(i + 1)")
                                Text(String(format: "%.2f m", w.width))
                                Text(String(format: "%.2f m", w.height))
                            }
                        }
                    }
                    .font(.system(.footnote, design: .monospaced))
                } header: { Text("Wände") }
            }

            // MARK: Türen Detailtabelle
            if let doors = record.doorMeasurements, !doors.isEmpty {
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            Text("Nr.").bold()
                            Text("Breite").bold()
                            Text("Höhe").bold()
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(Array(doors.enumerated()), id: \.offset) { i, d in
                            GridRow {
                                Text("\(i + 1)")
                                Text(String(format: "%.2f m", d.width))
                                Text(String(format: "%.2f m", d.height))
                            }
                        }
                    }
                    .font(.system(.footnote, design: .monospaced))
                } header: { Text("Türen") }
            }

            // MARK: Fenster Detailtabelle
            if let windows = record.windowMeasurements, !windows.isEmpty {
                Section {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        GridRow {
                            Text("Nr.").bold()
                            Text("Breite").bold()
                            Text("Höhe").bold()
                        }
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(Array(windows.enumerated()), id: \.offset) { i, w in
                            GridRow {
                                Text("\(i + 1)")
                                Text(String(format: "%.2f m", w.width))
                                Text(String(format: "%.2f m", w.height))
                            }
                        }
                    }
                    .font(.system(.footnote, design: .monospaced))
                } header: { Text("Fenster") }
            }

            // MARK: Fotos pro Raum
            if !roomNames.isEmpty {
                Section {
                    ForEach(roomNames, id: \.self) { room in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(room)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Button {
                                    photoPickerRoom = room
                                    showPhotoPicker = true
                                } label: {
                                    Label("Foto", systemImage: "camera")
                                        .font(.caption)
                                }
                            }
                            if let fileNames = roomPhotoFileNames[room], !fileNames.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(fileNames, id: \.self) { fileName in
                                            LazyPhotoThumb(
                                                fileURL: record.folderURL.appendingPathComponent(fileName)
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Fotos")
                }
            }

            // MARK: Feuchtigkeitsmessung
            Section {
                if moistureMeasurements.isEmpty {
                    Text("Noch keine Messpunkte.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(moistureMeasurements) { m in
                        HStack {
                            Text("\(m.nummer).")
                                .foregroundColor(.secondary)
                                .frame(width: 28, alignment: .leading)
                            Text(m.kategorie.rawValue)
                                .foregroundColor(m.kategorie == .wandflaeche ? .blue : .red)
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f %@", m.wert, m.einheit))
                                .font(.system(.subheadline, design: .monospaced))
                        }
                    }
                }
                Button {
                    showMoistureSheet = true
                } label: {
                    Label("Punkt hinzufügen", systemImage: "plus.circle")
                }
            } header: {
                Text("Feuchtigkeitsmessung")
            }

            // MARK: Aktionen
            Section {
                Button {
                    if MFMailComposeViewController.canSendMail() {
                        showMail = true
                    } else {
                        mailNotAvailableAlert = true
                    }
                } label: {
                    Label("An Büro senden", systemImage: "envelope")
                }

                if let msg = mailResultMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(msg.contains("gesendet") ? .green : .secondary)
                }
            }
        }
        .navigationTitle(record.schadensnummer)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Lade 3D-Modell
            scene = try? SCNScene(url: record.usdzURL, options: nil)

            // Initialisiere bearbeitbare Kopfdaten
            street = record.address?.street ?? ""
            zip    = record.address?.zip    ?? ""
            city   = record.address?.city   ?? ""
            etage  = record.address?.etage  ?? ""
            roomNames = record.roomNames ?? []

            // Nur Dateinamen laden – kein UIImage-Massen-Load (Lazy Loading in der UI)
            roomPhotoFileNames = record.roomPhotos ?? [:]

            // Feuchtigkeitsmessungen laden
            moistureMeasurements = record.moistureMeasurements ?? []

            // Grundriss-Vorschau rendern
            if let walls = record.wallGeometry, !walls.isEmpty {
                DispatchQueue.global(qos: .userInitiated).async {
                    let img = FloorPlanRenderer.renderPreviewImage(
                        walls: walls,
                        doors: record.doorGeometry ?? [],
                        windows: record.windowGeometry ?? [],
                        floorAreaM2: record.floorAreaM2,
                        roomNames: record.roomNames,
                        roomFloorAreas: record.roomFloorAreas
                    )
                    DispatchQueue.main.async { floorPlanImage = img }
                }
            }
        }
        .sheet(isPresented: $showMail) {
            MailComposerView(record: record, isPresented: $showMail) { result in
                switch result {
                case .sent:      mailResultMessage = "E-Mail gesendet ✓"
                case .saved:     mailResultMessage = "Als Entwurf gespeichert"
                case .cancelled: mailResultMessage = nil
                case .failed:    mailResultMessage = "Senden fehlgeschlagen"
                @unknown default: break
                }
            }
        }
        .alert("Kein Mail-Account", isPresented: $mailNotAvailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Bitte richte zuerst einen E-Mail-Account in der iOS Mail-App ein (Einstellungen → Mail → Account hinzufügen).")
        }
        .sheet(isPresented: $showPhotoPicker) {
            RoomPhotoPicker { image in
                savePhoto(image, forRoom: photoPickerRoom)
            }
        }
        .sheet(isPresented: $showMoistureSheet) {
            MoistureInputView(nextNummer: moistureMeasurements.count + 1) { measurement in
                saveMoistureMeasurement(measurement)
            }
        }
    }

    private func savePhoto(_ image: UIImage, forRoom room: String) {
        let safeName = room.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        let fileName = "photo_\(safeName)_\(UUID().uuidString.prefix(8)).jpg"
        let url = record.folderURL.appendingPathComponent(fileName)

        // Auf max. 2048px skalieren bevor speichern – Original-UIImage danach nicht mehr halten
        let scaled = image.scaledToFit(maxDimension: 2048)
        guard let data = scaled.jpegData(compressionQuality: 0.75) else { return }
        try? data.write(to: url)
        // 'scaled' und 'image' werden jetzt nicht mehr referenziert → sofort freigegeben

        // Nur Dateiname im State halten – kein UIImage
        var updatedNames = roomPhotoFileNames[room] ?? []
        updatedNames.append(fileName)
        roomPhotoFileNames[room] = updatedNames

        // ScanRecord persistieren
        let updatedRecord = ScanRecord(
            id: record.id,
            schadensnummer: record.schadensnummer,
            date: record.date,
            relativeFolderPath: record.relativeFolderPath,
            wallCount: record.wallCount,
            doorCount: record.doorCount,
            windowCount: record.windowCount,
            objectCount: record.objectCount,
            floorAreaM2: record.floorAreaM2,
            wallMeasurements: record.wallMeasurements,
            doorMeasurements: record.doorMeasurements,
            windowMeasurements: record.windowMeasurements,
            wallGeometry: record.wallGeometry,
            doorGeometry: record.doorGeometry,
            windowGeometry: record.windowGeometry,
            address: record.address,
            roomNames: record.roomNames,
            roomFloorAreas: record.roomFloorAreas,
            roomPhotos: roomPhotoFileNames,
            moistureMeasurements: record.moistureMeasurements
        )
        ScanStore.shared.update(updatedRecord)
    }

    private func saveMoistureMeasurement(_ m: MoistureMeasurement) {
        moistureMeasurements.append(m)
        let updatedRecord = ScanRecord(
            id: record.id,
            schadensnummer: record.schadensnummer,
            date: record.date,
            relativeFolderPath: record.relativeFolderPath,
            wallCount: record.wallCount,
            doorCount: record.doorCount,
            windowCount: record.windowCount,
            objectCount: record.objectCount,
            floorAreaM2: record.floorAreaM2,
            wallMeasurements: record.wallMeasurements,
            doorMeasurements: record.doorMeasurements,
            windowMeasurements: record.windowMeasurements,
            wallGeometry: record.wallGeometry,
            doorGeometry: record.doorGeometry,
            windowGeometry: record.windowGeometry,
            address: record.address,
            roomNames: record.roomNames,
            roomFloorAreas: record.roomFloorAreas,
            roomPhotos: roomPhotoFileNames.isEmpty ? record.roomPhotos : roomPhotoFileNames,
            moistureMeasurements: moistureMeasurements
        )
        ScanStore.shared.update(updatedRecord)
    }

    private func saveKopfdaten() {
        let newAddress = ScanAddress(street: street, zip: zip, city: city, etage: etage)

        let resolvedNames = roomNames.isEmpty ? nil : roomNames
        let updated = ScanRecord(
            id: record.id,
            schadensnummer: record.schadensnummer,
            date: record.date,
            relativeFolderPath: record.relativeFolderPath,
            wallCount: record.wallCount,
            doorCount: record.doorCount,
            windowCount: record.windowCount,
            objectCount: record.objectCount,
            floorAreaM2: record.floorAreaM2,
            wallMeasurements: record.wallMeasurements,
            doorMeasurements: record.doorMeasurements,
            windowMeasurements: record.windowMeasurements,
            wallGeometry: record.wallGeometry,
            doorGeometry: record.doorGeometry,
            windowGeometry: record.windowGeometry,
            address: newAddress,
            roomNames: resolvedNames,
            roomFloorAreas: record.roomFloorAreas,
            roomPhotos: roomPhotoFileNames.isEmpty ? record.roomPhotos : roomPhotoFileNames,
            moistureMeasurements: moistureMeasurements.isEmpty ? record.moistureMeasurements : moistureMeasurements
        )
        ScanStore.shared.update(updated)

        // PDF im Hintergrund neu generieren
        if let wallGeo = updated.wallGeometry {
            DispatchQueue.global(qos: .userInitiated).async {
                try? FloorPlanRenderer.generateReport(
                    wallMeasurements: updated.wallMeasurements ?? [],
                    doorMeasurements: updated.doorMeasurements ?? [],
                    windowMeasurements: updated.windowMeasurements ?? [],
                    wallGeometry: wallGeo,
                    doorGeometry: updated.doorGeometry ?? [],
                    windowGeometry: updated.windowGeometry ?? [],
                    floorAreaM2: updated.floorAreaM2,
                    address: newAddress,
                    roomNames: resolvedNames,
                    roomFloorAreas: updated.roomFloorAreas,
                    schadensnummer: updated.schadensnummer,
                    date: updated.date,
                    roomPhotos: updated.roomPhotos,
                    folderURL: updated.folderURL,
                    moistureMeasurements: updated.moistureMeasurements,
                    at: updated.pdfURL
                )
            }
        }

        saveConfirmation = "Gespeichert ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveConfirmation = nil
        }
    }
}

// MARK: - UIImage Memory-Hilfsfunktion

extension UIImage {
    /// Skaliert das Bild so, dass keine Seite größer als maxDimension ist.
    /// Gibt self zurück wenn das Bild bereits kleiner ist.
    func scaledToFit(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let ratio = maxDimension / maxSide
        let newSize = CGSize(width: (size.width * ratio).rounded(),
                             height: (size.height * ratio).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Lazy Foto-Thumbnail (lädt erst wenn sichtbar, hält nur 160px im RAM)

struct LazyPhotoThumb: View {
    let fileURL: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(ProgressView().scaleEffect(0.7))
            }
        }
        .frame(width: 80, height: 80)
        .clipped()
        .cornerRadius(6)
        .task {
            guard image == nil else { return }
            let url = fileURL
            image = await Task.detached(priority: .utility) {
                guard let data = try? Data(contentsOf: url),
                      let full = UIImage(data: data) else { return nil }
                return full.scaledToFit(maxDimension: 160)
            }.value
        }
    }
}

// MARK: - Kamera / Fotobibliothek Picker

struct RoomPhotoPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: RoomPhotoPicker
        init(_ parent: RoomPhotoPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.onImage(img)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Feuchtigkeitspunkt Eingabe

struct MoistureInputView: View {
    let nextNummer: Int
    let onSave: (MoistureMeasurement) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var wertText: String = ""
    @State private var einheit: String = "%"
    @State private var kategorie: MoistureKategorie = .wandflaeche

    var body: some View {
        NavigationStack {
            Form {
                Section("Messpunkt \(nextNummer)") {
                    HStack {
                        TextField("Wert", text: $wertText)
                            .keyboardType(.decimalPad)
                        Picker("Einheit", selection: $einheit) {
                            Text("%").tag("%")
                            Text("Digits").tag("Digits")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 130)
                    }
                }
                Section("Kategorie") {
                    Picker("Kategorie", selection: $kategorie) {
                        ForEach(MoistureKategorie.allCases, id: \.self) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Feuchtigkeitspunkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        guard let wert = Double(wertText.replacingOccurrences(of: ",", with: ".")) else { return }
                        let m = MoistureMeasurement(
                            id: UUID(),
                            nummer: nextNummer,
                            wert: wert,
                            einheit: einheit,
                            kategorie: kategorie
                        )
                        onSave(m)
                        dismiss()
                    }
                    .disabled(wertText.isEmpty)
                }
            }
        }
    }
}
