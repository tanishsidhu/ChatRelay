import Foundation
import HandoffCore

private struct DoctorReport: Codable {
    let installedApps: [InstalledChatApp]
    let helperInstalled: Bool
    let helperRuntime: RuntimeStatus?
    let configuredVaultPath: String
    let vaultExists: Bool
    let handoffDirectoryExists: Bool
    let handoffFileExists: Bool
}

private func printUsage() {
    print("""
    Usage:
      chatrelayctl doctor
      chatrelayctl configure --vault /path/to/ObsidianVault
    """)
}

private let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "configure" {
    guard let vaultFlag = arguments.firstIndex(of: "--vault"),
          arguments.indices.contains(vaultFlag + 1)
    else {
        printUsage()
        exit(EXIT_FAILURE)
    }

    let vaultURL = URL(
        fileURLWithPath: arguments[vaultFlag + 1],
        isDirectory: true
    ).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: vaultURL.path, isDirectory: &isDirectory),
          isDirectory.boolValue
    else {
        FileHandle.standardError.write(Data("Vault directory does not exist.\n".utf8))
        exit(EXIT_FAILURE)
    }

    do {
        try ChatRelayConfiguration(vaultPath: vaultURL.path).save()
        print("Configured ChatRelay vault: \(vaultURL.path)")
        exit(EXIT_SUCCESS)
    } catch {
        FileHandle.standardError.write(Data("Configuration failed: \(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

guard arguments.isEmpty || arguments.first == "doctor" else {
    printUsage()
    exit(EXIT_FAILURE)
}

let configuration = ChatRelayConfiguration.load()
let handoffDirectory = configuration.handoffFileURL.deletingLastPathComponent()
let applicationLocations = [
    "/Applications/ChatRelay.app",
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications/ChatRelay.app")
        .path,
]

private let report = DoctorReport(
    installedApps: InstalledAppDiscovery.discover(),
    helperInstalled: applicationLocations.contains {
        FileManager.default.fileExists(atPath: $0)
    },
    helperRuntime: RuntimeStatus.load(),
    configuredVaultPath: configuration.vaultPath,
    vaultExists: FileManager.default.fileExists(atPath: configuration.vaultURL.path),
    handoffDirectoryExists: FileManager.default.fileExists(atPath: handoffDirectory.path),
    handoffFileExists: FileManager.default.fileExists(atPath: configuration.handoffFileURL.path)
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

do {
    let data = try encoder.encode(report)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    FileHandle.standardError.write(Data("Doctor failed: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
