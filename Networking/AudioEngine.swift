@preconcurrency import AVFoundation
import Foundation

#if os(macOS)
import CoreAudio
#endif

// MARK: - Audio Engine Delegate

protocol AudioEngineDelegate: AnyObject, Sendable {
    func audioEngine(_ engine: AudioEngine, didCaptureAudio data: Data) async
    func audioEngineDidStartCapturing(_ engine: AudioEngine) async
    func audioEngineDidStopCapturing(_ engine: AudioEngine) async
}

// MARK: - Audio Engine Errors

enum AudioEngineError: Error, LocalizedError {
    case engineNotRunning
    case configurationFailed(String)
    case permissionDenied
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .engineNotRunning:
            return "Audio engine is not running"
        case .configurationFailed(let message):
            return "Configuration failed: \(message)"
        case .permissionDenied:
            return "Microphone permission denied"
        case .playbackFailed(let message):
            return "Playback failed: \(message)"
        }
    }
}

// MARK: - Audio Level Box (Thread-Safe)

final class AudioLevelBox: @unchecked Sendable {
    private var _value: CGFloat = 0
    private let lock = NSLock()

    var value: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func update(_ newValue: CGFloat) {
        lock.lock()
        defer { lock.unlock() }
        _value = newValue
    }
}

// MARK: - Audio Engine

