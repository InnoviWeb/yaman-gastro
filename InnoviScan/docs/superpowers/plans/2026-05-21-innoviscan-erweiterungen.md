# InnoviScan Erweiterungen – Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 6 Features gleichzeitig umsetzen: 3 Bugfixes (Fenster-Rendering, Raumflächen, Confidence entfernen) + 3 neue Features (Fotos pro Raum, Feuchtigkeitsmessungen, Schadensnummer-Suche).

**Architecture:** Alle Änderungen verteilen sich auf die 4 bestehenden Swift-Dateien. `ScanStore.swift` bekommt neue Datenmodelle. `RoomScanView.swift` (enthält `FloorPlanRenderer`) bekommt Rendering-Fix und neue PDF-Seiten. `ScanDetailView.swift` bekommt neue UI-Sektionen. `ContentView.swift` bekommt die Suchleiste.

**Tech Stack:** SwiftUI, UIKit, RoomPlan, CoreGraphics (PDF), PHPickerViewController (Fotos), Codable (Persistenz)

---

## Datei-Übersicht

| Datei | Änderungen |
|---|---|
| `InnoviScan/ScanStore.swift` | + `MoistureMeasurement` struct + `MoistureKategorie` enum; `ScanRecord` bekommt `roomFloorAreas`, `roomPhotos`, `moistureMeasurements` |
| `InnoviScan/ContentView.swift` | + `.searchable` + gefilterte Liste |
| `InnoviScan/ScanDetailView.swift` | - Confidence-Spalte; + Foto-Sektion (PHPicker); + Feuchtigkeits-Sektion; `saveKopfdaten` überarbeitet |
| `InnoviScan/RoomScanView.swift` | Fix: Fenster zuletzt zeichnen; Fix: `roomFloorAreas` berechnen + speichern; - Confidence aus PDF-Tabelle; + Foto-PDF-Seite; + Feuchtigkeits-PDF-Seite |

---

## Task 1: Datenmodell erweitern (ScanStore.swift)

**Files:**
- Modify: `InnoviScan/ScanStore.swift`

- [ ] **Schritt 1.1: Neue Typen einfügen**

Füge direkt nach dem `OpeningGeometry2D`-Struct (nach Zeile 57) folgende neue Typen ein:

```swift
// MARK: - Feuchtigkeitsmessung

enum MoistureKategorie: String, Codable, CaseIterable {
    case wandflaeche  = "Wandfläche"
    case daemmschicht = "Dämmschicht"
}

struct MoistureMeasurement: Codable, Identifiable {
    let id: UUID
    let nummer: Int
    var wert: Double
    var einheit: String    // "%" oder "Digits"
    var kategorie: MoistureKategorie
}
```

- [ ] **Schritt 1.2: ScanRecord um neue Felder erweitern**

In `ScanRecord` nach `roomNames: [String]?` drei neue optionale Felder hinzufügen:

```swift
/// Bodenfläche pro Raum (parallel zu roomNames, nil bei älteren Scans)
let roomFloorAreas: [Double]?
/// Fotos pro Raum: Raumname → Array von Dateinamen (relativ zum folderURL)
let roomPhotos: [String: [String]]?
/// Feuchtigkeitsmessungen
let moistureMeasurements: [MoistureMeasurement]?
```

- [ ] **Schritt 1.3: ScanRecord-Initializer überall anpassen**

Da `ScanRecord` ein Struct ist, ändert Swift den memberwise init automatisch. Aber es gibt mehrere Stellen, wo `ScanRecord(...)` manuell aufgerufen wird (in `RoomScanView.swift` → `saveResults` und in `ScanDetailView.swift` → `saveKopfdaten`). Diese müssen die neuen Felder mit `nil` (Defaultwert für alte Daten) oder echten Werten bekommen.

In `RoomScanView.swift`, Funktion `saveResults`, das `return ScanRecord(...)` erweitern:

```swift
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
    roomFloorAreas: roomFloorAreas,   // NEU (wird in Task 3 befüllt)
    roomPhotos: nil,
    moistureMeasurements: nil
)
```

In `ScanDetailView.swift`, Funktion `saveKopfdaten`, das `ScanRecord(...)` erweitern:

```swift
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
    roomPhotos: record.roomPhotos,
    moistureMeasurements: record.moistureMeasurements
)
```

- [ ] **Schritt 1.4: Build prüfen**

