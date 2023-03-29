//
//  Utilities.swift
//  CowabungaJailed
//
//  Created by Rory Madden on 20/3/2023.
//

import Foundation

@objc class Logger: NSObject, ObservableObject {
    @objc static let shared = Logger()
    
    @Published var logText = ""

    @objc func logMe(_ message: String) {
        logText += "\(message)\n"
    }
}

enum Tweak: String {
    case footnote = "Footnote"
    case statusBar = "StatusBar"
    case springboardOptions = "SpringboardOptions"
    case skipSetup = "SkipSetup"
    case themes = "AppliedTheme"
    case dynamicIsland = "DynamicIsland"
    case none = "None"
}

@objc class DataSingleton: NSObject, ObservableObject {
    @objc static let shared = DataSingleton()
    private var currentDevice: Device?
    private var currentWorkspace: URL?
    @Published var enabledTweaks: Set<Tweak> = []
    @Published var deviceAvailable = false
    
    func setTweakEnabled(_ tweak: Tweak, isEnabled: Bool) {
        if isEnabled {
            enabledTweaks.insert(tweak)
        } else {
            enabledTweaks.remove(tweak)
        }
    }
    
    func isTweakEnabled(_ tweak: Tweak) -> Bool {
        return enabledTweaks.contains(tweak)
    }
    
    func allEnabledTweaks() -> Set<Tweak> {
        return enabledTweaks
    }
    
    func setCurrentDevice(_ device: Device) {
        currentDevice = device
        if Int(device.version.split(separator: ".")[0])! < 15 {
            deviceAvailable = false
        } else {
            setupWorkspaceForUUID(device.uuid)
            deviceAvailable = true
        }
    }
    
    func resetCurrentDevice() {
        currentDevice = nil
        currentWorkspace = nil
        deviceAvailable = false
        enabledTweaks.removeAll()
    }
    
    @objc func getCurrentUUID() -> String? {
        return currentDevice?.uuid
    }
    
    @objc func getCurrentVersion() -> String? {
        return currentDevice?.version
    }
    
    @objc func getCurrentName() -> String? {
        return currentDevice?.name
    }
    
    func setCurrentWorkspace(_ workspaceURL: URL) {
        currentWorkspace = workspaceURL
    }
    
    @objc func getCurrentWorkspace() -> URL? {
        return currentWorkspace
    }
}

extension FileManager {
    func mergeDirectory(at sourceURL: URL, to destinationURL: URL) throws {
        try createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        let contents = try contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        for item in contents {
            let newItemURL = destinationURL.appendingPathComponent(item.lastPathComponent)
            var isDirectory: ObjCBool = false
            if fileExists(atPath: newItemURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    try mergeDirectory(at: item, to: newItemURL)
                } else {
                    let newFileAttributes = try fm.attributesOfItem(atPath: newItemURL.path)
                    let oldFileAttributes = try fm.attributesOfItem(atPath: item.path)
                    if let newModifiedTime = newFileAttributes[.modificationDate] as? Date,
                       let oldModifiedTime = oldFileAttributes[.modificationDate] as? Date,
                       newModifiedTime.compare(oldModifiedTime) == .orderedAscending {
                            try removeItem(at: newItemURL)
                            try copyItem(at: item, to: newItemURL)
                    }
                }
            } else {
                try copyItem(at: item, to: newItemURL)
            }
        }
    }
}

func setupWorkspaceForUUID(_ UUID: String) {
    let workspaceDirectory = documentsDirectory.appendingPathComponent("Workspace")
    if !fm.fileExists(atPath: workspaceDirectory.path) {
        do {
            try fm.createDirectory(atPath: workspaceDirectory.path, withIntermediateDirectories: false, attributes: nil)
            Logger.shared.logMe("Workspace folder created")
        } catch {
            Logger.shared.logMe("Error creating Workspace folder: \(error.localizedDescription)")
            return
        }
    }
    let UUIDDirectory = workspaceDirectory.appendingPathComponent(UUID)
    if !fm.fileExists(atPath: UUIDDirectory.path) {
        do {
            try fm.createDirectory(atPath: UUIDDirectory.path, withIntermediateDirectories: false, attributes: nil)
            Logger.shared.logMe("UUID folder created")
        } catch {
            Logger.shared.logMe("Error creating UUID folder: \(error.localizedDescription)")
            return
        }
    }
    DataSingleton.shared.setCurrentWorkspace(UUIDDirectory)
    guard let docsFolderURL = Bundle.main.url(forResource: "Files", withExtension: nil) else {
        Logger.shared.logMe("Can't find Bundle URL?")
        return
    }
    do {
        let files = try fm.contentsOfDirectory(at: docsFolderURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        for file in files {
            let newURL = UUIDDirectory.appendingPathComponent(file.lastPathComponent)
            var shouldMergeDirectory = false
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: newURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    shouldMergeDirectory = true
                } else {
                    Logger.shared.logMe(newURL.path)
                    let newFileAttributes = try fm.attributesOfItem(atPath: newURL.path)
                    let oldFileAttributes = try fm.attributesOfItem(atPath: file.path)
                    if let newModifiedTime = newFileAttributes[.modificationDate] as? Date,
                       let oldModifiedTime = oldFileAttributes[.modificationDate] as? Date,
                       newModifiedTime.compare(oldModifiedTime) != .orderedAscending {
                        continue // skip copying the file since the new file is older
                    }
                }
            }
            if shouldMergeDirectory {
                try fm.mergeDirectory(at: file, to: newURL)
            } else {
                try fm.copyItem(at: file, to: newURL)
            }
        }
    } catch {
        Logger.shared.logMe(error.localizedDescription)
        return
    }
}

