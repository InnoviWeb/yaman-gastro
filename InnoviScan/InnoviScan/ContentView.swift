//
//  ContentView.swift
//  InnoviScan
//
//  Created by Talha Öztürk on 16.05.26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var store = ScanStore.shared
    @State private var schadensnummer: String = ""
    @State private var showScan = false
    @State private var scanMessage: String? = nil
    @State private var searchText: String = ""

    private var filteredRecords: [ScanRecord] {
        if searchText.isEmpty { return store.records }
        return store.records.filter {
            $0.schadensnummer.localizedCaseInsensitiveContains(searchText)
        }
    }

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    var body: some View {
        NavigationStack {
            List {

                // MARK: Neuer Scan
                Section {
                    TextField("Schadensnummer *", text: $schadensnummer)
                        .keyboardType(.numberPad)

                    Button {
                        scanMessage = nil
                        showScan = true
                    } label: {
                        Text("Raum scannen")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(schadensnummer.isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(10)
                    }
                    .disabled(schadensnummer.isEmpty)

                    if let message = scanMessage {
                        Text(message)
                            .foregroundColor(message.contains("Fehler") ? .red : .green)
                            .font(.subheadline)
                    }
                }

                // MARK: Meine Scans
                Section {
                    if store.records.isEmpty {
                        Text("Noch keine Scans vorhanden.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else if filteredRecords.isEmpty {
                        Text("Keine Ergebnisse für „\(searchText)".")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
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
                            guard searchText.isEmpty else { return }
                            store.delete(at: offsets)
                        }
                    }
                } header: {
                    Text("Meine Scans")
                }
            }
            .navigationTitle("InnoviScan")
            .toolbar {
                if !store.records.isEmpty {
                    EditButton()
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Schadensnummer suchen"
            )
            .fullScreenCover(isPresented: $showScan) {
                RoomScanView(
                    schadensnummer: schadensnummer,
                    isPresented: $showScan
                ) { success in
                    scanMessage = success ? "Scan gespeichert ✓" : "Fehler beim Speichern."
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