In Xcode: `Cmd+B`. Erwartet: **Build Succeeded**. Falls Fehler wegen fehlendem Argument im ScanRecord-Init → die fehlende Stelle in RoomScanView.swift oder ScanDetailView.swift suchen und ebenfalls die 3 neuen nil-Argumente einfügen.

---

## Task 2: FIX 3 – Confidence / Zuverlässigkeit entfernen

**Files:**
- Modify: `InnoviScan/ScanDetailView.swift` (Zeile ~151–170)
- Modify: `InnoviScan/RoomScanView.swift` (Zeile ~455–461)

- [ ] **Schritt 2.1: Wände-Grid in ScanDetailView.swift bereinigen**

Die Section "Wände Detailtabelle" (ab ca. Zeile 150) zeigt aktuell 4 Spalten: Nr., Länge, Höhe, Güte. Die Güte-Spalte komplett entfernen:

```swift
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
```

- [ ] **Schritt 2.2: Wände-Tabelle im PDF bereinigen (RoomScanView.swift)**

In `generateReport`, die `tableHeader`/`tableRow`-Aufrufe für Wände anpassen. Die Spalte "Zuverlässigkeit" entfernen:

```swift
text("WÄNDE  (\(wallMeasurements.count))", attrs: sectionAttrs); nl(20)
if wallMeasurements.isEmpty { text("Keine Wände erkannt.", attrs: bodyAttrs); nl() } else {
    tableHeader([("Nr.", 40), ("Länge", 90), ("Höhe", 200)])
    for (i, w) in wallMeasurements.enumerated() {
        tableRow([("\(i+1)", 40), (String(format:"%.2f m", w.width), 90),
                  (String(format:"%.2f m", w.height), 200)])
    }
}
```

- [ ] **Schritt 2.3: Build prüfen**

`Cmd+B` → Build Succeeded. Danach in Simulator starten, einen alten Scan öffnen → in "Wände" sind nur noch Nr./Länge/Höhe sichtbar, keine Güte-Spalte.

---

## Task 3: FIX 2 – Raumflächen pro Raum berechnen und anzeigen

**Files:**
- Modify: `InnoviScan/RoomScanView.swift` (Funktion `saveResults`)
- Modify: `InnoviScan/ScanDetailView.swift` (Section Raummaße + Adresse & Räume)

- [ ] **Schritt 3.1: roomFloorAreas in saveResults berechnen**

In `saveResults` (RoomScanView.swift), direkt nach der `floorArea`-Berechnung, eine pro-Raum-Liste berechnen. RoomPlan liefert `room.floors` als Array (ein Element pro Raumebene/Bereich). Die Reihenfolge entspricht der Raum-Erkennungsreihenfolge — wir pairen sie per Index mit `roomNames`:

```swift
// Bodenfläche gesamt
let floorArea = room.floors.reduce(0.0) {
    $0 + Double($1.dimensions.x * $1.dimensions.z)
}

// Bodenfläche pro Raum (parallel zu roomNames)
let roomFloorAreas: [Double] = room.floors.map {
    Double($0.dimensions.x * $0.dimensions.z)
}
```

Hinweis: Wenn `room.floors.count != roomNames.count`, ist das unproblematisch — wir zeigen nur so viele Flächen wie Floors vorhanden. Die UI liest den Index sicher.

- [ ] **Schritt 3.2: roomFloorAreas in ScanRecord übergeben**

Das `return ScanRecord(...)` aus Task 1.3 ist bereits vorbereitet — `roomFloorAreas: roomFloorAreas` ist dort gesetzt. Sicherstellen, dass `roomFloorAreas` die Variable aus diesem Schritt ist.

- [ ] **Schritt 3.3: Raumfläche in ScanDetailView anzeigen**

In der Section "Adresse & Räume" (ScanDetailView.swift), den `ForEach` für roomNames anpassen, sodass neben dem Textfeld die berechnete Fläche steht:

```swift
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
```

- [ ] **Schritt 3.4: Raumfläche in FloorPlanRenderer je Raum anzeigen**

In `drawFloorPlan` (RoomScanView.swift), den Block "Raumname(n) + Fläche in der Raummitte" anpassen. Aktuell wird nur ein gemeinsamer Text gezeichnet. Die Funktion muss `roomFloorAreas` kennen. Da `drawFloorPlan` bereits `roomNames` empfängt, ergänze den Parameter:

```swift
private static func drawFloorPlan(
    g: CGContext,
    in rect: CGRect,
    walls: [WallGeometry2D],
    doors: [OpeningGeometry2D],
    windows: [OpeningGeometry2D],
    floorAreaM2: Double,
    roomNames: [String]? = nil,
    roomFloorAreas: [Double]? = nil   // NEU
) {
```

Alle Aufrufer von `drawFloorPlan` (in `generateReport`, `drawPDFPage`, `renderPreviewImage`) müssen `roomFloorAreas:` übergeben. In diesen Funktionen ebenfalls den Parameter ergänzen und durchreichen.

Den Raum-Label-Block im Inneren von `drawFloorPlan` anpassen:

```swift
// Raumname(n) + Fläche in der Raummitte
if floorAreaM2 > 0.01 {
    let ps = NSMutableParagraphStyle()
    ps.alignment = .center
    let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 11),
        .foregroundColor: UIColor.darkGray,
        .paragraphStyle: ps
    ]
    // Wenn mehrere Räume mit eigenen Flächen vorhanden: pro Raum zeigen
    let names = roomNames?.filter { !$0.isEmpty } ?? ["Raum"]
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
    let w: CGFloat = 100, h: CGFloat = CGFloat(lines.count) * 16 + 4
    (roomLabel as NSString).draw(
        in: CGRect(x: ox + scaledW/2 - w/2, y: oy + scaledH/2 - h/2,
                   width: w, height: h),
        withAttributes: labelAttrs
    )
}
```

- [ ] **Schritt 3.5: Alle Aufrufer von drawFloorPlan / renderPreviewImage / drawPDFPage aktualisieren**

`generateReport` und `renderPreviewImage` bekommen `roomFloorAreas` als neuen Parameter. Alle bestehenden Aufrufer (in `saveResults`, `saveKopfdaten`, `ScanDetailView.onAppear`) übergeben `roomFloorAreas: record.roomFloorAreas`.

`generateReport`-Signatur:
```swift
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
    roomFloorAreas: [Double]?,   // NEU
    schadensnummer: String,
    date: Date,
    at url: URL
) throws
```

`renderPreviewImage`-Signatur:
```swift
static func renderPreviewImage(
    walls: [WallGeometry2D],
    doors: [OpeningGeometry2D],
    windows: [OpeningGeometry2D],
    floorAreaM2: Double,
    roomNames: [String]? = nil,
    roomFloorAreas: [Double]? = nil,   // NEU
    size: CGSize = CGSize(width: 480, height: 480)
) -> UIImage
```

- [ ] **Schritt 3.6: Build prüfen**

`Cmd+B` → Build Succeeded.

---

## Task 4: FIX 1 – Fenster im Grundriss korrekt einzeichnen

**Files:**
- Modify: `InnoviScan/RoomScanView.swift` (Funktion `drawFloorPlan`)

**Problem:** In `drawFloorPlan` werden Fenster (blau gestrichelt) **vor** Türen und Wänden gezeichnet. Dicke schwarze Wände (3.5px) überdecken die Fensterlinien an den Öffnungen. Lösung: Zeichenreihenfolge umkehren → erst Wände, dann Türen, dann Fenster oben drauf.

- [ ] **Schritt 4.1: Zeichenreihenfolge in drawFloorPlan anpassen**

Den kompletten Zeichenblock neu anordnen. Die aktuelle Reihenfolge ist: Grid → Fenster → Türen → Wände → Maße → Raumname → Maßstabsleiste.

Neue Reihenfolge: Grid → Wände → Türen → Fenster → Maße → Raumname → Maßstabsleiste.

Schneide den Fenster-Block aus seiner aktuellen Position (nach dem Grid-Aufruf) heraus und füge ihn **nach** dem Türen-Block ein:

```swift
drawGrid(g: g, rect: CGRect(x: ox, y: oy, width: scaledW, height: scaledH))

// 1. Wände (schwarze, dicke Linien) – ZUERST
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

// 2. Türen (grüne Linie + Viertelbogen)
g.saveGState()
g.setStrokeColor(UIColor.systemGreen.cgColor)
g.setLineWidth(2)
for door in doors {
    let hw = door.width / 2
    let p1 = cv(door.cx + hw * door.dirX, door.cz + hw * door.dirZ)
    let p2 = cv(door.cx - hw * door.dirX, door.cz - hw * door.dirZ)
    g.move(to: p1); g.addLine(to: p2)
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

// 3. Fenster (blaue gestrichelte Linie) – ZULETZT, damit sie über Wänden sichtbar sind
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
```

