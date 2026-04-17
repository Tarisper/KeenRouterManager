import CryptoKit
import Foundation

/**
 * Errors returned by the Keenetic HTTP API integration.
 */
enum RouterAPIError: LocalizedError {
    case invalidAddress
    case invalidResponse
    case server(statusCode: Int, path: String)
    case authenticationFailed(String)
    case transport(String)
    case unsupportedAuthChallenge

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return LocalizationManager.shared.text("error.router.invalidAddress")
        case .invalidResponse:
            return LocalizationManager.shared.text("error.router.invalidResponse")
        case let .server(statusCode, path):
            return LocalizationManager.shared.text("error.router.serverStatusPath", args: [statusCode, path])
        case let .authenticationFailed(reason):
            return reason
        case let .transport(message):
            return LocalizationManager.shared.text("error.router.transport", args: [message])
        case .unsupportedAuthChallenge:
            return LocalizationManager.shared.text("error.router.unsupportedAuthChallenge")
        }
    }
}

/**
 * Low-level Keenetic API client.
 *
 * Handles:
 * - router address normalization with scheme/port fallback;
 * - authentication via `/auth`;
 * - policy and client loading;
 * - policy application and client blocking.
 */
final class KeeneticAPIClient {
    private let username: String
    private let password: String
    private let host: String
    private let port: Int?
    private let preferredScheme: String
    private let hasExplicitScheme: Bool
    private let requestedAddress: String

    private var baseAddress: String
    private var session: URLSession
    private var sessionDelegate: InsecureRouterTLSDelegate?
    private var sessionCookie: String?

    private static var localization: LocalizationManager {
        LocalizationManager.shared
    }

    /**
     * Initializes an API client for a specific router.
     * - Parameters:
     *   - address: Router address (scheme may be omitted).
     *   - username: Login username.
     *   - password: Login password.
     * - Throws: `RouterAPIError.invalidAddress` when the address is invalid.
     */
    init(address: String, username: String, password: String) throws {
        let rawAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOriginal = rawAddress.lowercased()
        self.hasExplicitScheme = trimmedOriginal.hasPrefix("http://") || trimmedOriginal.hasPrefix("https://")
        self.requestedAddress = rawAddress

        let normalized = try Self.normalizedBaseAddress(from: address)
        guard let components = URLComponents(string: normalized),
              let host = components.host,
              !host.isEmpty
        else {
            throw RouterAPIError.invalidAddress
        }

        self.username = username
        self.password = password

        let scheme = (components.scheme ?? "http").lowercased()
        self.preferredScheme = (scheme == "https") ? "https" : "http"

        self.host = host
        self.port = components.port

        self.baseAddress = normalized
        self.session = URLSession(configuration: Self.makeSessionConfiguration())
    }

    /**
     * Actual address used by the active connection.
     */
    var connectionAddress: String {
        baseAddress
    }

    /**
     * Normalizes a user-provided base router address.
     * - Parameter rawAddress: Raw address string.
     * - Returns: Canonical `http(s)://host[:port]` address.
     * - Throws: `RouterAPIError.invalidAddress` when parsing fails.
     */
    static func normalizedBaseAddress(from rawAddress: String) throws -> String {
        var trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        guard !trimmed.isEmpty else {
            throw RouterAPIError.invalidAddress
        }

        let withScheme: String
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "http://\(trimmed)"
        }

        guard var components = URLComponents(string: withScheme),
              let host = components.host,
              !host.isEmpty
        else {
            throw RouterAPIError.invalidAddress
        }

        let scheme = (components.scheme ?? "http").lowercased()
        guard scheme == "http" || scheme == "https" else {
            throw RouterAPIError.invalidAddress
        }

        components.scheme = scheme
        components.path = ""
        components.query = nil
        components.fragment = nil

