import Foundation
import AVFoundation

#if os(macOS)
import CoreAudio
#endif

// MARK: - Audio Device

struct AudioDevice: Identifiable, Hashable {
    let id: String  // Device UID (persistent across reboots)
    let name: String
    let isInput: Bool
    let isOutput: Bool

    #if os(macOS)
    let audioObjectID: AudioObjectID
    #endif
}

// MARK: - Audio Device Manager

@MainActor
@Observable
final class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    var inputDevices: [AudioDevice] = []
    var outputDevices: [AudioDevice] = []

    private func log(_ message: String) {
        StructuredLogger.log(component: "AudioDeviceManager", message: message)
    }

    var selectedInputDeviceID: String? {
        didSet {
            if let id = selectedInputDeviceID {
                UserDefaults.standard.set(id, forKey: "selectedInputDeviceID")
                log("Selected input device: \(id)")
                #if os(macOS)
                setInputDevice(uid: id)
                #endif
            }
        }
    }

    var selectedOutputDeviceID: String? {
        didSet {
            if let id = selectedOutputDeviceID {
                UserDefaults.standard.set(id, forKey: "selectedOutputDeviceID")
                log("Selected output device: \(id)")
                #if os(macOS)
                setOutputDevice(uid: id)
                #endif
            }
        }
    }

    var selectedInputDevice: AudioDevice? {
        inputDevices.first { $0.id == selectedInputDeviceID }
    }

    var selectedOutputDevice: AudioDevice? {
        outputDevices.first { $0.id == selectedOutputDeviceID }
    }

    private init() {
        // Enumerate devices FIRST (before loading preferences)
        refreshDevices()

        // Now load saved preferences (didSet will find devices in the list)
        selectedInputDeviceID = UserDefaults.standard.string(forKey: "selectedInputDeviceID")
        selectedOutputDeviceID = UserDefaults.standard.string(forKey: "selectedOutputDeviceID")

        #if os(macOS)
        // Listen for device changes
        setupDeviceChangeListener()
        #endif
    }

    func refreshDevices() {
        #if os(macOS)
        enumerateMacOSDevices()
        #else
        enumerateiOSDevices()
        #endif
    }

    // MARK: - macOS Device Enumeration

    #if os(macOS)
    private func enumerateMacOSDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            log("Failed to get devices size: \(status)")
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            log("Failed to get devices: \(status)")
            return
        }

        var inputs: [AudioDevice] = []
        var outputs: [AudioDevice] = []

        for deviceID in deviceIDs {
            guard let device = getDeviceInfo(deviceID: deviceID) else { continue }

            if device.isInput {
                inputs.append(device)
            }
            if device.isOutput {
                outputs.append(device)
            }
        }

        inputDevices = inputs
        outputDevices = outputs

        log("Found \(inputs.count) input devices, \(outputs.count) output devices")

        // If no device selected but we have devices, select the default
        if selectedInputDeviceID == nil, let defaultInput = getDefaultInputDevice() {
            selectedInputDeviceID = defaultInput.id
        }
        if selectedOutputDeviceID == nil, let defaultOutput = getDefaultOutputDevice() {
            selectedOutputDeviceID = defaultOutput.id
        }
    }

    private func getDeviceInfo(deviceID: AudioObjectID) -> AudioDevice? {
        // Get device name
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var nameRef: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        var status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &nameRef
        )

        guard status == noErr, let name = nameRef?.takeUnretainedValue() else { return nil }

        // Get device UID
        propertyAddress.mSelector = kAudioDevicePropertyDeviceUID
        var uidRef: Unmanaged<CFString>?
        dataSize = UInt32(MemoryLayout<CFString?>.size)

        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uidRef
        )

        guard status == noErr, let uid = uidRef?.takeUnretainedValue() else { return nil }

        // Check if device has input channels
        let hasInput = hasStreams(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput)

        // Check if device has output channels
        let hasOutput = hasStreams(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput)

        // Skip devices with no channels
        guard hasInput || hasOutput else { return nil }

        return AudioDevice(
            id: uid as String,
            name: name as String,
            isInput: hasInput,
            isOutput: hasOutput,
            audioObjectID: deviceID
        )
    }

    private func hasStreams(deviceID: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }

    private func getDefaultInputDevice() -> AudioDevice? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else { return nil }
        return getDeviceInfo(deviceID: deviceID)
    }

    private func getDefaultOutputDevice() -> AudioDevice? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else { return nil }
        return getDeviceInfo(deviceID: deviceID)
    }

    private func setInputDevice(uid: String) {
        guard let device = inputDevices.first(where: { $0.id == uid }) else {
            log("Input device not found: \(uid)")
            return
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = device.audioObjectID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &deviceID
        )

        if status == noErr {
            log("Set default input device to: \(device.name)")
        } else {
            log("Failed to set input device: \(status)")
        }
    }

    private func setOutputDevice(uid: String) {
        guard let device = outputDevices.first(where: { $0.id == uid }) else {
            log("Output device not found: \(uid)")
            return
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = device.audioObjectID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &deviceID
        )

        if status == noErr {
            log("Set default output device to: \(device.name)")
        } else {
            log("Failed to set output device: \(status)")
        }
    }

    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in
                self?.refreshDevices()
            }
        }

        if status != noErr {
            log("Failed to add device change listener: \(status)")
        }
    }
    #endif

    // MARK: - iOS Device Enumeration

    #if os(iOS)
    private func enumerateiOSDevices() {
        // On iOS, we have limited control over audio routing
        // AVAudioSession handles device selection through routes
        let session = AVAudioSession.sharedInstance()

        var inputs: [AudioDevice] = []
        var outputs: [AudioDevice] = []

        // Get available inputs
        if let availableInputs = session.availableInputs {
            for input in availableInputs {
                let device = AudioDevice(
                    id: input.uid,
                    name: input.portName,
                    isInput: true,
                    isOutput: false
                )
                inputs.append(device)
            }
        }

        // Get current output route
        let currentRoute = session.currentRoute
        for output in currentRoute.outputs {
            let device = AudioDevice(
                id: output.uid,
                name: output.portName,
                isInput: false,
                isOutput: true
            )
            outputs.append(device)
        }

        inputDevices = inputs
        outputDevices = outputs

        log("iOS: Found \(inputs.count) input devices, \(outputs.count) output devices")
    }
    #endif
}