Hinweis: Die Linienbreite der Fenster wurde von 2.5 auf 3 erhöht, damit sie über den Wänden deutlich sichtbar sind.

- [ ] **Schritt 4.2: Build + Sichtprüfung**

`Cmd+B` → Build Succeeded. Scan mit Fenstern öffnen → Grundriss-Vorschau muss blaue Linien zeigen, die die Wandlinien überlagern.

---

## Task 5: NEU 3 – Suche nach Schadensnummer (ContentView.swift)

**Files:**
- Modify: `InnoviScan/ContentView.swift`

- [ ] **Schritt 5.1: State-Variable und gefilterte Liste hinzufügen**

In `ContentView`, direkt nach den bestehenden `@State`-Properties einfügen:

```swift
@State private var searchText: String = ""
```

Direkt nach `store.records` eine berechnete Variable für gefilterte Ergebnisse:

```swift
private var filteredRecords: [ScanRecord] {
    if searchText.isEmpty { return store.records }
    return store.records.filter {
        $0.schadensnummer.localizedCaseInsensitiveContains(searchText)
    }
}
```

- [ ] **Schritt 5.2: ForEach auf filteredRecords umstellen**

Den `ForEach(store.records)` ersetzen durch `ForEach(filteredRecords)`. Die `onDelete`-Closure muss weiterhin auf `store.records` operieren. Da `onDelete` IndexSet liefert (relativ zur angezeigten Liste), bei Suche nicht löschen oder Indizes korrekt mappen:

```swift
ForEach(filteredRecords) { record in
    NavigationLink(destination: ScanDetailView(record: record)) {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.schadensnummer)
                .font(.headline)
            Text(dateFormatter.string(from: record.date))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
.onDelete { offsets in
    // Nur löschen wenn keine Suche aktiv (sonst falscher Index)
    guard searchText.isEmpty else { return }
    store.delete(at: offsets)
}
```

- [ ] **Schritt 5.3: .searchable Modifier hinzufügen**

An der `NavigationStack`, direkt nach `.toolbar { ... }` und vor `.fullScreenCover`:

```swift
.searchable(
    text: $searchText,
    placement: .navigationBarDrawer(displayMode: .always),
    prompt: "Schadensnummer suchen"
)
```

- [ ] **Schritt 5.4: Build + Test**

`Cmd+B` → Build Succeeded. Im Simulator: Suchfeld erscheint unter dem Nav-Titel, Eingabe filtert die Liste sofort, leeres Feld zeigt alle Scans.

---

## Task 6: NEU 1 – Fotos pro Raum

**Files:**
- Modify: `InnoviScan/ScanDetailView.swift`
- Modify: `InnoviScan/RoomScanView.swift` (generateReport, neue PDF-Seite)

- [ ] **Schritt 6.1: State-Variablen für Fotos in ScanDetailView**

In `ScanDetailView`, nach den bestehenden `@State`-Properties einfügen:

```swift
@State private var roomPhotos: [String: [UIImage]] = [:]        // Raumname → geladene UIImages (für Anzeige)
@State private var roomPhotoFileNames: [String: [String]] = [:]  // Raumname → Dateinamen (für Persistenz, bleibt aktuell)
@State private var showPhotoPicker: Bool = false
@State private var photoPickerRoom: String = ""
```

- [ ] **Schritt 6.2: Fotos beim Start laden (onAppear)**

In `.onAppear { }`, nach dem Laden der Kopfdaten, Fotos aus Dateisystem laden:

```swift
// Fotos laden
var loadedPhotos: [String: [UIImage]] = [:]
let storedFileNames = record.roomPhotos ?? [:]
for (roomName, fileNames) in storedFileNames {
    let images = fileNames.compactMap { name -> UIImage? in
        let url = record.folderURL.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    if !images.isEmpty { loadedPhotos[roomName] = images }
}
roomPhotos = loadedPhotos
roomPhotoFileNames = storedFileNames   // State-Spiegel für Persistenz
```

- [ ] **Schritt 6.3: Foto-Sektion in der UI einbauen**

Nach der Fenster-Detailtabelle und vor der Aktionen-Section eine neue Section "Fotos" einfügen. Die Räume kommen aus `roomNames` (State-Variable):

