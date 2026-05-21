//
//  ScanStore.swift
//  InnoviScan
//

import Foundation
import Combine
import SwiftUI

// MARK: - Messungs-Strukturen

struct WallMeasurement: Codable {
    let width: Double       // Breite in Metern (dimensions.x)
    let height: Double      // Höhe in Metern  (dimensions.y)
    let confidence: String  // "hoch", "mittel", "niedrig"
}

struct SurfaceMeasurement: Codable {
    let width: Double
    let height: Double
}

struct ScanAddress: Codable {
    var street: String = ""   // Straße + Hausnummer
    var zip:    String = ""   // PLZ
    var city:   String = ""   // Ort
    var etage:  String = ""   // Etage

    var cityLine: String { "\(zip) \(city)".trimmingCharacters(in: .whitespaces) }

    var oneLiner: String {
        [street, cityLine, etage]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// 2D-Geometrie einer Wand in der XZ-Ebene (Draufsicht).
/// Koordinaten in Metern, RoomPlan-Weltkoordinatensystem.
/// Umrechnung: Y-Achse (Höhe) wird ignoriert; X und Z bilden den Grundriss.
/// Richtungsvektor (dirX, dirZ) ist der normierte columns.0-Vektor der Transform-Matrix.
struct WallGeometry2D: Codable {
    let cx: Double      // Mittelpunkt X (Meter)
    let cz: Double      // Mittelpunkt Z (Meter)
    let dirX: Double    // Normierter Richtungsvektor entlang der Wand, X-Komponente
    let dirZ: Double    // Normierter Richtungsvektor entlang der Wand, Z-Komponente
    let width: Double   // Wandlänge in Metern
}

/// 2D-Geometrie einer Öffnung (Tür oder Fenster) in der XZ-Ebene.
struct OpeningGeometry2D: Codable {
    let cx: Double
    let cz: Double
    let dirX: Double
    let dirZ: Double
    let width: Double
}

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

// MARK: - Datenmodell

struct ScanRecord: Codable, Identifiable {
    let id: UUID
    let schadensnummer: String
    let date: Date
    /// Relativ zu Documents/ — absoluter Pfad ändert sich bei iOS-Updates.
    let relativeFolderPath: String
    let wallCount: Int
    let doorCount: Int
    let windowCount: Int
    let objectCount: Int
    let floorAreaM2: Double
    /// Neue Felder (nil bei alten Scans ohne Maßdaten)
    let wallMeasurements: [WallMeasurement]?
    let doorMeasurements: [SurfaceMeasurement]?
    let windowMeasurements: [SurfaceMeasurement]?
    /// Grundriss-Geometrie (nil bei älteren Scans ohne Positionsdaten)
    let wallGeometry: [WallGeometry2D]?
    let doorGeometry: [OpeningGeometry2D]?
    let windowGeometry: [OpeningGeometry2D]?
    /// Kopfdaten (nil bei älteren Scans)
    let address:   ScanAddress?
    let roomNames: [String]?
    /// Bodenfläche pro Raum, parallel zu roomNames (nil bei älteren Scans)
    let roomFloorAreas: [Double]?
    /// Fotos pro Raum: Raumname → Array von Dateinamen (relativ zum folderURL)
    let roomPhotos: [String: [String]]?
    /// Feuchtigkeitsmessungen
    let moistureMeasurements: [MoistureMeasurement]?

    // Raumhöhe = größte gemessene Wandhöhe (abgeleitet, nicht gespeichert)
    var roomHeightM: Double? { wallMeasurements?.map(\.height).max() }

    // Bequemer Anzeigename (erster Raum oder nil)
    var primaryRoomName: String? { roomNames?.first(where: { !$0.isEmpty }) }

    var folderURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(relativeFolderPath)
    }
    var usdzURL: URL { folderURL.appendingPathComponent("scan.usdz") }
    var pdfURL:  URL { folderURL.appendingPathComponent("bericht.pdf") }
}

// MARK: - Store (Singleton, ObservableObject)

final class ScanStore: ObservableObject {
    static let shared = ScanStore()

    @Published private(set) var records: [ScanRecord] = []

    private let storeURL: URL = {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scans.json")
    }()

    private init() { load() }

    func add(_ record: ScanRecord) {
        records.insert(record, at: 0)
        save()
    }

    func update(_ record: ScanRecord) {
        guard let idx = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[idx] = record
        save()
    }

    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data  = try? Data(contentsOf: storeURL),
              let saved = try? decoder.decode([ScanRecord].self, from: data)
        else { return }
        records = saved
    }
}