        guard var normalized = components.url?.absoluteString else {
            throw RouterAPIError.invalidAddress
        }
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    /**
     * Authenticates against the router and selects a working fallback endpoint.
     * - Throws: `RouterAPIError` when authentication or transport fails.
     */
    func authenticate() async throws {
        sessionCookie = nil
        let candidates = baseCandidates()
        var lastError: Error = RouterAPIError.authenticationFailed(Self.localization.text("error.auth.default"))
        var attemptedErrors: [String] = []
        var firstAuthError: RouterAPIError?

        for candidate in candidates {
            let delegate = InsecureRouterTLSDelegate(username: username, password: password)
            let candidateSession = URLSession(
                configuration: Self.makeSessionConfiguration(),
                delegate: delegate,
                delegateQueue: nil
            )

            do {
                let candidateCookie = try await authenticate(baseAddress: candidate, session: candidateSession)
                baseAddress = candidate
                session = candidateSession
                sessionDelegate = delegate
                sessionCookie = candidateCookie
                return
            } catch let apiError as RouterAPIError {
                let reason = apiError.errorDescription ?? String(describing: apiError)
                attemptedErrors.append("\(candidate) -> \(reason)")
                if firstAuthError == nil {
                    switch apiError {
                    case .authenticationFailed, .unsupportedAuthChallenge:
                        firstAuthError = apiError
                    case let .server(statusCode, _):
                        if statusCode == 401 || statusCode == 403 {
                            firstAuthError = apiError
                        }
                    default:
                        break
                    }
                }
                lastError = apiError
                candidateSession.invalidateAndCancel()
            } catch {
                attemptedErrors.append("\(candidate) -> \(error.localizedDescription)")
                lastError = error
                candidateSession.invalidateAndCancel()
            }
        }

        if let firstAuthError {
            let baseReason = firstAuthError.errorDescription ?? Self.localization.text("error.auth.default")
            let attempts = attemptedErrors.joined(separator: " | ")
            throw RouterAPIError.authenticationFailed(
                Self.localization.text("error.auth.withAttempts", args: [baseReason, attempts])
            )
        }

        if let apiError = lastError as? RouterAPIError {
            switch apiError {
            case let .transport(message):
                let tlsHint = (message.contains("TLS") || message.contains("secure connection"))
                    ? Self.localization.text("error.auth.hintTLS")
                    : Self.localization.text("error.auth.hintPort")
                throw RouterAPIError.authenticationFailed(
                    Self.localization.text(
                        "error.auth.cannotConnectWithHint",
                        args: [message, tlsHint, attemptedErrors.joined(separator: " | ")]
                    )
                )
            default:
                throw lastError
            }
        }

        throw lastError
    }

    /**
     * Runs a non-destructive connectivity and authentication diagnostic against
     * all candidate router endpoints.
     * - Returns: Structured diagnostic report for UI presentation.
     */
    func diagnoseConnection() async -> ConnectionDiagnosticReport {
        var attempts: [ConnectionDiagnosticAttempt] = []
        var lastError: RouterAPIError?

        for candidate in baseCandidates() {
            let delegate = InsecureRouterTLSDelegate(username: username, password: password)
            let candidateSession = URLSession(
                configuration: Self.makeSessionConfiguration(),
                delegate: delegate,
                delegateQueue: nil
            )

            do {
                _ = try await authenticate(baseAddress: candidate, session: candidateSession)
                attempts.append(
                    ConnectionDiagnosticAttempt(
                        endpoint: candidate,
                        outcome: .success,
                        message: Self.localization.text("diagnostics.attempt.success")
                    )
                )

                return ConnectionDiagnosticReport(
                    requestedAddress: requestedAddress,
                    normalizedAddress: baseAddress,
                    succeededEndpoint: candidate,
                    guidance: Self.localization.text("diagnostics.guidance.success"),
                    attempts: attempts,
                    completedAt: Date()
                )
            } catch let error as RouterAPIError {
                lastError = error
                attempts.append(
                    ConnectionDiagnosticAttempt(
                        endpoint: candidate,
                        outcome: .failure,
                        message: error.localizedDescription
                    )
                )
            } catch {
                attempts.append(
                    ConnectionDiagnosticAttempt(
                        endpoint: candidate,
                        outcome: .failure,
                        message: error.localizedDescription
                    )
                )
            }

            candidateSession.invalidateAndCancel()
        }

        return ConnectionDiagnosticReport(
            requestedAddress: requestedAddress,
            normalizedAddress: baseAddress,
            succeededEndpoint: nil,
            guidance: diagnosticGuidance(for: lastError),
            attempts: attempts,
            completedAt: Date()
        )
    }