```swift
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
                        Label("Foto aufnehmen", systemImage: "camera")
                            .font(.caption)
                    }
                }
                if let images = roomPhotos[room], !images.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, img in
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipped()
                                    .cornerRadius(6)
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
```

- [ ] **Schritt 6.4: PHPickerViewController einbinden**

Am Ende von `ScanDetailView`, vor dem schließenden `}`, einen Wrapper hinzufügen:

```swift
// MARK: - PHPicker Wrapper (Kamera + Bibliothek)
struct RoomPhotoPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

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
```

Dann in `ScanDetailView.body`, nach dem `.alert(...)` Modifier, das Sheet einbinden:

```swift
.sheet(isPresented: $showPhotoPicker) {
    RoomPhotoPicker { image in
        savePhoto(image, forRoom: photoPickerRoom)
    }
}
```

- [ ] **Schritt 6.5: savePhoto-Funktion implementieren**

Private Funktion in `ScanDetailView` (neben `saveKopfdaten`):

```swift
private func savePhoto(_ image: UIImage, forRoom room: String) {
    let fileName = "photo_\(room.filter { $0.isLetter || $0.isNumber })_\(UUID().uuidString.prefix(8)).jpg"
    let url = record.folderURL.appendingPathComponent(fileName)
    guard let data = image.jpegData(compressionQuality: 0.8) else { return }
    try? data.write(to: url)

    // UI-State aktualisieren
    var updatedImages = roomPhotos[room] ?? []
    updatedImages.append(image)
    roomPhotos[room] = updatedImages

    // Dateinamen-State aktualisieren (wird von saveKopfdaten genutzt)
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
        roomPhotos: roomPhotoFileNames,   // Nutzt State-Variable, nicht record.roomPhotos
        moistureMeasurements: record.moistureMeasurements
    )
    ScanStore.shared.update(updatedRecord)
}
```

Hinweis: `record` in `ScanDetailView` ist eine `let`-Konstante. Die Funktion aktualisiert den Store, aber `record` in dieser View-Instanz bleibt unverändert bis die View neu geladen wird. Das ist für Fotos (sofortige UI-Anzeige via `roomPhotos`-State) ausreichend.

- [ ] **Schritt 6.6: Foto-Seite im PDF (FloorPlanRenderer)**

In `generateReport` (RoomScanView.swift), nach der Maßtabellen-Seite eine neue Seite für Fotos hinzufügen. Der Funktion muss `roomPhotos: [String: [String]]?` und `folderURL: URL` übergeben werden:

Neue Parameter in `generateReport`:
```swift
roomPhotos: [String: [String]]?,
folderURL: URL
```

Nach dem bestehenden Seite-2-Block (Maßtabelle), eine optionale Foto-Seite:

```swift
// Seite 3: Fotos (nur wenn vorhanden)
if let photos = roomPhotos, !photos.isEmpty {
    let roomOrder = roomNames ?? Array(photos.keys.sorted())
    for roomName in roomOrder {
        guard let fileNames = photos[roomName], !fileNames.isEmpty else { continue }
        let images = fileNames.compactMap { name -> UIImage? in
            let url = folderURL.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
        guard !images.isEmpty else { continue }

        ctx.beginPage()
        let g2 = ctx.cgContext
        let _ = drawKRAFTHeader(g: g2, pageW: 595, schadensnummer: schadensnummer,
                                date: date, address: address, roomNames: roomNames,
                                floorAreaM2: floorAreaM2)

        // Raumname als Überschrift
        var photoY: CGFloat = 130
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor.systemBlue
        ]
        (roomName as NSString).draw(at: CGPoint(x: 40, y: photoY), withAttributes: titleAttrs)
        photoY += 22

        // Fotos: max 3 pro Zeile
        let photoW: CGFloat = 160, photoH: CGFloat = 120, gap: CGFloat = 10
        let cols = 3
        for (i, img) in images.enumerated() {
            let col = CGFloat(i % cols)
            let row = CGFloat(i / cols)
            let x = 40 + col * (photoW + gap)
            let y = photoY + row * (photoH + gap)
            if y + photoH > 800 { break }   // Seitenende-Schutz
            img.draw(in: CGRect(x: x, y: y, width: photoW, height: photoH))
        }
    }
}
```

