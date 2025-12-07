import Foundation

/// Downloads audio from YouTube videos using yt-dlp and ffmpeg
actor YouTubeDownloader {

    // MARK: - Error Types

    enum DownloadError: LocalizedError {
        case ytDlpNotFound
        case ffmpegNotFound
        case invalidURL
        case downloadFailed(String)
        case audioExtractionFailed(String)
        case processError(String)

        var errorDescription: String? {
            switch self {
            case .ytDlpNotFound:
                return "yt-dlp not found. Install with: brew install yt-dlp"
            case .ffmpegNotFound:
                return "ffmpeg not found. Install with: brew install ffmpeg"
            case .invalidURL:
                return "Invalid YouTube URL"
            case .downloadFailed(let message):
                return "Download failed: \(message)"
            case .audioExtractionFailed(let message):
                return "Audio extraction failed: \(message)"
            case .processError(let message):
                return "Process error: \(message)"
            }
        }
    }

    // MARK: - Progress Types

    enum Progress: Sendable {
        case checking
        case downloading(percent: Double, speed: String?)
        case extractingAudio
        case complete(audioURL: URL)
    }

    // MARK: - Singleton

    static let shared = YouTubeDownloader()
    private init() {}

    // MARK: - Dependency Checking

    /// Check if required command-line tools are installed
    func checkDependencies() async -> (ytDlp: Bool, ffmpeg: Bool) {
        let ytDlpInstalled = await checkCommand("yt-dlp")
        let ffmpegInstalled = await checkCommand("ffmpeg")
        return (ytDlpInstalled, ffmpegInstalled)
    }

    private func checkCommand(_ command: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - URL Validation

    /// Validate that the URL is a valid YouTube URL
    nonisolated func isValidYouTubeURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        guard let host = url.host?.lowercased() else { return false }

        let validHosts = ["youtube.com", "www.youtube.com", "youtu.be", "m.youtube.com"]
        return validHosts.contains(host)
    }

    // MARK: - Download

    /// Download audio from a YouTube video
    /// - Parameter url: YouTube video URL
    /// - Returns: AsyncThrowingStream of progress updates
    nonisolated func downloadAudio(from url: String) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Validate URL
                    guard isValidYouTubeURL(url) else {
                        continuation.finish(throwing: DownloadError.invalidURL)
                        return
                    }

                    continuation.yield(.checking)

                    // Check dependencies
                    let deps = await checkDependencies()
                    guard deps.ytDlp else {
                        continuation.finish(throwing: DownloadError.ytDlpNotFound)
                        return
                    }
                    guard deps.ffmpeg else {
                        continuation.finish(throwing: DownloadError.ffmpegNotFound)
                        return
                    }

                    // Create temp directory for download
                    let tempDir = FileManager.default.temporaryDirectory
                        .appending(path: "youtube_import_\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                    let outputTemplate = tempDir.appending(path: "audio.%(ext)s").path

                    // Run yt-dlp to download and extract audio
                    // Using -x (extract audio) with ffmpeg as post-processor
                    let ytDlpPath = try await findExecutable("yt-dlp")

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: ytDlpPath)
                    process.arguments = [
                        "-x",                           // Extract audio
                        "--audio-format", "m4a",        // Convert to m4a (good balance of quality/size)
                        "--audio-quality", "0",         // Best quality
                        "-o", outputTemplate,           // Output template
                        "--no-playlist",                // Don't download playlists
                        "--progress",                   // Show progress
                        "--newline",                    // Progress on new lines (easier to parse)
                        url
                    ]

                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe

                    try process.run()

                    // Parse progress from output
                    let outputHandle = outputPipe.fileHandleForReading
                    var lastPercent: Double = 0

                    // Read output asynchronously
                    for try await line in outputHandle.bytes.lines {
                        if let progress = parseYtDlpProgress(line) {
                            if progress.percent != lastPercent {
                                lastPercent = progress.percent
                                continuation.yield(.downloading(percent: progress.percent, speed: progress.speed))
                            }
                        }
                    }

                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.finish(throwing: DownloadError.downloadFailed(errorMessage))
                        return
                    }

                    // Find the output audio file
                    let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                    guard let audioFile = files.first(where: { $0.pathExtension == "m4a" || $0.pathExtension == "mp3" || $0.pathExtension == "aac" }) else {
                        continuation.finish(throwing: DownloadError.audioExtractionFailed("No audio file found"))
                        return
                    }

                    continuation.yield(.complete(audioURL: audioFile))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    private nonisolated func findExecutable(_ name: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DownloadError.ytDlpNotFound
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw DownloadError.ytDlpNotFound
        }

        return path
    }

    private nonisolated func parseYtDlpProgress(_ line: String) -> (percent: Double, speed: String?)? {
        // yt-dlp progress format: [download]  45.2% of 10.50MiB at 2.50MiB/s ETA 00:03
        guard line.contains("[download]") else { return nil }

        // Extract percentage
        let pattern = #"(\d+\.?\d*)%"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let percentRange = Range(match.range(at: 1), in: line),
              let percent = Double(line[percentRange]) else {
            return nil
        }

        // Extract speed if available
        var speed: String?
        let speedPattern = #"at\s+([\d.]+\w+/s)"#
        if let speedRegex = try? NSRegularExpression(pattern: speedPattern),
           let speedMatch = speedRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let speedRange = Range(speedMatch.range(at: 1), in: line) {
            speed = String(line[speedRange])
        }

        return (percent, speed)
    }

    // MARK: - Compression

    /// Maximum file size for Whisper API (25MB)
    static let maxWhisperFileSize: Int64 = 25 * 1024 * 1024

    /// Compress audio file to reduce size for Whisper API
    /// Uses progressively lower bitrates until under 25MB
    /// - Parameter audioURL: The audio file to compress
    /// - Returns: URL to compressed file (may be same as input if already small enough)
    nonisolated func compressIfNeeded(audioURL: URL) async throws -> URL {
        let fileSize = try FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64 ?? 0

        guard fileSize > Self.maxWhisperFileSize else {
            return audioURL // Already small enough
        }

        StructuredLogger.log(component: "YouTube Import", message: "Audio file too large (\(fileSize / 1_000_000)MB), compressing...")

        // Choose bitrate based on input file size
        // Larger files need more aggressive compression to fit under 25MB
        // At mono 16kHz: 48k ~= 360KB/min, 32k ~= 240KB/min, 24k ~= 180KB/min
        let bitrate: String
        if fileSize > 100 * 1024 * 1024 {
            bitrate = "32k"  // >100MB: aggressive compression
        } else if fileSize > 50 * 1024 * 1024 {
            bitrate = "48k"  // 50-100MB: moderate compression
        } else {
            bitrate = "48k"  // 25-50MB: light compression
        }

        let compressedURL = audioURL.deletingLastPathComponent()
            .appending(path: "compressed_audio.mp3")

        // Find ffmpeg
        let ffmpegPath = try await findFfmpeg()
        StructuredLogger.log(component: "YouTube Import", message: "Using ffmpeg at: \(ffmpegPath)")

        // Log input file details
        let inputAttrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
        let inputSize = (inputAttrs?[.size] as? Int64) ?? 0
        StructuredLogger.log(component: "YouTube Import", message: "Input file: \(audioURL.lastPathComponent), size: \(inputSize / 1_000_000)MB")

        let args = [
            "-nostdin",            // Don't wait for keyboard input
            "-i", audioURL.path,
            "-b:a", bitrate,
            "-map", "a",           // Audio only
            "-ac", "1",            // Mono (halves size, fine for speech)
            "-ar", "16000",        // 16kHz sample rate (good for speech)
            "-y",                  // Overwrite output
            compressedURL.path
        ]
        StructuredLogger.log(component: "YouTube Import", message: "Running: ffmpeg \(args.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args

        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        // Read stderr for debugging
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            StructuredLogger.log(component: "YouTube Import", message: "ffmpeg exit code: \(process.terminationStatus)")
            // Log last few lines of stderr (ffmpeg outputs a lot)
            let errorLines = stderrOutput.split(separator: "\n").suffix(10).joined(separator: "\n")
            StructuredLogger.log(component: "YouTube Import", message: "ffmpeg stderr:\n\(errorLines)")
            throw DownloadError.audioExtractionFailed("ffmpeg compression failed (exit \(process.terminationStatus))")
        }

        // Check if output file was created
        guard FileManager.default.fileExists(atPath: compressedURL.path) else {
            StructuredLogger.log(component: "YouTube Import", message: "ERROR: Output file not created!")
            let errorLines = stderrOutput.split(separator: "\n").suffix(10).joined(separator: "\n")
            StructuredLogger.log(component: "YouTube Import", message: "ffmpeg stderr:\n\(errorLines)")
            throw DownloadError.audioExtractionFailed("ffmpeg produced no output file")
        }

        let compressedSize = try FileManager.default.attributesOfItem(atPath: compressedURL.path)[.size] as? Int64 ?? 0

        StructuredLogger.log(
            component: "YouTube Import",
            message: "Compressed to \(compressedSize / 1_000_000)MB (bitrate: \(bitrate), mono, 16kHz)"
        )

        // If still too large, try again with lower bitrate
        if compressedSize > Self.maxWhisperFileSize {
            StructuredLogger.log(component: "YouTube Import", message: "Still too large, recompressing with 24k bitrate...")

            let ultraCompressedURL = audioURL.deletingLastPathComponent()
                .appending(path: "ultra_compressed_audio.mp3")

            let args2 = [
                "-nostdin",            // Don't wait for keyboard input
                "-i", audioURL.path,
                "-b:a", "24k",
                "-map", "a",
                "-ac", "1",
                "-ar", "16000",
                "-y",
                ultraCompressedURL.path
            ]
            StructuredLogger.log(component: "YouTube Import", message: "Running: ffmpeg \(args2.joined(separator: " "))")

            let process2 = Process()
            process2.executableURL = URL(fileURLWithPath: ffmpegPath)
            process2.arguments = args2

            let stderrPipe2 = Pipe()
            process2.standardInput = FileHandle.nullDevice
            process2.standardOutput = FileHandle.nullDevice
            process2.standardError = stderrPipe2

            try process2.run()
            process2.waitUntilExit()

            guard process2.terminationStatus == 0 else {
                let stderrData2 = stderrPipe2.fileHandleForReading.readDataToEndOfFile()
                let stderrOutput2 = String(data: stderrData2, encoding: .utf8) ?? ""
                StructuredLogger.log(component: "YouTube Import", message: "ffmpeg exit code: \(process2.terminationStatus)")
                let errorLines = stderrOutput2.split(separator: "\n").suffix(10).joined(separator: "\n")
                StructuredLogger.log(component: "YouTube Import", message: "ffmpeg stderr:\n\(errorLines)")
                throw DownloadError.audioExtractionFailed("ffmpeg ultra compression failed (exit \(process2.terminationStatus))")
            }

            let ultraSize = try FileManager.default.attributesOfItem(atPath: ultraCompressedURL.path)[.size] as? Int64 ?? 0
            StructuredLogger.log(component: "YouTube Import", message: "Ultra-compressed to \(ultraSize / 1_000_000)MB")

            // Clean up first compressed file
            try? FileManager.default.removeItem(at: compressedURL)

            return ultraCompressedURL
        }

        return compressedURL
    }

    private nonisolated func findFfmpeg() async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DownloadError.ffmpegNotFound
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            throw DownloadError.ffmpegNotFound
        }

        return path
    }

    // MARK: - Cleanup

    /// Clean up temporary files from a previous download
    nonisolated func cleanup(audioURL: URL) {
        // Remove the parent temp directory
        let tempDir = audioURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: tempDir)
    }
}
