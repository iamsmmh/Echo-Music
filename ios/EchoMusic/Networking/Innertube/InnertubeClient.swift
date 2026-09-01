import Foundation

enum InnertubeError: LocalizedError {
    case httpStatus(Int, String?)
    case badResponse
    case visitorDataUnavailable
    case playbackUnavailable(String?)
    case streamRequiresDeciphering
    case parsing(String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let body):
            "InnerTube returned HTTP \(code)\(body.map { ": \($0.prefix(200))" } ?? "")"
        case .badResponse:
            "The server returned an unexpected response."
        case .visitorDataUnavailable:
            "Could not obtain a visitor ID."
        case .playbackUnavailable(let reason):
            reason.map { "Playback unavailable: \($0)" } ?? "Playback unavailable."
        case .streamRequiresDeciphering:
            "This stream requires signature deciphering, which isn't implemented yet."
        case .parsing(let kind):
            "Could not parse \(kind) response."
        }
    }
}

/// Low-level transport for the YouTube Music InnerTube API.
///
/// Everything here mirrors the Android repo's `InnerTube.kt` + `NetworkConfig.kt`:
/// same base URL, same public key, same headers, same retry behaviour. The typed,
/// domain-level calls live in `InnertubeAPI`.
final class InnertubeClient {
    /// Public web client key used by music.youtube.com (same key the Android app uses).
    static let apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX3"

    static let baseURL = URL(string: "https://music.youtube.com/youtubei/v1/")!
    static let origin = "https://music.youtube.com"

    // Session state
    var visitorData: String?
    var cookie: String?
    var dataSyncId: String?
    var hl: String = Locale.current.language.languageCode?.identifier ?? "en"
    var gl: String = Locale.current.region?.identifier ?? "US"

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.urlCache = URLCache(
            memoryCapacity: 20_000_000,
            diskCapacity: 200_000_000
        )
        session = URLSession(configuration: configuration)
    }

    /// Builds the `context` object for a request, mirroring `YouTubeClient.toContext()`.
    func context(profile: InnertubeClientProfile, loggedIn: Bool = false) -> InnerTubeContext {
        InnerTubeContext(
            client: InnerTubeContext.Client(
                clientName: profile.name,
                clientVersion: profile.version,
                osName: profile.osName,
                osVersion: profile.osVersion,
                deviceMake: profile.deviceMake,
                deviceModel: profile.deviceModel,
                androidSdkVersion: nil,
                gl: gl,
                hl: hl,
                visitorData: visitorData
            ),
            user: InnerTubeContext.User(
                lockedSafetyMode: false,
                onBehalfOfUser: loggedIn ? dataSyncId : nil
            )
        )
    }

    // MARK: - Core request

    /// POSTs a JSON body to an InnerTube endpoint and decodes the response.
    /// Retries transient transport errors up to 3 times with exponential backoff,
    /// matching the Android `withRetry` wrapper.
    func post<Body: Encodable, Response: Decodable>(
        _ endpoint: String,
        profile: InnertubeClientProfile,
        body: Body,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        try await withRetry {
            var components = URLComponents(
                url: Self.baseURL.appendingPathComponent(endpoint),
                resolvingAgainstBaseURL: false
            )!
            var items = query
            items.append(URLQueryItem(name: "key", value: Self.apiKey))
            items.append(URLQueryItem(name: "prettyPrint", value: "false"))
            components.queryItems = items

            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(body)

            // Headers mirror `InnerTube.ytClient()` in the Android repo.
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("\(hl),\(gl);q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("1", forHTTPHeaderField: "X-Goog-Api-Format-Version")
            request.setValue(profile.clientID, forHTTPHeaderField: "X-YouTube-Client-Name")
            request.setValue(profile.version, forHTTPHeaderField: "X-YouTube-Client-Version")
            request.setValue(Self.origin, forHTTPHeaderField: "X-Origin")
            request.setValue(Self.origin + "/", forHTTPHeaderField: "Referer")
            request.setValue(profile.userAgent, forHTTPHeaderField: "User-Agent")
            if let visitorData {
                request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
            }
            if let cookie {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw InnertubeError.badResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                throw InnertubeError.httpStatus(
                    http.statusCode,
                    String(data: data, encoding: .utf8)
                )
            }
            return try JSONDecoder().decode(Response.self, from: data)
        }
    }

    // MARK: - Visitor data bootstrap

    /// Fetches a visitor ID once per app session. Required for most endpoints.
    func ensureVisitorData() async throws {
        if visitorData != nil { return }
        visitorData = try await fetchVisitorData()
    }

    private func fetchVisitorData() async throws -> String {
        let userAgent = InnertubeClientProfile.webRemix.userAgent

        // 1) sw.js_data — same source the Android app uses (`getSwJsData`).
        if let url = URL(string: "https://music.youtube.com/sw.js_data") {
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await session.data(for: request),
               let text = String(data: data, encoding: .utf8),
               let visitorData = Self.extractVisitorData(from: text) {
                return visitorData
            }
        }

        // 2) Fallback: ytcfg in the www.youtube.com HTML.
        if let url = URL(string: "https://www.youtube.com") {
            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await session.data(for: request),
               let text = String(data: data, encoding: .utf8),
               let visitorData = Self.extractVisitorData(from: text) {
                return visitorData
            }
        }

        throw InnertubeError.visitorDataUnavailable
    }

    static func extractVisitorData(from text: String) -> String? {
        let pattern = #""visitorData"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    // MARK: - Playback registration

    /// Fire-and-forget beacon that tells YouTube a track started playing.
    /// Mirrors `registerPlayback()` in the Android repo (s.youtube.com → music.youtube.com).
    func registerPlayback(baseURL: String, playlistId: String?) async throws {
        let rewritten = baseURL.replacingOccurrences(
            of: "https://s.youtube.com",
            with: "https://music.youtube.com"
        )
        guard var components = URLComponents(string: rewritten) else { return }
        var items = components.queryItems ?? []
        items.append(contentsOf: [
            URLQueryItem(name: "ver", value: "2"),
            URLQueryItem(name: "c", value: InnertubeClientProfile.webRemix.name),
            URLQueryItem(name: "cpn", value: Self.randomCPN())
        ])
        if let playlistId {
            items.append(URLQueryItem(name: "list", value: playlistId))
            items.append(URLQueryItem(
                name: "referrer",
                value: "https://music.youtube.com/playlist?list=\(playlistId)"
            ))
        }
        components.queryItems = items
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(InnertubeClientProfile.webRemix.userAgent, forHTTPHeaderField: "User-Agent")
        _ = try await session.data(for: request)
    }

    static func randomCPN() -> String {
        let alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        return String((0..<16).map { _ in alphabet.randomElement()! })
    }

    // MARK: - Retry

    private func withRetry<T>(
        maxAttempts: Int = 3,
        operation: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var delay: UInt64 = 500_000_000 // 500 ms
        while true {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError {
                attempt += 1
                if attempt >= maxAttempts { throw error }
                try await Task.sleep(nanoseconds: delay)
                delay *= 2
            }
        }
    }
}
