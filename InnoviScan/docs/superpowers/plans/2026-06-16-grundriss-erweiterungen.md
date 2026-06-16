# Grundriss-Erweiterungen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four visual/UX enhancements to InnoviScan: object footprints in floor plan, exterior walls thicker, dimension arrows, and editable wall measurements post-scan.

**Architecture:** All four features are layered into the existing `FloorPlanRenderer.drawFloorPlan` function and `ScanStore` data model. New optional fields on `ScanRecord` (backward-compatible JSON) carry object geometry and manual wall overrides. `ScanDetailView` gains an edit section that writes overrides and re-renders preview + PDF on save.

**Tech Stack:** Swift, SwiftUI, UIKit Core Graphics, RoomPlan (`CapturedStructure.objects`, `CapturedRoom.Object.Category`), existing `FloorPlanRenderer` (RoomScanView.swift)

---

## File Map

| File | Change |
|------|--------|
| `InnoviScan/InnoviScan/ScanStore.swift` | Add `ObjectGeometry2D` struct; add `objectGeometry` and `manualWallMeasurements` to `ScanRecord` |
| `InnoviScan/InnoviScan/RoomScanView.swift` | Extract object geometry in `saveResults`/`saveFallback`; thread `objectGeometry` through all `FloorPlanRenderer` calls; update `drawFloorPlan` for all 3 visual features; update all `ScanRecord` init sites |
| `InnoviScan/InnoviScan/ScanDetailView.swift` | Add `@State var manualWallWidths`, edit section UI, `effectiveWallMeasurements()`, `effectiveWallGeometry()` helpers, update `saveKopfdaten` + `savePhoto` + `saveMoistureMeasurement` to pass new fields |

---

### Task 1: Add ObjectGeometry2D + new ScanRecord fields

**Files:**
- Modify: `InnoviScan/InnoviScan/ScanStore.swift:50-118`

- [ ] **Step 1: Insert ObjectGeometry2D struct after OpeningGeometry2D (line 57)**

Add immediately after line 57 (`}`):

```swift
/// 2D-Geometrie eines erkannten Objekts (Möbel, Sanitär, …) in der XZ-Ebene.
struct ObjectGeometry2D: Codable {
    let cx: Double       // Mittelpunkt X (Meter)
    let cz: Double       // Mittelpunkt Z (Meter)
    let dirX: Double     // Normierter Richtungsvektor, X-Komponente
    let dirZ: Double     // Normierter Richtungsvektor, Z-Komponente
    let width: Double    // Ausdehnung entlang der Hauptachse (dimensions.x)
    let depth: Double    // Ausdehnung quer zur Hauptachse (dimensions.z)
    let label: String    // Deutscher Kurzname z.B. "WC", "Bett"
}
```

- [ ] **Step 2: Add two optional fields to ScanRecord after `moistureMeasurements`**

After line 103 (`let moistureMeasurements: [MoistureMeasurement]?`):

```swift
    /// Erkannte Objekte im Grundriss (nil bei älteren Scans)
    let objectGeometry: [ObjectGeometry2D]?
    /// Manuell korrigierte Wandbreiten (nil = Original-Scan-Daten verwenden)
    let manualWallMeasurements: [WallMeasurement]?
```

- [ ] **Step 3: Build the project — expect zero errors (new optional fields are backward-compatible)**

Open Xcode → Product → Build (⌘B). Expected: BUILD SUCCEEDED (Swift Codable synthesises init from all stored properties, so the existing memberwise init still compiles; however all call sites that construct `ScanRecord` via the memberwise initialiser will now fail because the new fields have no defaults — fix those in Tasks 2 and 3).

Expected build errors after this step: multiple "missing argument" errors in `RoomScanView.swift` and `ScanDetailView.swift`. That is fine — we fix them next.

- [ ] **Step 4: Commit**

```bash
cd /Users/talhaozturk/Desktop/InnoviScan
git add InnoviScan/InnoviScan/ScanStore.swift
git commit -m "feat: add ObjectGeometry2D struct and two optional ScanRecord fields"
```

---

### Task 2: Extract object geometry + update all call sites in RoomScanView.swift

**Files:**
- Modify: `InnoviScan/InnoviScan/RoomScanView.swift`

#### 2a: Add object label helper

- [ ] **Step 1: Add objectLabel helper just before the FloorPlanRenderer struct (after line 560)**

```swift
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
    case .screen:       return "Display"
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
```