func shell(_ scriptURL: URL, arguments: [String] = [], workingDirectory: URL? = nil) throws {
    let task = Process()
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    let scriptArguments = arguments.joined(separator: " ")
    task.arguments = ["-c", "source \(scriptURL.path) \(scriptArguments)"]
    if let workingDirectory = workingDirectory {
        task.currentDirectoryURL = workingDirectory
    }
    
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8) {
        Logger.shared.logMe(output)
    }
}

func execute(_ execURL: URL, arguments: [String] = [], workingDirectory: URL? = nil) throws {
    let task = Process()
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    
    let bundlePath = Bundle.main.bundlePath
    let frameworksPath = (bundlePath as NSString).appendingPathComponent("Contents/Frameworks")
    let environment = ["DYLD_LIBRARY_PATH": frameworksPath]
    task.environment = environment

    task.executableURL = execURL
    task.arguments = arguments
    if let workingDirectory = workingDirectory {
        task.currentDirectoryURL = workingDirectory
    }
    
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8) {
        Logger.shared.logMe(output)
    }
}

func execute2(_ execURL: URL, arguments: [String] = [], workingDirectory: URL? = nil) throws -> String {
    let task = Process()
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    
    let bundlePath = Bundle.main.bundlePath
    let frameworksPath = (bundlePath as NSString).appendingPathComponent("Contents/Frameworks")
    let environment = ["DYLD_LIBRARY_PATH": frameworksPath]
    task.environment = environment

    task.executableURL = execURL
    task.arguments = arguments
    if let workingDirectory = workingDirectory {
        task.currentDirectoryURL = workingDirectory
    }
    
    try task.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    if let output = String(data: data, encoding: .utf8) {
        return output
    }
    return ""
}