Alle Aufrufer von `generateReport` (in `saveResults` und `saveKopfdaten`) müssen `roomPhotos` und `folderURL` übergeben.

In `saveResults`:
```swift
try FloorPlanRenderer.generateReport(
    ...
    roomFloorAreas: roomFloorAreas,
    roomPhotos: nil,        // Noch keine Fotos bei erstem Scan
    folderURL: folder,
    ...
)
```

In `saveKopfdaten` (ScanDetailView.swift):
```swift
try FloorPlanRenderer.generateReport(
    ...
    roomFloorAreas: updated.roomFloorAreas,
    roomPhotos: updated.roomPhotos,
    folderURL: updated.folderURL,
    ...
)
```

- [ ] **Schritt 6.7: Info.plist – Kamera-Permission**

In Xcode: `InnoviScan` Target → Info → "+ Add Row" → `NSCameraUsageDescription` = `"InnoviScan benötigt die Kamera, um Fotos der gescannten Räume aufzunehmen."`. Und `NSPhotoLibraryUsageDescription` = `"InnoviScan benötigt Zugriff auf die Fotobibliothek."`.

- [ ] **Schritt 6.8: Build + Test**

`Cmd+B` → Build Succeeded. Im Simulator: Scan öffnen → Section "Fotos" sichtbar, Kamera-Button pro Raum vorhanden. (Kamera funktioniert nur auf echtem Gerät.)

---

## Task 7: NEU 2 – Feuchtigkeitsmessungen

**Files:**
- Modify: `InnoviScan/ScanDetailView.swift`
- Modify: `InnoviScan/RoomScanView.swift` (neue PDF-Seite)

- [ ] **Schritt 7.1: State-Variablen für Feuchtigkeitsmessungen**

In `ScanDetailView`, nach den Foto-State-Variablen einfügen:

```swift
@State private var moistureMeasurements: [MoistureMeasurement] = []
@State private var showMoistureSheet: Bool = false
```

- [ ] **Schritt 7.2: Messungen beim Start laden (onAppear)**

In `.onAppear`, nach dem Fotos-Ladeblock:

```swift
moistureMeasurements = record.moistureMeasurements ?? []
```

- [ ] **Schritt 7.3: Feuchtigkeits-Sektion in der UI einbauen**

Nach der Fotos-Section (und vor der Aktionen-Section) eine neue Section einfügen:

```swift
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
```

- [ ] **Schritt 7.4: Eingabe-Sheet für Feuchtigkeitspunkt**

Eigener View `MoistureInputView` (kann am Ende von ScanDetailView.swift stehen, vor dem Datei-Ende):

```swift
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
```

Das Sheet in `ScanDetailView.body` registrieren (nach dem Foto-Sheet):

```swift
.sheet(isPresented: $showMoistureSheet) {
    MoistureInputView(nextNummer: moistureMeasurements.count + 1) { measurement in
        saveMoistureMeasurement(measurement)
    }
}
```

- [ ] **Schritt 7.5: saveMoistureMeasurement-Funktion**

```swift
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
        roomPhotos: record.roomPhotos,
        moistureMeasurements: moistureMeasurements
    )
    ScanStore.shared.update(updatedRecord)
}
```

- [ ] **Schritt 7.6: Feuchtigkeits-PDF-Seite (FloorPlanRenderer)**

In `generateReport` (RoomScanView.swift), nach der Foto-Seite eine neue Seite für Feuchtigkeitsmessungen einfügen. Neuer Parameter: `moistureMeasurements: [MoistureMeasurement]?`.