#### 2b: Extract objectGeos in saveResults (currently line ~316-318)

- [ ] **Step 2: Add objectGeos extraction after the window geometry extraction in saveResults**

After the line `let windowGeos = structure.windows.map { makeOpeningGeo($0.transform, $0.dimensions.x) }` (line ~318), insert:

```swift
        // Objekte (Möbel, Sanitär, …)
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
```

- [ ] **Step 3: Pass objectGeos to generateReport in saveResults (currently line ~331-348)**

Replace the `FloorPlanRenderer.generateReport(...)` call in `saveResults` with:

```swift
        try FloorPlanRenderer.generateReport(
            wallMeasurements: wallM,
            doorMeasurements: doorM,
            windowMeasurements: windowM,
            wallGeometry: wallGeos,
            doorGeometry: doorGeos,
            windowGeometry: windowGeos,
            objectGeometry: objectGeos,
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
```

- [ ] **Step 4: Pass objectGeos to ScanRecord init in saveResults (currently line ~350-371)**

Replace the `return ScanRecord(...)` in `saveResults` with:

```swift
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
            moistureMeasurements: nil,
            objectGeometry: objectGeos,
            manualWallMeasurements: nil
        )
```

#### 2c: Update saveFallback

- [ ] **Step 5: Add objectGeos extraction in saveFallback (after windowGeos line ~442)**

After `let windowGeos = firstRoom.windows.map { makeOpeningGeo($0.transform, $0.dimensions.x) }`:

```swift
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
```

- [ ] **Step 6: Pass objectGeos to generateReport in saveFallback (currently line ~453-469)**

Replace the `FloorPlanRenderer.generateReport(...)` call in `saveFallback` with:

```swift
        try FloorPlanRenderer.generateReport(
            wallMeasurements: wallM,
            doorMeasurements: doorM,
            windowMeasurements: windowM,
            wallGeometry: wallGeos,
            doorGeometry: doorGeos,
            windowGeometry: windowGeos,
            objectGeometry: objectGeos,
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
```

- [ ] **Step 7: Pass objectGeos to ScanRecord init in saveFallback (currently line ~472-493)**

Replace the `return ScanRecord(...)` in `saveFallback` with:

```swift
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
            moistureMeasurements: nil,
            objectGeometry: objectGeos,
            manualWallMeasurements: nil
        )
```

#### 2d: Update FloorPlanRenderer signatures

- [ ] **Step 8: Add `objectGeometry` parameter to generateReport signature (line ~575)**

In `generateReport`, add after `moistureMeasurements: [MoistureMeasurement]?,` (just before `at url: URL`):

```swift
        objectGeometry: [ObjectGeometry2D] = [],
```

Then inside the function, pass it through to `drawPDFPage`:

Find the `drawPDFPage(context: ctx, walls: wallGeometry, doors: doorGeometry, windows: windowGeometry, ...)` call (line ~620) and add `objects: objectGeometry` to it:

```swift
            drawPDFPage(context: ctx, walls: wallGeometry, doors: doorGeometry, windows: windowGeometry,
                        objects: objectGeometry,
                        schadensnummer: schadensnummer, date: date, floorAreaM2: floorAreaM2,
                        address: address, roomNames: roomNames, roomFloorAreas: roomFloorAreas,
                        pageNum: 1, totalPages: totalPages)
```

- [ ] **Step 9: Add `objects` parameter to drawPDFPage (line ~849)**

In `drawPDFPage` signature, add after `windows: [OpeningGeometry2D],`:

```swift
        objects: [ObjectGeometry2D] = [],
```

Pass it to `drawFloorPlan`:

```swift
        drawFloorPlan(g: g, in: drawRect,
                      walls: walls, doors: doors, windows: windows,
                      objects: objects,
                      floorAreaM2: floorAreaM2, roomNames: roomNames,
                      roomFloorAreas: roomFloorAreas,
                      etage: address?.etage,
                      pageNum: pageNum, totalPages: totalPages)
```

- [ ] **Step 10: Add `objects` parameter to renderPreviewImage (line ~896)**

In `renderPreviewImage` signature, add after `windows: [OpeningGeometry2D],`:

```swift
        objects: [ObjectGeometry2D] = [],
```

Pass it to `drawFloorPlan`:

```swift
            drawFloorPlan(
                g: ctx.cgContext,
                in: CGRect(x: pad, y: pad,
                           width: size.width - 2*pad,
                           height: size.height - 2*pad),
                walls: walls, doors: doors, windows: windows,
                objects: objects,
                floorAreaM2: floorAreaM2, roomNames: roomNames,
                roomFloorAreas: roomFloorAreas
            )
```