func printDirectoryTree(at path: URL, level: Int) {
    let prefix = String(repeating: "│   ", count: level > 0 ? level - 1 : 0) + (level > 0 ? "├── " : "")
    
    do {
        let contents = try fm.contentsOfDirectory(at: path, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        for url in contents {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            Logger.shared.logMe(prefix + url.lastPathComponent)
            if isDirectory {
                printDirectoryTree(at: url, level: level + 1)
            }
        }
    } catch {
        Logger.shared.logMe(error.localizedDescription)
    }
}

func applyTweaks() async {
    // Erase backup folder
    let enabledTweaksDirectory = documentsDirectory.appendingPathComponent("EnabledTweaks")
    if fm.fileExists(atPath: enabledTweaksDirectory.path) {
        do {
            let fileURLs = try fm.contentsOfDirectory(at: enabledTweaksDirectory, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            Logger.shared.logMe("Error removing contents of EnabledTweaks directory")
            return
        }
    } else {
        do {
            try fm.createDirectory(at: enabledTweaksDirectory, withIntermediateDirectories: false)
        } catch {
            Logger.shared.logMe("Error creating EnabledTweaks directory")
            return
        }
    }
    
    // Copy tweaks across
    guard let workspaceURL = DataSingleton.shared.getCurrentWorkspace() else {
        Logger.shared.logMe("Error getting Workspace URL")
        return
    }

    for tweak in DataSingleton.shared.allEnabledTweaks() {
        do {
            let files = try fm.contentsOfDirectory(at: workspaceURL.appendingPathComponent("\(tweak.rawValue)"), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for file in files {
                let newURL = enabledTweaksDirectory.appendingPathComponent(file.lastPathComponent)
                var shouldMergeDirectory = false
                var isDirectory: ObjCBool = false
                if fm.fileExists(atPath: newURL.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        shouldMergeDirectory = true
                    } else {
                        let newFileAttributes = try fm.attributesOfItem(atPath: newURL.path)
                        let oldFileAttributes = try fm.attributesOfItem(atPath: file.path)
                        if let newModifiedTime = newFileAttributes[.modificationDate] as? Date,
                           let oldModifiedTime = oldFileAttributes[.modificationDate] as? Date,
                           newModifiedTime.compare(oldModifiedTime) != .orderedAscending {
                            continue // skip copying the file since the new file is older
                        }
                    }
                }
                if shouldMergeDirectory {
                    try fm.mergeDirectory(at: file, to: newURL)
                } else {
                    try fm.copyItem(at: file, to: newURL)
                }
            }
        } catch {
            Logger.shared.logMe(error.localizedDescription)
            return
        }
    }

    
    let backupDirectory = documentsDirectory.appendingPathComponent("Backup")
    if fm.fileExists(atPath: backupDirectory.path) {
        do {
            let fileURLs = try fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            Logger.shared.logMe("Error removing contents of Backup directory")
            return
        }
    } else {
        do {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: false)
        } catch {
            Logger.shared.logMe("Error creating Backup directory")
            return
        }
    }
    
    // Generate backup
    await generateBackup()
    
    // Restore files
    guard let exec = Bundle.main.url(forResource: "idevicebackup2", withExtension: "") else {
        Logger.shared.logMe("Error locating idevicebackup2")
        return
    }
    guard let currentUUID = DataSingleton.shared.getCurrentUUID() else {
        Logger.shared.logMe("Error getting current UUID")
        return
    }
    do {
        try execute(exec, arguments:["-u", currentUUID, "-s", "Backup", "restore", "--system", "--skip-apps", "."], workingDirectory: documentsDirectory)
    } catch {
        Logger.shared.logMe("Error restoring to device")
    }
}

struct Device {
    let uuid: String
    let name: String
    let version: String
}

func getDevices() -> [Device] {
    guard let exec = Bundle.main.url(forResource: "idevice_id", withExtension: "") else { return [] }
    do {
        let devices = try execute2(exec, arguments:["-l"], workingDirectory: documentsDirectory) // array of UUIDs
        if devices.contains("ERROR") {
            return []
        }
        let devicesArr = devices.split(separator: "\n", omittingEmptySubsequences: true)
        
        var deviceStructs: [Device] = []
        for d in devicesArr {
            guard let exec2 = Bundle.main.url(forResource: "idevicename", withExtension: "") else { continue }
            let deviceName = try execute2(exec2, arguments:["-u", String(d)], workingDirectory: documentsDirectory).replacingOccurrences(of: "\n", with: "")
            guard let exec3 = Bundle.main.url(forResource: "ideviceinfo", withExtension: "") else { continue }
            let deviceVersion = try execute2(exec3, arguments:["-u", String(d), "-k", "ProductVersion"], workingDirectory: documentsDirectory).replacingOccurrences(of: "\n", with: "")
            let device = Device(uuid: String(d), name: deviceName, version: deviceVersion)
            deviceStructs.append(device)
        }
        return deviceStructs
    } catch {
        return []
    }
}

func getHomeScreenApps() -> [String:String] {
    guard let exec = Bundle.main.url(forResource: "homeScreenApps", withExtension: "") else {
        Logger.shared.logMe("Error locating homeScreenApps")
        return [:]
    }
    guard let currentUUID = DataSingleton.shared.getCurrentUUID() else {
        Logger.shared.logMe("Error getting current UUID")
        return [:]
    }
    do {
        let appsCSV = try execute2(exec, arguments:["-u", currentUUID], workingDirectory: documentsDirectory)
        var dict = [String:String]()
        for line in appsCSV.split(separator: "\n") {
            let components = line.split(separator: ",")
            // todo proper error check here
            dict[String(components[0])] = String(components[1])
        }
        Logger.shared.logMe("\(dict)")
        return dict
    } catch {
        Logger.shared.logMe("Error processing apps csv")
        return [:]
    }
}

func getHomeScreenNumPages() -> Int {
    guard let exec = Bundle.main.url(forResource: "homeScreenApps", withExtension: "") else {
        Logger.shared.logMe("Error locating homeScreenApps")
        return 1
    }
    guard let currentUUID = DataSingleton.shared.getCurrentUUID() else {
        Logger.shared.logMe("Error getting current UUID")
        return 1
    }
    do {
        var pagesStr = try execute2(exec, arguments:["-u", currentUUID, "-n"], workingDirectory: documentsDirectory)
        pagesStr = pagesStr.replacingOccurrences(of: "\n", with: "")
        let pages = Int(pagesStr) ?? 1
        return pages
    } catch {
        Logger.shared.logMe("Error processing apps csv")
        return 1
    }
}

