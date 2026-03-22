import Foundation

/// One saved learning debrief from `preferences.learningDebriefs` (newest-first in `AuthStore.learningDebriefEntries()`).
struct LearningDebriefEntry: Identifiable, Hashable {
    let id: String
    let taskId: String
    let taskTitle: String
    let confidence: Int
    /// Raw value from storage (e.g. `time`, `understanding`, or custom text).
    let blocker: String
    let revisit: String
    let recordedAt: Date?
    let atISO: String

    var blockerDisplayLabel: String {
        switch blocker.lowercased() {
        case "time": return "Ran out of time"
        case "understanding": return "Didn't fully understand"
        case "motivation": return "Hard to stay motivated"
        case "other": return "Other"
        default: return blocker.isEmpty ? "—" : blocker
        }
    }

    init?(dictionary: [String: Any]) {
        let title = (dictionary["taskTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }

        let id = (dictionary["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskId = (dictionary["taskId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let conf: Int = {
            if let i = dictionary["confidence"] as? Int { return min(5, max(1, i)) }
            if let d = dictionary["confidence"] as? Double { return min(5, max(1, Int(d.rounded()))) }
            if let s = dictionary["confidence"] as? String, let v = Int(s) { return min(5, max(1, v)) }
            return 3
        }()

        let blocker = (dictionary["blocker"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let revisit = (dictionary["revisit"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let at = (dictionary["at"] as? String) ?? ""

        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let recordedAt = frac.date(from: at) ?? plain.date(from: at)

        if let id, !id.isEmpty {
            self.id = id
        } else {
            self.id = "\(taskId)-\(at)-\(title.hashValue)"
        }
        self.taskId = taskId
        self.taskTitle = title
        self.confidence = conf
        self.blocker = blocker
        self.revisit = revisit
        self.recordedAt = recordedAt
        self.atISO = at
    }
}

@Observable
final class AuthStore {
    var currentUser: UserProfile?
    var isAuthenticated = false
    var isLoading = false
    var error: String?

    private let api = APIClient.shared

    init() {
        #if DEBUG
        // Dev bypass: skip auth so you can test everything else
        isAuthenticated = true
        currentUser = UserProfile(
            id: "00000000-0000-0000-0000-000000000000",
            email: "dev@moretime.local",
            name: "Dev User",
            timezone: "America/New_York",
            preferences: nil,
            createdAt: nil
        )
        #else
        isAuthenticated = api.isAuthenticated
        #endif
    }

    func register(email: String, name: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let body = ["email": email, "name": name, "password": password]
            let response: AuthResponse = try await api.request("POST", path: "/auth/register", body: body, authenticated: false)
            api.setTokens(access: response.accessToken, refresh: response.refreshToken)
            currentUser = response.user
            isAuthenticated = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func login(email: String, password: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let body = ["email": email, "password": password]
            let response: AuthResponse = try await api.request("POST", path: "/auth/login", body: body, authenticated: false)
            api.setTokens(access: response.accessToken, refresh: response.refreshToken)
            currentUser = response.user
            isAuthenticated = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func logout() async {
        try? await api.request("POST", path: "/auth/logout") as Void
        api.clearTokens()
        currentUser = nil
        isAuthenticated = false
    }

    func fetchProfile() async {
        do {
            let user: UserProfile = try await api.request("GET", path: "/auth/me")
            currentUser = user
        } catch {
            // Token might be expired
            if case APIError.unauthorized = error {
                isAuthenticated = false
                api.clearTokens()
            }
        }
    }

    /// Merges into existing profile `preferences` and PATCHes `/auth/me` (server replaces whole JSON object).
    func updatePreferences(merging updates: [String: Any] = [:], removingKeys: Set<String> = []) async -> Bool {
        var merged = Self.preferencesDictionary(from: currentUser)
        for key in removingKeys {
            merged.removeValue(forKey: key)
        }
        for (key, value) in updates {
            merged[key] = value
        }
        let codablePrefs = merged.mapValues { AnyCodable($0) }

        struct PatchBody: Codable {
            var preferences: [String: AnyCodable]
        }

        do {
            let user: UserProfile = try await api.request("PATCH", path: "/auth/me", body: PatchBody(preferences: codablePrefs))
            currentUser = user
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private static let semesterPlanPreferenceKey = "semesterPlan"
    private static let learningDebriefsPreferenceKey = "learningDebriefs"
    private static let maxLearningDebriefsStored = 25

    /// Appends a learning debrief to `preferences.learningDebriefs` (capped, preserves other preference keys).
    func appendLearningDebrief(
        taskId: String,
        title: String,
        confidence: Int,
        blocker: String,
        revisit: String?,
    ) async -> Bool {
        var merged = Self.preferencesDictionary(from: currentUser)
        var list = Self.learningDebriefsArray(from: merged)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var revisitTrimmed = (revisit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if revisitTrimmed.count > 200 {
            revisitTrimmed = String(revisitTrimmed.prefix(200))
        }

        let clampedConfidence = min(5, max(1, confidence))
        let entry: [String: Any] = [
            "id": UUID().uuidString,
            "at": iso.string(from: Date()),
            "taskId": taskId,
            "taskTitle": title,
            "confidence": clampedConfidence,
            "blocker": String(blocker.prefix(80)),
            "revisit": revisitTrimmed,
        ]
        list.append(entry)
        if list.count > Self.maxLearningDebriefsStored {
            list = Array(list.suffix(Self.maxLearningDebriefsStored))
        }

        return await updatePreferences(merging: [Self.learningDebriefsPreferenceKey: list])
    }

    private static func learningDebriefsArray(from prefs: [String: Any]) -> [[String: Any]] {
        guard let raw = prefs[learningDebriefsPreferenceKey] else { return [] }
        if let arr = raw as? [[String: Any]] { return arr }
        if let arr = raw as? [Any] {
            return arr.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    /// Reflections saved after completing tasks, newest first.
    func learningDebriefEntries() -> [LearningDebriefEntry] {
        let raw = Self.learningDebriefsArray(from: Self.preferencesDictionary(from: currentUser))
        let entries = raw.compactMap { LearningDebriefEntry(dictionary: $0) }
        return entries.sorted { a, b in
            guard let da = a.recordedAt, let db = b.recordedAt else {
                return a.atISO > b.atISO
            }
            return da > db
        }
    }

    /// Removes all stored learning debriefs from profile preferences.
    func clearLearningDebriefs() async -> Bool {
        await updatePreferences(merging: [:], removingKeys: Set([Self.learningDebriefsPreferenceKey]))
    }

    /// Saves or clears the single persisted semester heat-map plan (JSON string in `preferences`).
    func persistSemesterPlan(_ plan: SemesterPlan?) async -> Bool {
        if let plan {
            guard let data = try? JSONEncoder().encode(plan),
                  let jsonString = String(data: data, encoding: .utf8) else { return false }
            return await updatePreferences(merging: [Self.semesterPlanPreferenceKey: jsonString])
        }
        return await updatePreferences(merging: [:], removingKeys: Set([Self.semesterPlanPreferenceKey]))
    }

    func semesterPlanFromPreferences() -> SemesterPlan? {
        let dict = Self.preferencesDictionary(from: currentUser)
        guard let raw = dict[Self.semesterPlanPreferenceKey] else { return nil }
        let jsonString: String? = {
            if let s = raw as? String { return s }
            if let s = raw as? NSString { return s as String }
            return nil
        }()
        guard let jsonString, let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SemesterPlan.self, from: data)
    }

    static func preferencesDictionary(from profile: UserProfile?) -> [String: Any] {
        guard let prefs = profile?.preferences else { return [:] }
        var out: [String: Any] = [:]
        for (key, any) in prefs {
            out[key] = any.value
        }
        return out
    }
}