- [ ] **Step 11: Add `objects` parameter to drawFloorPlan (line ~924)**

In `drawFloorPlan` signature, add after `windows: [OpeningGeometry2D],`:

```swift
        objects: [ObjectGeometry2D] = [],
```

- [ ] **Step 12: Build — expect BUILD SUCCEEDED**

```bash
# Xcode: ⌘B
```

Expected: zero errors. The `saveFallback`/`saveResults` ScanRecord inits now compile, and all FloorPlanRenderer call sites have default `objects: []`.

- [ ] **Step 13: Commit**

```bash
git add InnoviScan/InnoviScan/RoomScanView.swift
git commit -m "feat: extract object geometry in saveResults/saveFallback, thread objects through FloorPlanRenderer"
```

---

### Task 3: Visual features in drawFloorPlan (objects, thick exterior walls, dimension arrows)

**Files:**
- Modify: `InnoviScan/InnoviScan/RoomScanView.swift` — inside `drawFloorPlan` only

All changes are within the `drawFloorPlan` function body.

#### 3a: Feature 2 — Außenwände dicker

- [ ] **Step 1: Replace the wall drawing block (lines ~994-1006) with exterior-wall detection + variable line width**

Current code:
```swift
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
```

Replace with:

```swift
        // 1. Wände — Außenwände (nahe Bounding-Box-Rand) dicker als Innenwände
        // Heuristik: Wandmittelpunkt innerhalb 0,8 m der Begrenzung → Außenwand
        let exteriorThreshold = 0.8
        g.setLineCap(.square)
        g.setStrokeColor(UIColor.black.cgColor)

        // Zuerst Innenwände (dünn), dann Außenwände (dick) → Außenwände überdecken Kreuzungen
        for pass in 0...1 {
            g.saveGState()
            for wall in walls {
                let isExterior = (wall.cx - minX < exteriorThreshold) ||
                                 (maxX - wall.cx < exteriorThreshold) ||
                                 (wall.cz - minZ < exteriorThreshold) ||
                                 (maxZ - wall.cz < exteriorThreshold)
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
```

#### 3b: Feature 3 — Maßpfeile

- [ ] **Step 2: Replace the dimension label block (lines ~1043-1075) with dimension lines + arrowheads + labels**

Current code (lines 1043-1075):
```swift
        // Maßangaben + Wandnummern entlang der Wände (senkrecht versetzt)
        let dimAttrs: [NSAttributedString.Key: Any] = [...]
        let numAttrs: [NSAttributedString.Key: Any] = [...]
        for (i, wall) in walls.enumerated() {
            ...
        }
```

Replace the entire block with:

```swift
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
            let arrowLen: CGFloat = 8    // Länge des Pfeils
            let arrowBase: CGFloat = 4   // halbe Basisbreite
            let len = sqrt(dir.x * dir.x + dir.y * dir.y)
            guard len > 0.01 else { return }
            let ux = dir.x / len, uy = dir.y / len   // normierter Richtungsvektor
            let px = -uy, py = ux                     // senkrechter Vektor

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

            // Senkrechter Versatz (Maßlinie außen)
            let perpX = CGFloat(-sin(ang)) * 15
            let perpY = CGFloat( cos(ang)) * 15

            // Maßlinie (offset von der Wand)
            let p1off = CGPoint(x: p1.x + perpX, y: p1.y + perpY)
            let p2off = CGPoint(x: p2.x + perpX, y: p2.y + perpY)

            g.saveGState()
            g.setStrokeColor(UIColor(white: 0.45, alpha: 1).cgColor)
            g.setLineWidth(0.7)
            // Maßlinie
            g.move(to: p1off); g.addLine(to: p2off)
            // Hilfslinien von Wandende zur Maßlinie
            g.move(to: p1); g.addLine(to: p1off)
            g.move(to: p2); g.addLine(to: p2off)
            g.strokePath()
            g.restoreGState()

            // Pfeilköpfe an den Enden der Maßlinie
            drawArrowhead(at: p1off, direction: CGPoint(x: p1off.x - p2off.x, y: p1off.y - p2off.y))
            drawArrowhead(at: p2off, direction: CGPoint(x: p2off.x - p1off.x, y: p2off.y - p1off.y))

            // Maßzahl über der Maßlinie
            let label = String(format: "%.2f m", wall.width)
                .replacingOccurrences(of: ".", with: ",")
            let sz = (label as NSString).size(withAttributes: dimAttrs)
            (label as NSString).draw(
                at: CGPoint(x: mid.x + perpX - sz.width/2,
                            y: mid.y + perpY - sz.height/2 - 9),
                withAttributes: dimAttrs
            )

            // Wandnummer auf der Wandinnenseite
            let numLabel = "\(i + 1)"
            let nsz = (numLabel as NSString).size(withAttributes: numAttrs)
            (numLabel as NSString).draw(
                at: CGPoint(x: mid.x - perpX - nsz.width/2,
                            y: mid.y - perpY - nsz.height/2),
                withAttributes: numAttrs
            )
        }
```