    /**
     * Loads available access policies.
     * - Returns: Sorted list of policies.
     * - Throws: `RouterAPIError` on API or transport failure.
     */
    func fetchPolicies() async throws -> [RouterPolicy] {
        let (json, response) = try await requestJSON(path: "rci/show/rc/ip/policy")
        guard response.statusCode == 200 else {
            throw RouterAPIError.server(statusCode: response.statusCode, path: "rci/show/rc/ip/policy")
        }

        // Keenetic often returns a dictionary: { "Policy0": { "description": "XKeen", ... } }
        if let object = json as? [String: Any] {
            var items: [RouterPolicy] = []
            for (id, raw) in object {
                let displayName: String
                if let details = raw as? [String: Any] {
                    let desc = Self.stringValue(details["description"], fallback: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !desc.isEmpty {
                        displayName = desc
                    } else {
                        let name = Self.stringValue(details["name"], fallback: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        displayName = name.isEmpty ? id : name
                    }
                } else {
                    displayName = id
                }

                items.append(RouterPolicy(id: id, displayName: displayName))
            }

            return items.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }

        // Compatibility fallback for array-like responses.
        guard let rows = json as? [[String: Any]] else {
            return []
        }

        let items = rows.compactMap { row -> RouterPolicy? in
            let id = Self.stringValue(row["name"], fallback: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return nil }
            let desc = Self.stringValue(row["description"], fallback: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return RouterPolicy(id: id, displayName: desc.isEmpty ? id : desc)
        }

        // Deduplicate by id preserving the first pretty name.
        var seen = Set<String>()
        let deduplicated = items.filter {
            seen.insert($0.id).inserted
        }

        return deduplicated.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /**
     * Loads and merges clients from multiple Keenetic endpoints.
     * - Returns: Sorted clients (online first, then by name).
     * - Throws: `RouterAPIError` on API or transport failure.
     */
    func fetchClients() async throws -> [RouterClient] {
        let (clientsJSON, clientsResponse) = try await requestJSON(path: "rci/show/ip/hotspot/host")
        guard clientsResponse.statusCode == 200 else {
            throw RouterAPIError.server(statusCode: clientsResponse.statusCode, path: "rci/show/ip/hotspot/host")
        }

        var clientsByMac: [String: RouterClient] = [:]
        if let rows = clientsJSON as? [[String: Any]] {
            for row in rows {
                let mac = Self.stringValue(row["mac"], fallback: "").lowercased()
                guard !mac.isEmpty else { continue }
                let ip = Self.stringValue(row["ip"], fallback: Self.localization.text("common.notAvailable"))
                let isOnline = Self.inferOnline(from: row, fallbackIP: ip)
                let details = Self.extractClientDetails(from: row)

                let client = RouterClient(
                    name: Self.stringValue(row["name"], fallback: Self.localization.text("client.unknown")),
                    ip: ip,
                    mac: mac,
                    policy: nil,
                    access: "deny",
                    isOnline: isOnline,
                    segmentTitle: details.segmentTitle,
                    segmentSubtitle: details.segmentSubtitle,
                    connectionTitle: details.connectionTitle,
                    connectionSubtitle: details.connectionSubtitle,
                    trafficPriority: details.trafficPriority
                )
                clientsByMac[mac] = client
            }
        }

        let (policyJSON, policyResponse) = try await requestJSON(path: "rci/show/rc/ip/hotspot/host")
        if policyResponse.statusCode == 200, let rows = policyJSON as? [[String: Any]] {
            for row in rows {
                let mac = Self.stringValue(row["mac"], fallback: "").lowercased()
                guard !mac.isEmpty else { continue }
                let details = Self.extractClientDetails(from: row)

                var current = clientsByMac[mac] ?? RouterClient(
                    name: Self.localization.text("client.unknown"),
                    ip: Self.localization.text("common.notAvailable"),
                    mac: mac,
                    policy: nil,
                    access: "deny",
                    isOnline: false,
                    segmentTitle: details.segmentTitle,
                    segmentSubtitle: details.segmentSubtitle,
                    connectionTitle: details.connectionTitle,
                    connectionSubtitle: details.connectionSubtitle,
                    trafficPriority: details.trafficPriority
                )
                current.policy = Self.optionalStringValue(row["policy"])
                current.access = Self.stringValue(row["access"], fallback: "deny")
                current.isOnline = current.isOnline || Self.inferOnline(from: row, fallbackIP: current.ip)
                Self.merge(details: details, into: &current)
                clientsByMac[mac] = current
            }
        }

        return clientsByMac.values.sorted {
            if $0.isOnline != $1.isOnline {
                return $0.isOnline && !$1.isOnline
            }

            let byName = $0.name.caseInsensitiveCompare($1.name)
            if byName == .orderedSame {
                return $0.mac < $1.mac
            }
            return byName == .orderedAscending
        }
    }

    /**
     * Applies an access policy to a client by MAC address.
     * - Parameters:
     *   - mac: Client MAC address.
     *   - policy: Policy identifier, or `nil` for the default policy.
     * - Throws: `RouterAPIError` when the API response is not successful.
     */
    func applyPolicy(mac: String, policy: String?) async throws {
        let payload: [String: Any] = [
            "mac": mac,
            "policy": policy ?? false,
            "permit": true,
            "schedule": false,
        ]

        let (_, response) = try await request(path: "rci/ip/hotspot/host", method: "POST", body: payload)
        guard response.statusCode == 200 else {
            throw RouterAPIError.server(statusCode: response.statusCode, path: "rci/ip/hotspot/host")
        }
    }

    /**
     * Blocks internet access for a client.
     * - Parameter mac: Client MAC address.
     * - Throws: `RouterAPIError` when the API response is not successful.
     */
    func setClientBlocked(mac: String) async throws {
        let payload: [String: Any] = [
            "mac": mac,
            "schedule": false,
            "deny": true,
        ]

        let (_, response) = try await request(path: "rci/ip/hotspot/host", method: "POST", body: payload)
        guard response.statusCode == 200 else {
            throw RouterAPIError.server(statusCode: response.statusCode, path: "rci/ip/hotspot/host")
        }
    }

    private struct ClientDetails {
        var segmentTitle: String?
        var segmentSubtitle: String?
        var connectionTitle: String?
        var connectionSubtitle: String?
        var trafficPriority: String?
    }

    private static func extractClientDetails(from row: [String: Any]) -> ClientDetails {
        let mws = (row["mws"] as? [String: Any]) ?? [:]
        let segmentObject = row["segment"] as? [String: Any]
        let interfaceObject = row["interface"] as? [String: Any]
        let qosObject = row["qos"] as? [String: Any]

        var details = ClientDetails()

        let segmentTitle = firstNonEmptyString(
            in: row,
            keys: ["segment-name", "segment_name", "segmentTitle", "segment", "network", "zone", "pool", "realm"]
        ) ?? firstNonEmptyString(
            in: segmentObject ?? [:],
            keys: ["description", "title", "name", "id"]
        )

        let segmentSubtitle = firstNonEmptyString(
            in: row,
            keys: ["segment-type", "segment_type", "media", "medium", "interface", "ifname", "ssid", "band"]
        ) ?? firstNonEmptyString(
            in: interfaceObject ?? [:],
            keys: ["description", "name", "id", "type"]
        ) ?? firstNonEmptyString(
            in: mws,
            keys: ["band", "ssid", "interface", "ifname"]
        )

        details.segmentTitle = segmentTitle
        details.segmentSubtitle = dedupeDetailsText(segmentSubtitle, against: segmentTitle)

        let rawRate = firstNonEmptyString(
            in: row,
            keys: ["speed", "rate", "link-rate", "link_rate", "tx-rate", "tx_rate", "phy-rate", "phy_rate", "throughput"]
        ) ?? firstNonEmptyString(
            in: mws,
            keys: ["speed", "rate", "link-rate", "link_rate", "tx-rate", "tx_rate", "phy-rate", "phy_rate"]
        )

        let security = firstNonEmptyString(
            in: row,
            keys: ["security", "auth", "encryption", "cipher"]
        ) ?? firstNonEmptyString(
            in: mws,
            keys: ["security", "auth", "encryption", "cipher"]
        )

        let linkType = firstNonEmptyString(
            in: row,
            keys: ["connection", "connection-type", "connection_type", "link-type", "link_type", "media", "medium"]
        )

        let port = firstNonEmptyString(
            in: row,
            keys: ["port", "switch-port", "switch_port", "ether-port", "ether_port"]
        )

        var connectionTitleParts: [String] = []
        if let normalizedRate = normalizedRate(rawRate) {
            connectionTitleParts.append(normalizedRate)
        }
        if let security {
            connectionTitleParts.append(security)
        }
        if let linkType {
            connectionTitleParts.append(linkType)
        }
        if connectionTitleParts.isEmpty, let port {
            connectionTitleParts.append(Self.localization.text("router.portLabel", args: [port]))
        }
        details.connectionTitle = joinUnique(connectionTitleParts, separator: " ")

        var connectionSubtitleParts: [String] = []
        connectionSubtitleParts.append(contentsOf: [
            firstNonEmptyString(in: row, keys: ["standard", "mode", "protocol", "phy", "radio"]),
            firstNonEmptyString(in: row, keys: ["channel-width", "channel_width", "width", "bw"]),
            firstNonEmptyString(in: row, keys: ["streams", "nss"]),
            firstNonEmptyString(in: mws, keys: ["standard", "mode", "protocol", "phy"]),
            firstNonEmptyString(in: mws, keys: ["channel-width", "channel_width", "width", "bw"]),
            firstNonEmptyString(in: mws, keys: ["streams", "nss"]),
            firstNonEmptyString(in: mws, keys: ["band", "ssid"]),
        ].compactMap { $0 })

        if let port,
           details.connectionTitle?.localizedCaseInsensitiveContains(port) != true
        {
            connectionSubtitleParts.append(Self.localization.text("router.portLabel", args: [port]))
        }

        details.connectionSubtitle = dedupeDetailsText(
            joinUnique(connectionSubtitleParts, separator: " "),
            against: details.connectionTitle
        )

        details.trafficPriority = firstNonEmptyString(
            in: row,
            keys: ["priority", "traffic-priority", "traffic_priority", "prio", "qos-priority", "qos_priority"]
        ) ?? firstNonEmptyString(
            in: qosObject ?? [:],
            keys: ["priority", "class", "value"]
        ) ?? firstNonEmptyString(
            in: mws,
            keys: ["priority", "prio"]
        )

        return details
    }

    private static func merge(details: ClientDetails, into client: inout RouterClient) {
        if let segmentTitle = details.segmentTitle {
            client.segmentTitle = segmentTitle
        }
        if let segmentSubtitle = details.segmentSubtitle {
            client.segmentSubtitle = segmentSubtitle
        }
        if let connectionTitle = details.connectionTitle {
            client.connectionTitle = connectionTitle
        }
        if let connectionSubtitle = details.connectionSubtitle {
            client.connectionSubtitle = connectionSubtitle
        }
        if let trafficPriority = details.trafficPriority {
            client.trafficPriority = trafficPriority
        }
    }

    private static func firstNonEmptyString(in object: [String: Any], keys: [String]) -> String? {
        guard !object.isEmpty else { return nil }

        for key in keys {
            let value = optionalStringValue(object[key])?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                return value
            }
        }

        return nil
    }

    private static func joinUnique(_ values: [String], separator: String) -> String? {
        var unique: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if !unique.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
                unique.append(normalized)
            }
        }
        return unique.isEmpty ? nil : unique.joined(separator: separator)
    }

    private static func dedupeDetailsText(_ value: String?, against base: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        guard let base = base?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty else {
            return value
        }

        if value.caseInsensitiveCompare(base) == .orderedSame {
            return nil
        }
        return value
    }

    private static func normalizedRate(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        let lower = raw.lowercased()
        if lower.contains("бит") || lower.contains("bit") {
            return raw
        }

        if let numeric = Double(raw.replacingOccurrences(of: ",", with: ".")) {
            if numeric == floor(numeric) {
                return Self.localization.text("router.rateMbpsInt", args: [Int(numeric)])
            }
            return Self.localization.text("router.rateMbpsFloat", args: [numeric])
        }

        return raw
    }

    private func diagnosticGuidance(for error: RouterAPIError?) -> String {
        guard let error else {
            return Self.localization.text("diagnostics.guidance.generic")
        }

        switch error {
        case .invalidAddress:
            return Self.localization.text("diagnostics.guidance.address")
        case .unsupportedAuthChallenge:
            return Self.localization.text("diagnostics.guidance.challenge")
        case .authenticationFailed:
            return Self.localization.text("diagnostics.guidance.credentials")
        case let .transport(message):
            if message.caseInsensitiveCompare(Self.localization.text("transport.tlsHandshakeFailed")) == .orderedSame {
                return Self.localization.text("diagnostics.guidance.tls")
            }
            return Self.localization.text("diagnostics.guidance.network")
        case .server:
            return Self.localization.text("diagnostics.guidance.server")
        case .invalidResponse:
            return Self.localization.text("diagnostics.guidance.response")
        }
    }

    private func baseCandidates() -> [String] {
        let http = buildBaseAddress(scheme: "http", portOverride: nil)
        let https = buildBaseAddress(scheme: "https", portOverride: nil)
        let httpNoPort = buildBaseAddressWithoutPort(scheme: "http")
        let httpsNoPort = buildBaseAddressWithoutPort(scheme: "https")

        // When an explicit port is provided, try that port first with scheme fallback.
        if port != nil {
            if isLikelyLocalAddress(host) {
                if preferredScheme == "https" {
                    return deduplicated([https, httpNoPort, http, httpsNoPort, buildBaseAddress(scheme: "https", portOverride: 8443)])
                }
                return deduplicated([http, httpNoPort, httpsNoPort, https, buildBaseAddress(scheme: "http", portOverride: 8080)])
            }

            if preferredScheme == "https" {
                return deduplicated([https, http, httpsNoPort, httpNoPort])
            }
            return deduplicated([http, https, httpNoPort, httpsNoPort])
        }

        // For local addresses (IP, .local, single-label host), HTTP is usually the best first try.
        if isLikelyLocalAddress(host), port == nil {
            var candidates: [String] = [http]
            candidates.append(buildBaseAddress(scheme: "https", portOverride: 8443))
            candidates.append(https)
            candidates.append(buildBaseAddress(scheme: "http", portOverride: 8080))
            candidates.append(buildBaseAddress(scheme: "http", portOverride: 81))
            return deduplicated(candidates)
        }

        // If scheme is omitted, prefer HTTPS first for KeenDNS and external domains.
        if !hasExplicitScheme {
            return deduplicated([https, http, buildBaseAddress(scheme: "https", portOverride: 8443)])
        }

        // With an explicit scheme: try user preference first, then fallback.
        if preferredScheme == "https" {
            return deduplicated([https, http, buildBaseAddress(scheme: "https", portOverride: 8443)])
        }
        return deduplicated([http, https, buildBaseAddress(scheme: "http", portOverride: 8080)])
    }

    private func buildBaseAddress(scheme: String, portOverride: Int?) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = portOverride ?? port
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "\(scheme)://\(host)"
    }

