//
//  ISODropView.swift
//  Whisky
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import WhiskyKit

struct ISODropView: View {
    var isoURL: URL
    var bottles: [Bottle]
    var currentBottle: URL?

    @State private var selection: URL = URL(filePath: "")
    @State private var isMounting: Bool = false
    @State private var mountedVolume: URL?
    @State private var setupExecutables: [URL] = []
    @State private var selectedExecutable: URL?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header with ISO info
                VStack(spacing: 12) {
                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.purple.gradient)
                    Text(isoURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                }
                .padding(.vertical, 20)

                Form {
                    // Bottle selection
                    Section {
                        Picker("iso.selectLibrary", selection: $selection) {
                            ForEach(bottles, id: \.self) {
                                Text($0.settings.name)
                                    .tag($0.url)
                            }
                        }
                    }

                    // Setup executable selection (after mounting)
                    if !setupExecutables.isEmpty {
                        Section("iso.selectSetup") {
                            Picker("iso.executable", selection: $selectedExecutable) {
                                ForEach(setupExecutables, id: \.self) { exe in
                                    HStack {
                                        Image(systemName: "app.fill")
                                            .foregroundStyle(.purple)
                                        Text(exe.lastPathComponent)
                                    }
                                    .tag(exe as URL?)
                                }
                            }
                            .pickerStyle(.radioGroup)
                        }
                    }

                    // Status section
                    if isMounting {
                        Section {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("iso.mounting")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let error = errorMessage {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .formStyle(.grouped)
            }
            .frame(width: ViewWidth.medium, height: 400)
            .navigationTitle("iso.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("create.cancel") {
                        unmountAndDismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .primaryAction) {
                    if setupExecutables.isEmpty {
                        Button("iso.mountAndScan") {
                            mountISO()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isMounting || bottles.isEmpty)
                    } else {
                        Button("iso.install") {
                            runSelectedSetup()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(selectedExecutable == nil)
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                }
            }
        }
        .onAppear {
            if bottles.count <= 0 {
                dismiss()
                return
            }
            selection = bottles.first(where: { $0.url == currentBottle })?.url ?? bottles[0].url
        }
    }

    private func mountISO() {
        isMounting = true
        errorMessage = nil

        Task {
            do {
                // Mount the ISO using hdiutil
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                process.arguments = ["attach", isoURL.path, "-nobrowse", "-readonly"]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    // Parse mounted volume path from output
                    // Output format: /dev/disk4s1   Apple_HFS   /Volumes/GAME_NAME
                    let lines = output.components(separatedBy: "\n")
                    for line in lines where line.contains("/Volumes/") {
                        if let volumeRange = line.range(of: "/Volumes/") {
                            let volumePath = String(line[volumeRange.lowerBound...])
                                .trimmingCharacters(in: .whitespaces)
                            let volumeURL = URL(fileURLWithPath: volumePath)
                            await MainActor.run {
                                mountedVolume = volumeURL
                                scanForSetupFiles(in: volumeURL)
                                isMounting = false
                            }
                            return
                        }
                    }
                    await MainActor.run {
                        errorMessage = "iso.error.noVolume"
                        isMounting = false
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "iso.error.mountFailed"
                        isMounting = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isMounting = false
                }
            }
        }
    }

    private func scanForSetupFiles(in volumeURL: URL) {
        var executables: [URL] = []

        // Common setup file patterns for games
        let setupPatterns = ["setup", "install", "autorun", "launcher", "start", "play", "game"]

        let fileManager = FileManager.default

        // Check root directory first
        if let contents = try? fileManager.contentsOfDirectory(at: volumeURL, includingPropertiesForKeys: nil) {
            for file in contents {
                let ext = file.pathExtension.lowercased()
                let name = file.deletingPathExtension().lastPathComponent.lowercased()

                if ext == "exe" || ext == "msi" {
                    // Prioritize setup files
                    let isSetupFile = setupPatterns.contains { name.contains($0) }
                    if isSetupFile {
                        executables.insert(file, at: 0)
                    } else {
                        executables.append(file)
                    }
                }
            }
        }

        // Check common subdirectories
        let subDirs = ["", "Setup", "Install", "Bin", "Game"]
        for subDir in subDirs {
            let searchURL = subDir.isEmpty ? volumeURL : volumeURL.appendingPathComponent(subDir)
            if let contents = try? fileManager.contentsOfDirectory(at: searchURL, includingPropertiesForKeys: nil) {
                for file in contents {
                    let ext = file.pathExtension.lowercased()
                    if (ext == "exe" || ext == "msi") && !executables.contains(file) {
                        executables.append(file)
                    }
                }
            }
        }

        setupExecutables = executables
        selectedExecutable = executables.first
    }

    private func runSelectedSetup() {
        guard let executable = selectedExecutable,
              let bottle = bottles.first(where: { $0.url == selection }) else {
            return
        }

        Task.detached(priority: .userInitiated) {
            do {
                if executable.pathExtension.lowercased() == "msi" {
                    try await Wine.runWine(["msiexec", "/i", executable.path], bottle: bottle)
                } else {
                    try await Wine.runProgram(at: executable, bottle: bottle)
                }
            } catch {
                print("Failed to run setup: \(error)")
            }
        }

        dismiss()
    }

    private func unmountAndDismiss() {
        if let volume = mountedVolume {
            Task {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                process.arguments = ["detach", volume.path, "-force"]
                try? process.run()
                process.waitUntilExit()
            }
        }
        dismiss()
    }
}