final class AudioEngine: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let audioQueue = DispatchQueue(label: "com.interviewer.audioengine", qos: .userInteractive)

    private var isCapturing = false
    private var isPlaying = false
    private var audioConverter: AVAudioConverter?
    private var playbackTapInstalled = false

    weak var delegate: AudioEngineDelegate?

    private func log(_ message: String) {
        StructuredLogger.log(component: "AudioEngine", message: message)
    }

    // Audio level for visualization (0.0 to 1.0)
    // Using a thread-safe box for the level
    private let _audioLevel = AudioLevelBox()
    var audioLevel: CGFloat {
        _audioLevel.value
    }

    // Audio format for OpenAI Realtime API: PCM 16-bit, 24kHz, mono
    private let targetSampleRate: Double = 24000
    private let channels: AVAudioChannelCount = 1

    private var targetFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: channels,
            interleaved: false
        )
    }

    private var playbackFormat: AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: channels,
            interleaved: true
        )
    }

    init() {}

    // MARK: - Setup

    func setup() throws {
        #if os(iOS)
        try setupAudioSession()
        #endif

        // Attach player node to engine
        engine.attach(playerNode)

        // Connect player to main mixer
        guard let format = playbackFormat else {
            throw AudioEngineError.configurationFailed("Could not create playback format")
        }
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        // Install tap on main mixer to measure playback audio levels for visualization
        installPlaybackLevelTap()
    }

    private func installPlaybackLevelTap() {
        guard !playbackTapInstalled else { return }

        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)

        mixer.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processPlaybackLevel(buffer: buffer)
        }
        playbackTapInstalled = true
    }

    private func processPlaybackLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Compute RMS (Root Mean Square) for amplitude
        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))

        // Convert to dB and normalize to 0-1 range
        let minRms: Float = 0.000_02  // Avoid log(0)
        let clippedRms = max(minRms, rms)
        let db = 20 * log10(clippedRms)

        // Map from [-50, 0] dB to [0, 1]
        let minDb: Float = -50
        let clampedDb = max(minDb, min(0, db))
        let normalized = (clampedDb - minDb) / -minDb

        // Update the level with slight smoothing via exponential moving average
        let currentLevel = Float(_audioLevel.value)
        let smoothed = currentLevel * 0.3 + normalized * 0.7

        _audioLevel.update(CGFloat(smoothed))
    }

    #if os(iOS)
    private var interruptionObserver: NSObjectProtocol?

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            throw AudioEngineError.configurationFailed(error.localizedDescription)
        }

        // Register for audio interruption notifications (phone calls, Siri, etc.)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Interruption started (e.g., phone call)
            log("Audio session interrupted - pausing capture")
            stopCapturing()
            playerNode.pause()

        case .ended:
            // Interruption ended - check if we should resume
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    log("Audio interruption ended - resuming")
                    do {
                        try AVAudioSession.sharedInstance().setActive(true)
                        if !engine.isRunning {
                            try engine.start()
                        }
                        playerNode.play()
                    } catch {
                        log("Failed to resume after interruption: \(error.localizedDescription)")
                    }
                }
            }

        @unknown default:
            break
        }
    }

    deinit {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    #endif

    // MARK: - Permissions

    func requestMicrophonePermission() async -> Bool {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
        #else
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
        #endif
    }

    // MARK: - Capture

    func startCapturing() async throws {
        guard !isCapturing else { return }

        let hasPermission = await requestMicrophonePermission()
        guard hasPermission else {
            throw AudioEngineError.permissionDenied
        }

        // Log current audio devices
        #if os(macOS)
        if let inputDevice = getCurrentInputDeviceName() {
            log("Using input device: \(inputDevice)")
        }
        if let outputDevice = getCurrentOutputDeviceName() {
            log("Using output device: \(outputDevice)")
        }
        #endif

        let inputNode = engine.inputNode

        // IMPORTANT: Enable Apple's Voice Processing for echo cancellation, noise suppression, and AGC
        // This must be done BEFORE engine.start() and requires both input/output nodes
        // Note: Voice Isolation mode must be enabled by the USER in Control Center/System Settings
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            inputNode.isVoiceProcessingAGCEnabled = true  // Enable automatic gain control
            log("Voice processing enabled (AEC, noise suppression, AGC)")
            log("Tip: Enable 'Voice Isolation' in Control Center for best results")
        } catch {
            log("Could not enable voice processing: \(error.localizedDescription)")
            // Continue without voice processing - will still work but without AEC
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create target format for 24kHz mono (float32 for converter, then convert to int16)
        guard let outputFormat = targetFormat else {
            throw AudioEngineError.configurationFailed("Could not create target format")
        }

        // For converter, use mono input format (we'll extract channel 0 manually if multi-channel)
        let converterInputFormat: AVAudioFormat
        if inputFormat.channelCount > 1 {
            guard let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: 1,
                interleaved: false
            ) else {
                throw AudioEngineError.configurationFailed("Could not create mono input format")
            }
            converterInputFormat = monoFormat
            log("Voice processing active: converting \(inputFormat.channelCount) channels to mono before resampling")
        } else {
            converterInputFormat = inputFormat
        }

        // Create audio converter for resampling (mono to mono at different sample rate)
        guard let converter = AVAudioConverter(from: converterInputFormat, to: outputFormat) else {
            throw AudioEngineError.configurationFailed("Could not create audio converter from \(converterInputFormat.sampleRate)Hz to \(outputFormat.sampleRate)Hz")
        }
        self.audioConverter = converter

        log(String(format: "Input format: %.0fHz, %d channels", inputFormat.sampleRate, inputFormat.channelCount))
        log(String(format: "Output format: %.0fHz, %d channels (24kHz PCM16 for API)", outputFormat.sampleRate, outputFormat.channelCount))

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4800, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let converter = self.audioConverter else { return }

            // If multi-channel (voice processing), extract channel 0 first
            let monoBuffer: AVAudioPCMBuffer
            if buffer.format.channelCount > 1 {
                monoBuffer = self.extractChannel0(from: buffer) ?? buffer
            } else {
                monoBuffer = buffer
            }

            // Resample to 24kHz and convert to PCM16
            guard let audioData = self.resampleAndConvert(monoBuffer, converter: converter, outputFormat: outputFormat),
                  let delegate = self.delegate else { return }

            self.audioQueue.async {
                Task {
                    await delegate.audioEngine(self, didCaptureAudio: audioData)
                }
            }
        }

        do {
            try engine.start()
            isCapturing = true
            if let delegate = delegate {
                audioQueue.async {
                    Task {
                        await delegate.audioEngineDidStartCapturing(self)
                    }
                }
            }
        } catch {
            inputNode.removeTap(onBus: 0)
            audioConverter = nil
            throw AudioEngineError.configurationFailed(error.localizedDescription)
        }
    }

    func stopCapturing() {
        guard isCapturing else { return }

        engine.inputNode.removeTap(onBus: 0)
        // Note: We do NOT call engine.stop() here because that disconnects all nodes
        // including the playerNode, which breaks audio playback on resume.
        // The engine continues running for playback.
        isCapturing = false
        audioConverter = nil

        if let delegate = delegate {
            audioQueue.async {
                Task {
                    await delegate.audioEngineDidStopCapturing(self)
                }
            }
        }
    }

    /// Fully stop the audio engine (call when ending session, not when pausing)
    func shutdown() {
        stopCapturing()
        playerNode.stop()
        engine.stop()
        log("Audio engine fully shut down")
    }

    // MARK: - Playback

    func playAudio(_ data: Data) throws {
        guard let format = playbackFormat else {
            throw AudioEngineError.playbackFailed("Could not create playback format")
        }

        // Ensure engine is running for playback
        if !engine.isRunning {
            try engine.start()
        }

        // Convert data to buffer
        guard let buffer = dataToBuffer(data, format: format) else {
            throw AudioEngineError.playbackFailed("Could not convert data to buffer")
        }

        // Schedule and play
        if !playerNode.isPlaying {
            playerNode.play()
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stopPlayback() {
        playerNode.stop()
        resetAudioLevel()
    }

    func resetAudioLevel() {
        _audioLevel.update(0)
    }

    // MARK: - Audio Conversion

    /// Extract channel 0 from a multi-channel buffer into a mono buffer
    private func extractChannel0(from buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let floatData = buffer.floatChannelData else { return nil }

        // Create mono format at same sample rate
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength) else {
            return nil
        }

        monoBuffer.frameLength = buffer.frameLength

        guard let monoData = monoBuffer.floatChannelData else { return nil }

        // Copy just channel 0
        let frameCount = Int(buffer.frameLength)
        for i in 0..<frameCount {
            monoData[0][i] = floatData[0][i]
        }

        return monoBuffer
    }

    private func resampleAndConvert(_ inputBuffer: AVAudioPCMBuffer, converter: AVAudioConverter, outputFormat: AVAudioFormat) -> Data? {
        // Calculate output frame count based on sample rate ratio
        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)

        guard outputFrameCount > 0 else { return nil }

        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        // Convert/resample
        var error: NSError?
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, error == nil else {
            log("Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        // Convert float32 to int16 for OpenAI API
        return floatBufferToInt16Data(outputBuffer)
    }

    private func floatBufferToInt16Data(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let floatData = buffer.floatChannelData else { return nil }

        let frameLength = Int(buffer.frameLength)
        var int16Data = [Int16](repeating: 0, count: frameLength)

        for i in 0..<frameLength {
            let sample = floatData[0][i]
            let clipped = max(-1.0, min(1.0, sample))
            int16Data[i] = Int16(clipped * Float(Int16.max))
        }

        return Data(bytes: int16Data, count: frameLength * 2)
    }

    private func dataToBuffer(_ data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(data.count / 2)  // 2 bytes per Int16 sample

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.int16ChannelData else {
            return nil
        }

        data.withUnsafeBytes { rawBuffer in
            guard let samples = rawBuffer.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for i in 0..<Int(frameCount) {
                channelData[0][i] = samples[i]
            }
        }

        return buffer
    }

    // MARK: - State

    var capturing: Bool {
        isCapturing
    }

    var playing: Bool {
        playerNode.isPlaying
    }

    // MARK: - Device Info

    #if os(macOS)
    private func getCurrentInputDeviceName() -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else { return nil }

        // Get device name
        propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString
        var nameRef: Unmanaged<CFString>?
        dataSize = UInt32(MemoryLayout<CFString?>.size)

        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &nameRef
        )

        guard status == noErr, let name = nameRef?.takeUnretainedValue() else { return nil }
        return name as String
    }

    private func getCurrentOutputDeviceName() -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioObjectID = 0
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)

        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else { return nil }

        // Get device name
        propertyAddress.mSelector = kAudioDevicePropertyDeviceNameCFString
        var nameRef: Unmanaged<CFString>?
        dataSize = UInt32(MemoryLayout<CFString?>.size)

        status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &nameRef
        )

        guard status == noErr, let name = nameRef?.takeUnretainedValue() else { return nil }
        return name as String
    }
    #endif
}