    private func buildBaseAddressWithoutPort(scheme: String) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = nil
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? "\(scheme)://\(host)"
    }

    private func deduplicated(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            if seen.insert(item).inserted {
                result.append(item)
            }
        }
        return result
    }

    private func isLikelyLocalAddress(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") {
            return true
        }
        if !lower.contains(".") {
            return true
        }
        return Self.isPrivateIPv4(lower)
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        guard let a = Int(parts[0]),
              let b = Int(parts[1]),
              let c = Int(parts[2]),
              let d = Int(parts[3]),
              (0...255).contains(a),
              (0...255).contains(b),
              (0...255).contains(c),
              (0...255).contains(d)
        else {
            return false
        }

        if a == 10 || a == 127 {
            return true
        }
        if a == 172 && (16...31).contains(b) {
            return true
        }
        if a == 192 && b == 168 {
            return true
        }
        if a == 169 && b == 254 {
            return true
        }
        return false
    }

    private func authenticate(baseAddress: String, session: URLSession) async throws -> String? {
        let (_, initialResponse) = try await request(path: "auth", method: "GET", baseAddress: baseAddress, session: session)

        var cookieHeader = parseCookieHeader(from: initialResponse)

        if initialResponse.statusCode == 200 {
            return cookieHeader
        }

        guard initialResponse.statusCode == 401 else {
            throw RouterAPIError.authenticationFailed(
                Self.localization.text(
                    "error.auth.initialStatus",
                    args: [baseAddress, initialResponse.statusCode]
                )
            )
        }

        guard let realm = initialResponse.value(forHTTPHeaderField: "X-NDM-Realm"),
              let challenge = initialResponse.value(forHTTPHeaderField: "X-NDM-Challenge")
        else {
            throw RouterAPIError.unsupportedAuthChallenge
        }

        let md5 = Self.md5Hex("\(username):\(realm):\(password)")
        let challengeHash = Self.sha256Hex("\(challenge)\(md5)")

        let payload: [String: Any] = [
            "login": username,
            "password": challengeHash,
        ]

        var headers: [String: String] = [:]
        if let cookieHeader {
            headers["Cookie"] = cookieHeader
        }

        let (_, authResponse) = try await request(
            path: "auth",
            method: "POST",
            body: payload,
            extraHeaders: headers,
            baseAddress: baseAddress,
            session: session
        )

        if let updatedCookie = parseCookieHeader(from: authResponse) {
            cookieHeader = updatedCookie
        }

        guard authResponse.statusCode == 200 else {
            let detail = authResponse.value(forHTTPHeaderField: "X-Detail")
            let detailSuffix = detail.map { Self.localization.text("detail.parenthesized", args: [$0]) } ?? ""
            throw RouterAPIError.authenticationFailed(
                Self.localization.text(
                    "error.auth.finalStatus",
                    args: [baseAddress, authResponse.statusCode, detailSuffix]
                )
            )
        }

        return cookieHeader
    }

    private static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 10
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.httpCookieStorage = HTTPCookieStorage()
        return configuration
    }

    private func buildURL(path: String, baseAddress: String) throws -> URL {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(baseAddress)/\(cleanPath)") else {
            throw RouterAPIError.invalidAddress
        }
        return url
    }

    private func request(
        path: String,
        method: String,
        body: [String: Any]? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        try await request(
            path: path,
            method: method,
            body: body,
            extraHeaders: extraHeaders,
            baseAddress: baseAddress,
            session: session
        )
    }

    private func request(
        path: String,
        method: String,
        body: [String: Any]? = nil,
        extraHeaders: [String: String] = [:],
        baseAddress: String,
        session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        let url = try buildURL(path: path, baseAddress: baseAddress)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        if let sessionCookie, !sessionCookie.isEmpty {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        for (header, value) in extraHeaders where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: header)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw RouterAPIError.invalidResponse
            }
            return (data, httpResponse)
        } catch let error as RouterAPIError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                throw RouterAPIError.transport(Self.localization.text("transport.tlsHandshakeFailed"))
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                throw RouterAPIError.transport(Self.localization.text("transport.couldNotConnect"))
            case .timedOut:
                throw RouterAPIError.transport(Self.localization.text("transport.requestTimedOut"))
            default:
                throw RouterAPIError.transport(error.localizedDescription)
            }
        } catch {
            throw RouterAPIError.transport(error.localizedDescription)
        }
    }

    private func requestJSON(path: String) async throws -> (Any, HTTPURLResponse) {
        let (data, response) = try await request(path: path, method: "GET")

        guard !data.isEmpty else {
            return ([:], response)
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data)
            return (json, response)
        } catch {
            throw RouterAPIError.invalidResponse
        }
    }

    private static func md5Hex(_ input: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func stringValue(_ value: Any?, fallback: String) -> String {
        guard let value else { return fallback }
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return fallback
    }

    private static func optionalStringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String, !string.isEmpty {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func inferOnline(from row: [String: Any], fallbackIP: String) -> Bool {
        if let online = row["online"] as? Bool {
            return online
        }

        if let active = row["active"] as? Bool {
            if active {
                return true
            }
        }

        let link = stringValue(row["link"], fallback: "").lowercased()
        if link == "up" || link == "online" || link == "connected" {
            return true
        }
        if link == "down" || link == "offline" {
            return false
        }

        if let mws = row["mws"] as? [String: Any] {
            let mwsLink = stringValue(mws["link"], fallback: "").lowercased()
            if mwsLink == "up" || mwsLink == "online" || mwsLink == "connected" {
                return true
            }
            if mwsLink == "down" || mwsLink == "offline" {
                return false
            }
        }
        _ = fallbackIP
        return false
    }

    private func parseCookieHeader(from response: HTTPURLResponse) -> String? {
        // Keenetic /auth returns one session cookie; send it back explicitly to avoid "no session" (HTTP 400).
        guard let raw = response.value(forHTTPHeaderField: "Set-Cookie"),
              !raw.isEmpty
        else {
            return nil
        }

        let firstPart = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first
        let cookie = firstPart.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cookie, cookie.contains("=") {
            return cookie
        }
        return nil
    }
}

/**
 * `URLSession` delegate for HTTP auth challenges and local self-signed TLS.
 */
private final class InsecureRouterTLSDelegate: NSObject, URLSessionDelegate {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    /**
     * Handles HTTP Basic/Digest and Server Trust challenges.
     * - Parameters:
     *   - session: Active URLSession instance.
     *   - challenge: Authentication challenge from the server.
     *   - completionHandler: Completion block with the chosen auth strategy.
     */
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod

        if method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest {
            let credential = URLCredential(user: username, password: password, persistence: .forSession)
            completionHandler(.useCredential, credential)
            return
        }

        if method == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }
}