#### 3c: Feature 1 — Objekte als gestrichelte Rechtecke

- [ ] **Step 3: Add object drawing block after the window drawing block (after line ~1041)**

Insert after the `// 3. Fenster` block (after `g.restoreGState()` of windows):

```swift
        // 4. Objekte (Möbel, Sanitär) — gestrichelte orange Rechtecke mit Beschriftung
        if !objects.isEmpty {
            let objLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 6.5),
                .foregroundColor: UIColor(red: 0.65, green: 0.35, blue: 0.0, alpha: 1)
            ]
            g.saveGState()
            g.setStrokeColor(UIColor(red: 0.8, green: 0.45, blue: 0.0, alpha: 0.85).cgColor)
            g.setLineWidth(1.2)
            g.setLineDash(phase: 0, lengths: [4, 3])

            for obj in objects {
                // Mittelpunkt und Halbmaße in Canvas-Koordinaten
                let center = cv(obj.cx, obj.cz)

                // Richtungsvektor der langen Achse (canvas)
                // cv() spiegelt X: cv(cx + dx, cz + dz) → canvas.x = ox + (maxX - (cx+dx))*scale = center.x - dx*scale
                let halfW = CGFloat(obj.width / 2) * scale
                let halfD = CGFloat(obj.depth / 2) * scale

                // Lokale Einheitsvektoren in Canvas-Space:
                // Hauptachse (Breite): canvas Richtung = (-dirX, +dirZ) wegen X-Spiegelung in cv()
                let axW = CGPoint(x: -CGFloat(obj.dirX), y: CGFloat(obj.dirZ))
                // Tiefenachse = senkrecht zur Hauptachse
                let axD = CGPoint(x: -axW.y, y: axW.x)

                // Vier Ecken des Rechtecks
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

                // Label zentriert im Objekt
                let lsz = (obj.label as NSString).size(withAttributes: objLabelAttrs)
                (obj.label as NSString).draw(
                    at: CGPoint(x: center.x - lsz.width/2, y: center.y - lsz.height/2),
                    withAttributes: objLabelAttrs
                )
            }
            g.restoreGState()
        }
```

- [ ] **Step 4: Build — expect BUILD SUCCEEDED**

Expected: zero errors.

- [ ] **Step 5: Commit**

```bash
git add InnoviScan/InnoviScan/RoomScanView.swift
git commit -m "feat: objects as dashed rectangles, exterior walls thicker, dimension arrows in floor plan"
```

---

### Task 4: Editable wall measurements in ScanDetailView

**Files:**
- Modify: `InnoviScan/InnoviScan/ScanDetailView.swift`

#### 4a: State + helpers

- [ ] **Step 1: Add @State for manual wall widths and edit-mode toggle (after line ~34)**

After `@State private var showMoistureSheet: Bool = false`:

```swift
    // Manuelle Wandmaße
    @State private var manualWallWidths: [String] = []
    @State private var showWallEditor: Bool = false
```

- [ ] **Step 2: Add two helper functions before `savePhoto` (after line ~376 in the current code structure)**

Insert before `private func savePhoto(...)`:

```swift
    /// Effektive Wandmaße: manuelle Korrekturen überschreiben Original-Scan-Daten
    private func effectiveWallMeasurements() -> [WallMeasurement] {
        guard !manualWallWidths.isEmpty,
              let originals = record.wallMeasurements else {
            return record.wallMeasurements ?? []
        }
        return originals.enumerated().map { i, orig in
            let parsed = i < manualWallWidths.count
                ? Double(manualWallWidths[i].replacingOccurrences(of: ",", with: "."))
                : nil
            let newWidth = parsed.flatMap { $0 > 0 ? $0 : nil } ?? orig.width
            return WallMeasurement(width: newWidth, height: orig.height, confidence: orig.confidence)
        }
    }

    /// Effektive Wandgeometrie: WallGeometry2D.width aus effectiveWallMeasurements() übernehmen
    private func effectiveWallGeometry() -> [WallGeometry2D] {
        guard let geos = record.wallGeometry else { return [] }
        let effM = effectiveWallMeasurements()
        return geos.enumerated().map { i, geo in
            let newWidth = i < effM.count ? effM[i].width : geo.width
            return WallGeometry2D(cx: geo.cx, cz: geo.cz,
                                  dirX: geo.dirX, dirZ: geo.dirZ,
                                  width: newWidth)
        }
    }
```

#### 4b: UI — Wände bearbeiten Section

- [ ] **Step 3: Add "Wände bearbeiten" section in the List body after the Fenster Detailtabelle section (after line ~228)**

After the closing `}` of the "Fenster" section (around line 228):

```swift
            // MARK: Wände bearbeiten (manuelle Korrektur)
            if let walls = record.wallMeasurements, !walls.isEmpty {
                Section {
                    DisclosureGroup("Wandmaße bearbeiten", isExpanded: $showWallEditor) {
                        ForEach(0..<walls.count, id: \.self) { i in
                            HStack {
                                Text("Wand \(i + 1)")
                                    .foregroundColor(.secondary)
                                    .frame(width: 60, alignment: .leading)
                                TextField(
                                    String(format: "%.2f", walls[i].width).replacingOccurrences(of: ".", with: ","),
                                    text: Binding(
                                        get: { i < manualWallWidths.count ? manualWallWidths[i] : "" },
                                        set: { v in
                                            if manualWallWidths.count <= i {
                                                manualWallWidths = walls.map { w in
                                                    String(format: "%.2f", w.width).replacingOccurrences(of: ".", with: ",")
                                                }
                                            }
                                            manualWallWidths[i] = v
                                        }
                                    )
                                )
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                Text("m")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Wandmaße korrigieren")
                } footer: {
                    Text("Geänderte Längen werden im PDF und Grundriss-Vorschau nach 'Speichern & PDF aktualisieren' übernommen.")
                        .font(.caption2)
                }
            }
```

#### 4c: Initialize manualWallWidths in onAppear

- [ ] **Step 4: Load existing manual wall widths in onAppear (after line ~333 where moistureMeasurements are loaded)**

After `moistureMeasurements = record.moistureMeasurements ?? []`:

```swift
            // Manuelle Wandmaße laden (falls vorhanden)
            if let manual = record.manualWallMeasurements {
                manualWallWidths = manual.map { w in
                    String(format: "%.2f", w.width).replacingOccurrences(of: ".", with: ",")
                }
            } else if let orig = record.wallMeasurements {
                manualWallWidths = orig.map { w in
                    String(format: "%.2f", w.width).replacingOccurrences(of: ".", with: ",")
                }
            }
```

Also update the preview render call in onAppear (lines ~336-347) to use effective geometry:

```swift
            // Grundriss-Vorschau mit effektiver Geometrie rendern
            if !record.wallGeometry.isNilOrEmpty {
                let effGeo = effectiveWallGeometry()
                let objGeo = record.objectGeometry ?? []
                DispatchQueue.global(qos: .userInitiated).async {
                    let img = FloorPlanRenderer.renderPreviewImage(
                        walls: effGeo,
                        doors: record.doorGeometry ?? [],
                        windows: record.windowGeometry ?? [],
                        objects: objGeo,
                        floorAreaM2: record.floorAreaM2,
                        roomNames: record.roomNames,
                        roomFloorAreas: record.roomFloorAreas
                    )
                    DispatchQueue.main.async { floorPlanImage = img }
                }
            }
```

Add a small extension at the top of ScanDetailView.swift (below the imports):

```swift
private extension Optional where Wrapped: Collection {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}
```

#### 4d: Update saveKopfdaten to persist manualWallMeasurements + use effective geometry

- [ ] **Step 5: Update saveKopfdaten (lines ~447-499)**

Replace the entire `saveKopfdaten` function with:

```swift
    private func saveKopfdaten() {
        let newAddress = ScanAddress(street: street, zip: zip, city: city, etage: etage)
        let resolvedNames = roomNames.isEmpty ? nil : roomNames

        // Manuelle Wandmaße nur speichern wenn sie vom Original abweichen
        let effM = effectiveWallMeasurements()
        let origM = record.wallMeasurements ?? []
        let hasManualChanges = zip(effM, origM).contains { abs($0.width - $1.width) > 0.001 }
        let manualToSave: [WallMeasurement]? = hasManualChanges ? effM : nil

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
            moistureMeasurements: moistureMeasurements.isEmpty ? record.moistureMeasurements : moistureMeasurements,
            objectGeometry: record.objectGeometry,
            manualWallMeasurements: manualToSave
        )
        ScanStore.shared.update(updated)

        // PDF + Vorschau mit effektiver Geometrie neu generieren
        let effGeo = effectiveWallGeometry()
        let objGeo = record.objectGeometry ?? []
        if !effGeo.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async {
                try? FloorPlanRenderer.generateReport(
                    wallMeasurements: effM,
                    doorMeasurements: updated.doorMeasurements ?? [],
                    windowMeasurements: updated.windowMeasurements ?? [],
                    wallGeometry: effGeo,
                    doorGeometry: updated.doorGeometry ?? [],
                    windowGeometry: updated.windowGeometry ?? [],
                    objectGeometry: objGeo,
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
                let img = FloorPlanRenderer.renderPreviewImage(
                    walls: effGeo,
                    doors: updated.doorGeometry ?? [],
                    windows: updated.windowGeometry ?? [],
                    objects: objGeo,
                    floorAreaM2: updated.floorAreaM2,
                    roomNames: resolvedNames,
                    roomFloorAreas: updated.roomFloorAreas
                )
                DispatchQueue.main.async { floorPlanImage = img }
            }
        }

        saveConfirmation = "Gespeichert ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { saveConfirmation = nil }
    }
```

#### 4e: Update savePhoto + saveMoistureMeasurement to pass new fields

- [ ] **Step 6: Add the two new fields to the ScanRecord init in savePhoto (lines ~395-416)**

Replace the `let updatedRecord = ScanRecord(...)` in `savePhoto` with (add two lines before the closing paren):

```swift
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
            moistureMeasurements: record.moistureMeasurements,
            objectGeometry: record.objectGeometry,
            manualWallMeasurements: record.manualWallMeasurements
        )
```

- [ ] **Step 7: Add the two new fields to the ScanRecord init in saveMoistureMeasurement (lines ~422-443)**

Replace the `let updatedRecord = ScanRecord(...)` in `saveMoistureMeasurement`:

```swift
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
            moistureMeasurements: moistureMeasurements,
            objectGeometry: record.objectGeometry,
            manualWallMeasurements: record.manualWallMeasurements
        )
```

- [ ] **Step 8: Build — expect BUILD SUCCEEDED**

Expected: zero errors.

- [ ] **Step 9: Commit**

```bash
git add InnoviScan/InnoviScan/ScanDetailView.swift
git commit -m "feat: editable wall measurements in ScanDetailView with PDF + preview regeneration"
```

---

### Task 5: Final verification + footer legend update

**Files:**
- Modify: `InnoviScan/InnoviScan/ScanDetailView.swift` — one line in the footer

- [ ] **Step 1: Update the floor plan section footer to mention objects**

Find (line ~92):
```swift
                Text("Schwarz = Wände · Grün = Türen · Blau gestrichelt = Fenster · Seite 1 des PDF-Berichts")
```

Replace with:
```swift
                Text("Schwarz = Wände · Grün = Türen · Blau gestrichelt = Fenster · Orange gestrichelt = Objekte · Seite 1 des PDF-Berichts")
```

- [ ] **Step 2: Build clean**

```bash
# Xcode: Product → Clean Build Folder (⇧⌘K), then ⌘B
```

Expected: BUILD SUCCEEDED, zero warnings about missing ScanRecord fields.

- [ ] **Step 3: Run on device or simulator (iPhone 12 Pro or later for LiDAR)**

Manual test checklist:
- New scan → floor plan preview shows objects as orange dashed rectangles
- Exterior walls visibly thicker than interior walls
- Each wall has a dimension line with arrowheads + measurement label
- ScanDetailView → "Wandmaße korrigieren" → change a value → "Speichern & PDF aktualisieren" → floor plan preview updates with new length
- Open PDF → verify same updated length appears in dimension line on page 1 and in table on page 2
- Old scans (without `objectGeometry`) still open without crash

- [ ] **Step 4: Final commit**

```bash
git add InnoviScan/InnoviScan/ScanDetailView.swift
git commit -m "feat: update floor plan legend to include objects"
```