```swift
// Seite 4 (oder 3 wenn keine Fotos): Feuchtigkeitsmessung
if let moisture = moistureMeasurements, !moisture.isEmpty {
    ctx.beginPage()
    let gm = ctx.cgContext
    let headerHm = drawKRAFTHeader(g: gm, pageW: 595, schadensnummer: schadensnummer,
                                   date: date, address: address, roomNames: roomNames,
                                   floorAreaM2: floorAreaM2)
    var my: CGFloat = headerHm + 14

    let sectionAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.systemBlue]
    let boldAttrs:    [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 11), .foregroundColor: UIColor.black]

    ("FEUCHTIGKEITSMESSUNG" as NSString).draw(at: CGPoint(x: 40, y: my), withAttributes: sectionAttrs)
    my += 24

    func mtext(_ s: String, x: CGFloat, color: UIColor = .black) {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: color]
        (s as NSString).draw(at: CGPoint(x: x, y: my), withAttributes: attrs)
    }

    // Wandfläche-Punkte (blau)
    let wand = moisture.filter { $0.kategorie == .wandflaeche }
    if !wand.isEmpty {
        ("Wandfläche" as NSString).draw(at: CGPoint(x: 40, y: my), withAttributes: boldAttrs)
        my += 18
        ("Nr." as NSString).draw(at: CGPoint(x: 40,  y: my), withAttributes: boldAttrs)
        ("Wert" as NSString).draw(at: CGPoint(x: 100, y: my), withAttributes: boldAttrs)
        ("Einheit" as NSString).draw(at: CGPoint(x: 200, y: my), withAttributes: boldAttrs)
        my += 18
        for m in wand {
            mtext("\(m.nummer).", x: 40,  color: .systemBlue)
            mtext(String(format: "%.1f", m.wert), x: 100, color: .systemBlue)
            mtext(m.einheit, x: 200, color: .systemBlue)
            my += 16
        }
        my += 10
    }

    // Dämmschicht-Punkte (rot)
    let daemm = moisture.filter { $0.kategorie == .daemmschicht }
    if !daemm.isEmpty {
        ("Dämmschicht" as NSString).draw(at: CGPoint(x: 40, y: my), withAttributes: boldAttrs)
        my += 18
        ("Nr." as NSString).draw(at: CGPoint(x: 40,  y: my), withAttributes: boldAttrs)
        ("Wert" as NSString).draw(at: CGPoint(x: 100, y: my), withAttributes: boldAttrs)
        ("Einheit" as NSString).draw(at: CGPoint(x: 200, y: my), withAttributes: boldAttrs)
        my += 18
        for m in daemm {
            mtext("\(m.nummer).", x: 40,  color: .systemRed)
            mtext(String(format: "%.1f", m.wert), x: 100, color: .systemRed)
            mtext(m.einheit, x: 200, color: .systemRed)
            my += 16
        }
    }
}
```

`generateReport`-Signatur um `moistureMeasurements: [MoistureMeasurement]?` erweitern. Alle Aufrufer übergeben `moistureMeasurements: record.moistureMeasurements` bzw. `nil` bei erstem Scan.

- [ ] **Schritt 7.7: Build + Test**

`Cmd+B` → Build Succeeded. Im Simulator: Scan öffnen → Section "Feuchtigkeitsmessung" sichtbar, "+ Punkt hinzufügen" öffnet Sheet, Eingabe wird gespeichert, Punkte in blau/rot angezeigt.

---

## Task 8: Abschlusskontrolle

- [ ] **Schritt 8.1: generateReport vollständige Signatur prüfen**

Sicherstellen, dass `generateReport` jetzt folgende Parameter in dieser Reihenfolge hat:
```
wallMeasurements, doorMeasurements, windowMeasurements,
wallGeometry, doorGeometry, windowGeometry,
floorAreaM2, address, roomNames, roomFloorAreas,
schadensnummer, date, roomPhotos, folderURL,
moistureMeasurements, at: URL
```
Alle 3 Aufrufer prüfen: in `saveResults` (RoomScanView), in `saveKopfdaten` (ScanDetailView), und im Background-Task von `saveKopfdaten`.

- [ ] **Schritt 8.2: Finale Build-Prüfung**

`Cmd+B` → Build Succeeded ohne Warnings.

- [ ] **Schritt 8.3: Rückwärtskompatibilität bestätigen**

Alle neuen `ScanRecord`-Felder sind `Optional` (`?`) — alte Scans in `scans.json` dekodieren weiterhin korrekt (fehlende Keys werden als `nil` interpretiert). Kein Datenverlust bei vorhandenen Scans.

- [ ] **Schritt 8.4: Auf echtem Gerät testen**

Da RoomPlan nur auf physischen Geräten mit LiDAR läuft (iPad Pro / iPhone Pro ab 2020), auf Gerät deployen und einen neuen Scan durchführen. Prüfen:
- Fenster sichtbar im Grundriss (blau, oben)
- Raumflächen korrekt angezeigt
- Kamera-Button für Fotos funktioniert
- Feuchtigkeitspunkte speicherbar
- Suche filtert Scans
- PDF enthält alle Seiten (Grundriss, Maßtabelle, ggf. Fotos, ggf. Feuchtigkeit)
