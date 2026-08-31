// droid-host-patch: this file originally conflated "non-wasm" with "Apple device"
// (WebSocket receive() via URLSessionWebSocketTask + AuthenticationServices sign-in) and
// skipped the whole module on native non-Apple (Android), where neither assumption holds.
// Data/auth/AI (Milestone 2 — droid-host README) now build for Android too: the portable
// URLSession/_Kernel.request surface rides the SAME host-fetch bridge Milestone 1 wired
// (Render/Kernel.swift's droidhost_register_{fetch,request,ws}), so Cloud.collection(...)/
// Cloud.auth.signUp/Cloud.ai work unchanged. Only the two genuinely Apple-only pieces stay
// gated narrower below: CloudRealtime's WebSocket transport (now `arch(wasm32) ||
// os(Android)` routes through the portable _KernelWS bridge; real Apple non-wasm keeps
// URLSessionWebSocketTask) and the native Sign in with Apple / ASWebAuthenticationSession
// UI (stays `canImport(AuthenticationServices)` — Android has neither; signInWithApple/
// signInWithOAuth fall through to the SAME "no native bridge" path wasm takes, which
// currently means _AuthHostBridge's droid-host stub — see AuthBridge.swift; the browser
// consent UI's Android equivalent, e.g. Chrome Custom Tabs, is a documented follow-up).
#if arch(wasm32) || os(Android) || canImport(AuthenticationServices)
#if !EMBEDDED
import Foundation
// Device builds use the real AuthenticationServices framework for the native Apple sheet.
// On wasm/Android the OAuth flow goes through _AuthHostBridge (Render/AuthBridge.swift)
// instead, so no AS import is needed there — which is what lets Cloud's sign-in API live
// in this module and stay callable with just `import SwiftUI`.
//
// `&& !arch(wasm32) && !os(Android)` is LOAD-BEARING, not redundant with the intent above:
// the wasm build ships a LOCAL `AuthenticationServices` shim module that itself imports
// SwiftUI. On a CLEAN build SwiftUI compiles before that shim exists, so `canImport` is
// false and we skip the import (correct). But an INCREMENTAL build (the preview builder's
// persistent .build, or any warm cache) finds the shim already built → `canImport` flips
// true → importing it here forms a SwiftUI↔AuthenticationServices module cycle and the whole
// framework build aborts ("circular dependency between modules"). Excluding wasm/Android
// explicitly makes the build cache-INDEPENDENT (always matches the clean-build result) —
// device builds (arm64, real AS framework) are unaffected.
#if canImport(AuthenticationServices) && !arch(wasm32) && !os(Android)
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif
#endif

// Cloud — the managed backend for apps built with the playground. Auth + tables with
// zero server code, backed by the per-app Durable Object Worker (dactyl/apps). The wire
// is Supabase-shaped: POST /<app>/auth/v1/{signup,token}, GET/POST/PATCH/DELETE
// /<app>/rest/v1/<table>?col=eq.val. The Swift surface below stays stable:
//
//     try await Cloud.auth.signUp(username: "divy", password: "…")
//     let post = try await Cloud.collection("posts").add(["caption": "hi", "likes": 0])
//     let feed = try await Cloud.collection("posts").list()
//
// PORTABLE FILE — ships verbatim inside generated Xcode projects, compiling against
// Apple Foundation on iOS and our shims on wasm. Stay on the portable URLSession
// surface; wasm-only hooks live behind #if arch(wasm32). Mutable statics are
// nonisolated(unsafe) by design (the runtime is single-threaded on wasm).

public enum Cloud {
    nonisolated(unsafe) public static var appId = "playground"
    nonisolated(unsafe) public static var baseURL = "https://api.dactyl.dev"
    // Per-app publishable token for the AI gateway (Cloud.ai). Baked into the built app
    // by the build pipeline; the managed backend gates /ai/v1 on it. nil in bare previews.
    nonisolated(unsafe) public static var aiToken: String?
    public static func configure(appId: String, baseURL: String? = nil, aiToken: String? = nil) {
        Cloud.appId = appId
        if let baseURL { Cloud.baseURL = baseURL }
        if let aiToken { Cloud.aiToken = aiToken }
    }
    nonisolated(unsafe) public static let auth = CloudAuth()
    nonisolated(unsafe) public static let realtime = CloudRealtime()
    nonisolated(unsafe) public static let ai = CloudAI()
    public static func collection(_ name: String) -> CloudCollection { CloudCollection(name: name) }

    // Custom-scheme callback for the web OAuth flow (Google). ASWebAuthenticationSession
    // intercepts a redirect to this scheme; it mirrors the default bundle id so the same
    // value works whether or not the app overrides its bundle id. Matches the apps DO's
    // defaultBundleId() and platform/web defaultBundleId(). Public so the OAuth methods —
    // which live in the AuthenticationServices module to avoid a SwiftUI→AS dep cycle — see it.
    public static var authScheme: String {
        "com.dactyl.app" + appId.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

// Realtime: WebSocket channels for multiplayer — broadcast messages + live presence.
//   let ch = Cloud.realtime.channel("room")
//   ch.onBroadcast { event, data in … }.onPresence { players in … }
//   ch.send(event: "move", ["x": x]);  ch.track(["score": score])
public struct CloudPresence: Identifiable {
    public let id: String
    public let name: String
    public let state: [String: Any]
}

public final class CloudRealtime {
    public func channel(_ name: String) -> CloudChannel { CloudChannel(name: name) }
}

public final class CloudChannel {
    public let name: String
    private var onBroadcastFn: ((String, [String: Any]) -> Void)?
    private var onPresenceFn: (([CloudPresence]) -> Void)?
    private var presence: [String: CloudPresence] = [:]
    // droid-host-patch: Android has no URLSessionWebSocketTask (corelibs-foundation gap),
    // so it rides the SAME portable _KernelWS bridge wasm uses (Milestone 1's
    // droidhost_register_ws) rather than the real-Apple-only URLSessionWebSocketTask path.
    #if arch(wasm32) || os(Android)
    private var wsId: Int32 = 0
    #else
    private var task: URLSessionWebSocketTask?
    #endif

    init(name: String) {
        self.name = name
        connect()
    }

    private var wsURL: String {
        let base = Cloud.baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        var u = "\(base)/\(Cloud.appId)/realtime/v1?channel=\(name)"
        if let t = Cloud.auth.token { u += "&token=\(t)" }
        return u
    }

    private func connect() {
        #if arch(wasm32) || os(Android)
        wsId = _KernelWS.open(wsURL) { [weak self] event, msg in self?.onEvent(event, msg) }
        #else
        guard let url = URL(string: wsURL) else { return }
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        receive()
        #endif
    }

    #if !arch(wasm32) && !os(Android)
    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            if case .success(let m) = result {
                if case .string(let s) = m { self.onEvent(2, s) }
                self.receive()
            }
        }
    }
    #endif

    private func onEvent(_ event: Int32, _ msg: String) {
        guard event == 2, let data = msg.data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        switch j["type"] as? String {
        case "broadcast":
            onBroadcastFn?(j["event"] as? String ?? "", j["payload"] as? [String: Any] ?? [:])
        case "presence_sync":
            presence = [:]
            for u in (j["users"] as? [[String: Any]] ?? []) { addPresence(u) }
            onPresenceFn?(Array(presence.values))
        case "presence_join", "presence_update":
            if let u = j["user"] as? [String: Any] { addPresence(u); onPresenceFn?(Array(presence.values)) }
        case "presence_leave":
            if let id = (j["user"] as? [String: Any])?["id"] as? String {
                presence[id] = nil
                onPresenceFn?(Array(presence.values))
            }
        default: break
        }
    }

    private func addPresence(_ u: [String: Any]) {
        guard let id = u["id"] as? String else { return }
        presence[id] = CloudPresence(id: id, name: u["name"] as? String ?? "", state: u["state"] as? [String: Any] ?? [:])
    }

    private func emit(_ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        #if arch(wasm32) || os(Android)
        _KernelWS.send(wsId, s)
        #else
        task?.send(.string(s)) { _ in }
        #endif
    }

    @discardableResult public func onBroadcast(_ h: @escaping (String, [String: Any]) -> Void) -> CloudChannel {
        onBroadcastFn = h
        return self
    }
    @discardableResult public func onPresence(_ h: @escaping ([CloudPresence]) -> Void) -> CloudChannel {
        onPresenceFn = h
        return self
    }
    public func send(event: String, _ payload: [String: Any] = [:]) {
        emit(["type": "broadcast", "event": event, "payload": payload])
    }
    public func track(_ state: [String: Any]) {
        emit(["type": "presence", "state": state])
    }
    public func leave() {
        #if arch(wasm32) || os(Android)
        _KernelWS.close(wsId)
        #else
        task?.cancel()
        #endif
    }
}

// LocalizedError matters: without it `error.localizedDescription` bridges to the generic
// NSError string ("The operation couldn't be completed. (SwiftUI.CloudError error 1.)") and
// the real reason is lost — which is what app code and users actually surface in a catch
// block. CustomStringConvertible alone only covers String(describing:)/print. (#1101)
public struct CloudError: Error, CustomStringConvertible, LocalizedError {
    public let message: String
    public let status: Int
    public var description: String { message }
    public var errorDescription: String? { message }
    public init(message: String, status: Int) { self.message = message; self.status = status }
}

public struct CloudUser: Identifiable, Hashable {
    public let id: String
    public let username: String
}

/// One row: a bag of JSON fields plus identity/ownership metadata. Typed accessors keep
/// view code short: `doc.string("caption")`, `doc.int("likes")`.
public struct CloudDocument: Identifiable {
    public let id: String
    public let owner: String?
    public let ownerName: String?
    public let createdAt: String
    public let updatedAt: String
    public let fields: [String: Any]

    public subscript(key: String) -> Any? { fields[key] }
    public func string(_ key: String) -> String? { fields[key] as? String }
    public func int(_ key: String) -> Int? { (fields[key] as? Int) ?? (fields[key] as? Double).map(Int.init) }
    public func double(_ key: String) -> Double? { (fields[key] as? Double) ?? (fields[key] as? Int).map(Double.init) }
    public func bool(_ key: String) -> Bool? { fields[key] as? Bool }

    // `forKey:`-labelled aliases mirroring UserDefaults/NSDictionary, the shape generated
    // code (and ported iOS code) naturally reaches for. They delegate to the positional
    // accessors above (`integer(forKey:)` to `int(_:)`, matching UserDefaults' naming).
    public func integer(forKey key: String) -> Int? { int(key) }
    public func string(forKey key: String) -> String? { string(key) }
    public func double(forKey key: String) -> Double? { double(key) }
    public func bool(forKey key: String) -> Bool? { bool(key) }
    public func object(forKey key: String) -> Any? { fields[key] }
    public var isMine: Bool { owner != nil && owner == Cloud.auth.currentUser?.id }

    private static let system: Set<String> = ["id", "user_id", "owner_name", "created_at", "updated_at"]

    init(_ row: [String: Any]) {
        id = row["id"] as? String ?? ""
        owner = row["user_id"] as? String
        ownerName = row["owner_name"] as? String
        createdAt = row["created_at"] as? String ?? ""
        updatedAt = row["updated_at"] as? String ?? ""
        fields = row.filter { !CloudDocument.system.contains($0.key) }
    }
}

public final class CloudAuth {
    var token: String?
    public private(set) var currentUser: CloudUser?
    public var isSignedIn: Bool { token != nil }

    @discardableResult
    public func signUp(username: String, password: String) async throws -> CloudUser {
        try await session("auth/v1/signup", body: ["email": username, "password": password])
    }
    @discardableResult
    public func signIn(username: String, password: String) async throws -> CloudUser {
        try await session("auth/v1/token?grant_type=password", body: ["email": username, "password": password])
    }
    public func signOut() async {
        _ = try? await _cloudObject("auth/v1/logout", method: "POST")
        token = nil
        currentUser = nil
    }

    /// Finish an OAuth sign-in: POST the verified credential (Apple id_token) or the broker's
    /// single-use code to the auth endpoint and adopt the returned session. The provider dance
    /// (ASWebAuthenticationSession / Sign in with Apple) lives in the AuthenticationServices
    /// module — which depends on SwiftUI — so this stays here and is called back into.
    @discardableResult
    public func _completeOAuth(path: String, body: [String: Any]) async throws -> CloudUser {
        try await session(path, body: body)
    }

    private func session(_ path: String, body: [String: Any]) async throws -> CloudUser {
        let json = try await _cloudObject(path, method: "POST", body: body)
        guard let t = json["access_token"] as? String, let u = json["user"] as? [String: Any],
              let id = u["id"] as? String else {
            throw CloudError(message: "malformed auth response", status: 0)
        }
        token = t
        let user = CloudUser(id: id, username: u["email"] as? String ?? "")
        currentUser = user
        #if arch(wasm32) || os(Android)
        _Scheduler.setNeedsRender()
        #endif
        return user
    }
}

public struct CloudCollection {
    public let name: String

    /// Create a row (requires sign-in). Fields are any JSON-encodable values.
    @discardableResult
    public func add(_ fields: [String: Any]) async throws -> CloudDocument {
        let rows = try await _cloudArray("rest/v1/\(name)", method: "POST", body: fields)
        guard let first = rows.first else { throw CloudError(message: "insert returned nothing", status: 0) }
        return CloudDocument(first)
    }
    /// Newest-first. `mine: true` filters to the signed-in user's rows.
    public func list(limit: Int = 50, mine: Bool = false, before: String? = nil) async throws -> [CloudDocument] {
        var q = "?order=created_at.desc&limit=\(limit)"
        if mine, let uid = Cloud.auth.currentUser?.id { q += "&user_id=eq.\(uid)" }
        if let before { q += "&created_at=lt.\(before)" }
        return try await _cloudArray("rest/v1/\(name)\(q)", method: "GET").map(CloudDocument.init)
    }
    public func get(_ id: String) async throws -> CloudDocument {
        let rows = try await _cloudArray("rest/v1/\(name)?id=eq.\(id)&limit=1", method: "GET")
        guard let first = rows.first else { throw CloudError(message: "not found", status: 404) }
        return CloudDocument(first)
    }
    /// Merge-patch fields into a row you own.
    @discardableResult
    public func update(_ id: String, _ fields: [String: Any]) async throws -> CloudDocument {
        let rows = try await _cloudArray("rest/v1/\(name)?id=eq.\(id)", method: "PATCH", body: fields)
        guard let first = rows.first else { throw CloudError(message: "not found or not yours", status: 404) }
        return CloudDocument(first)
    }
    public func delete(_ id: String) async throws {
        _ = try await _cloudArray("rest/v1/\(name)?id=eq.\(id)", method: "DELETE")
    }
}

// Cloud.ai — managed LLM for your app, NO API key. OpenAI-compatible chat/completions,
// proxied through the app's backend and billed to the app owner. `ask` is the one-liner;
// `chat` takes a message list + an optional model (any slug the gateway allows —
// e.g. "openai/gpt-5.6-sol"; omit for the cheap default).
//
//     let reply = try await Cloud.ai.ask("Write a haiku about tides")
//     let summary = try await Cloud.ai.chat([
//         .init(role: "system", content: "You summarize in one sentence."),
//         .init(role: "user", content: article),
//     ], model: "openai/gpt-5.6-sol")
public final class CloudAI {
    public struct Message {
        public let role: String
        public let content: String
        // Attached images for MULTIMODAL (vision) requests — a user photo the model reasons
        // about ("what's in this fridge?", "grade my handwriting"). Encoded as base64 data
        // URIs and sent in OpenAI's `content: [{type:text},{type:image_url}]` shape (#1357).
        let images: [Data]
        public init(role: String, content: String) { self.role = role; self.content = content; self.images = [] }
        public init(role: String, content: String, images: [Data]) {
            self.role = role; self.content = content; self.images = images
        }

        // The wire form: a plain string when there are no images, else the multimodal array.
        var _wireContent: Any {
            if images.isEmpty { return content }
            var parts: [[String: Any]] = [["type": "text", "text": content]]
            for data in images {
                parts.append(["type": "image_url", "image_url": ["url": _dataURI(data)]])
            }
            return parts
        }
    }

    /// One-shot: send a prompt, get the assistant's text back.
    public func ask(_ prompt: String, model: String? = nil) async throws -> String {
        try await chat([Message(role: "user", content: prompt)], model: model)
    }

    /// One-shot VISION: send a prompt grounded on a user photo, get the assistant's text back.
    public func ask(_ prompt: String, image: Data, model: String? = nil) async throws -> String {
        try await chat([Message(role: "user", content: prompt, images: [image])], model: model)
    }

    /// Full chat completion (multimodal-aware). Returns the assistant message text.
    public func chat(_ messages: [Message], model: String? = nil) async throws -> String {
        var body: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0._wireContent] },
        ]
        if let model { body["model"] = model }
        let json = try await _cloudAISend(body)
        let choices = json["choices"] as? [[String: Any]]
        guard let msg = (choices?.first?["message"] as? [String: Any])?["content"] as? String else {
            throw CloudError(message: "malformed AI response", status: 0)
        }
        return msg
    }

    /// Generate an image from a text prompt, optionally GROUNDED on a reference photo
    /// (image-to-image — e.g. "redesign this room in a Scandinavian style"). Returns the
    /// generated PNG bytes. Hits the managed gateway's OpenAI-compatible images endpoint
    /// (`images/edits` when a reference is supplied, else `images/generations`) (#1357).
    public func image(_ prompt: String, referenceImage: Data? = nil, model: String? = nil) async throws -> Data {
        var body: [String: Any] = ["prompt": prompt, "response_format": "b64_json", "n": 1]
        if let model { body["model"] = model }
        if let referenceImage { body["image"] = _dataURI(referenceImage) }
        let path = referenceImage == nil ? "ai/v1/images/generations" : "ai/v1/images/edits"
        let json = try await _cloudAISendPath(path, body)
        let items = json["data"] as? [[String: Any]]
        if let b64 = items?.first?["b64_json"] as? String, let bytes = Data(base64Encoded: b64) { return bytes }
        if let urlStr = items?.first?["url"] as? String, let url = URL(string: urlStr),
           let (bytes, _) = try? await URLSession.shared.data(from: url) { return bytes }
        throw CloudError(message: "malformed image response", status: 0)
    }
}

// MARK: - Names the agent reaches for (build-failure telemetry, 90d)
//
// These are NOT new API — every one forwards to the canonical member below it. They exist
// because the agent writes a plausible-but-wrong name often enough to break real builds,
// and a failed build costs a user a round-trip while a deprecation warning costs nothing.
// Counts are DISTINCT USERS who hit the name as a hard build error (PostHog project 444467,
// `has no member` / `cannot find in scope`, 90-day window read 24 Aug 2026).
//
// The deprecation message is the point: the build now SUCCEEDS and the warning reaches the
// agent through compileWarnings, so the next edit converges on the real name instead of
// guessing again. Delete a shim once its telemetry goes quiet.

/// `CloudAI.Message` is nested, so the flattened spelling doesn't resolve — 18 users.
@available(*, deprecated, renamed: "CloudAI.Message")
public typealias CloudAIMessage = CloudAI.Message

/// Same flattening, chat-shaped — 2 users.
@available(*, deprecated, renamed: "CloudAI.Message")
public typealias CloudAIChatMessage = CloudAI.Message

extension CloudAI {
    /// OpenAI-shaped muscle memory for `ask` — 2 users.
    @available(*, deprecated, renamed: "ask(_:model:)")
    public func complete(_ prompt: String, model: String? = nil) async throws -> String {
        try await ask(prompt, model: model)
    }

    /// `Cloud.ai.message(…)` for `ask` — 4 users.
    @available(*, deprecated, renamed: "ask(_:model:)")
    public func message(_ prompt: String, model: String? = nil) async throws -> String {
        try await ask(prompt, model: model)
    }
}

extension CloudUser {
    /// The account's one human-readable name is `username`; the agent reaches for the two
    /// spellings other platforms use — `displayName` (3 users) and `name` (2).
    @available(*, deprecated, renamed: "username")
    public var displayName: String { username }

    @available(*, deprecated, renamed: "username")
    public var name: String { username }
}

// A base64 data URI for image bytes, with the MIME sniffed from the magic bytes (PNG/JPEG/
// GIF/WebP), defaulting to PNG — what the OpenAI multimodal/images wire format expects.
private func _dataURI(_ data: Data) -> String {
    let mime: String
    let b = [UInt8](data.prefix(12))
    if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { mime = "image/jpeg" }
    else if b.count >= 4, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { mime = "image/gif" }
    else if b.count >= 12, b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { mime = "image/webp" }
    else { mime = "image/png" }
    return "data:\(mime);base64,\(data.base64EncodedString())"
}

// Bound every Cloud call so it fails LEGIBLY instead of hanging when the managed backend
// is unreachable or stalls (denoland/dactyl#701: an auth write that never answered parked
// signUp's `await` forever). Reads already return within this budget, so it never regresses
// a working call; a stalled write now throws a CloudError after this many seconds.
private let _cloudTimeout: TimeInterval = 20

// Shared transport: JSON in, bearer token when signed in, server error message surfaced.
private func _cloudSend(_ path: String, method: String, body: [String: Any]?) async throws -> (Any, Int) {
    guard let url = URL(string: "\(Cloud.baseURL)/\(Cloud.appId)/\(path)") else {
        throw CloudError(message: "bad url", status: 0)
    }
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.timeoutInterval = _cloudTimeout
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let t = Cloud.auth.token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
    if let body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
    let data: Data
    let resp: URLResponse
    do {
        (data, resp) = try await URLSession.shared.data(for: req)
    } catch {
        // A thrown URLError here is the transport giving up (timed out / could not reach the
        // host) — surface it as a CloudError so the caller (e.g. Cloud.auth.signUp) throws a
        // legible failure instead of the request hanging indefinitely.
        throw CloudError(
            message: "could not reach the backend — the request timed out. Check the connection and try again.",
            status: 0)
    }
    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
    let json = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
    guard (200..<300).contains(status) else {
        let msg = (json as? [String: Any])?["error"] as? String ?? "request failed (\(status))"
        throw CloudError(message: msg, status: status)
    }
    return (json, status)
}

func _cloudObject(_ path: String, method: String, body: [String: Any]? = nil) async throws -> [String: Any] {
    let (json, _) = try await _cloudSend(path, method: method, body: body)
    return json as? [String: Any] ?? [:]
}

func _cloudArray(_ path: String, method: String, body: [String: Any]? = nil) async throws -> [[String: Any]] {
    let (json, _) = try await _cloudSend(path, method: method, body: body)
    return json as? [[String: Any]] ?? []
}

// AI gateway transport: authenticates with the app's publishable Cloud.aiToken (NOT the
// user session), and allows a longer budget than BaaS calls since model latency exceeds 20s.
private let _cloudAITimeout: TimeInterval = 60
func _cloudAISend(_ body: [String: Any]) async throws -> [String: Any] {
    try await _cloudAISendPath("ai/v1/chat/completions", body)
}
// Same AI-gateway transport as `_cloudAISend`, parameterized by endpoint path so the
// chat, vision, and image-generation calls share one authenticated request path (#1357).
func _cloudAISendPath(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
    guard let token = Cloud.aiToken, !token.isEmpty else {
        throw CloudError(message: "Cloud.ai is not configured for this app", status: 0)
    }
    guard let url = URL(string: "\(Cloud.baseURL)/\(Cloud.appId)/\(path)") else {
        throw CloudError(message: "bad url", status: 0)
    }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.timeoutInterval = _cloudAITimeout
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let data: Data
    let resp: URLResponse
    do {
        (data, resp) = try await URLSession.shared.data(for: req)
    } catch {
        throw CloudError(message: "could not reach the AI backend — the request timed out.", status: 0)
    }
    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard (200..<300).contains(status) else {
        let msg = (json["error"] as? [String: Any])?["message"] as? String
            ?? (json["error"] as? String) ?? "AI request failed (\(status))"
        throw CloudError(message: msg, status: status)
    }
    return json
}

#if arch(wasm32) || os(Android)
/// Host hook: the playground passes the current project name at mount so every app gets
/// its own backend namespace without any code. (On iOS the generated App.swift calls
/// Cloud.configure(appId:) instead.) droid-host-patch: also exported unconditionally on
/// Android (@_cdecl, not gated by @_expose(wasm,...) which is wasm-only) — the host has
/// no generated App.swift/init() to call Cloud.configure(appId:) from (no SwiftUI `App`
/// lifecycle at all; Entry.swift is a bare renderView() @_cdecl), so it calls this from
/// the stamp contract's assets/app.json {appId} the same way sdk/runtime.mjs's
/// opts.appId does for the browser preview (see droid-host/README's stamp-apk.sh notes).
@_expose(wasm, "pp_set_app_id") @_cdecl("pp_set_app_id")
public func pp_set_app_id(_ ptr: UnsafeMutableRawPointer, _ len: Int32) {
    let bytes = [UInt8](UnsafeRawBufferPointer(start: ptr, count: Int(len)))
    ptr.deallocate()
    let s = String(decoding: bytes, as: UTF8.self)
    if !s.isEmpty { Cloud.appId = s }
}

/// Host hook: the preview passes the app's publishable AI token at mount (parallel to
/// pp_set_app_id) so Cloud.ai works in the browser preview without baking it into source.
@_expose(wasm, "pp_set_ai_token") @_cdecl("pp_set_ai_token")
public func pp_set_ai_token(_ ptr: UnsafeMutableRawPointer, _ len: Int32) {
    let bytes = [UInt8](UnsafeRawBufferPointer(start: ptr, count: Int(len)))
    ptr.deallocate()
    let s = String(decoding: bytes, as: UTF8.self)
    if !s.isEmpty { Cloud.aiToken = s }
}
#endif

// ── Cloud OAuth sign-in ──────────────────────────────────────────────────────
// Zero per-app setup: the backend brokers against dactyl-owned Google/Apple credentials,
// so these work in the browser preview AND in a shipped IPA. Callable with just
// `import SwiftUI` — the wasm flow uses _AuthHostBridge; device uses the native sheet.
extension CloudAuth {
    /// Sign in with Apple — native sheet on device, hosted web consent in the preview.
    @discardableResult
    public func signInWithApple() async throws -> CloudUser {
        #if arch(wasm32) || os(Android)
        // No native Apple sheet in the browser preview OR on Android (no
        // AuthenticationServices there at all) — use the same hosted broker flow as
        // Google (real Apple web consent) so sign-in works there too.
        return try await signInWithOAuth(provider: "apple")
        #else
        do {
            var flow: _AppleAuthFlow?
            let cred: ASAuthorizationAppleIDCredential = try await withCheckedThrowingContinuation { cont in
                flow = _AppleAuthFlow(cont) // retained by this scope until the await resumes
                flow?.start()
            }
            flow = nil
            guard let data = cred.identityToken, let idToken = String(data: data, encoding: .utf8) else {
                throw CloudError(message: "no Apple identity token", status: 0)
            }
            return try await _completeOAuth(path: "auth/v1/grant",
                                            body: ["provider": "apple", "id_token": idToken])
        } catch let err as ASAuthorizationError where err.code == .canceled {
            throw err
        } catch {
            // Free-signed installs (companion/ad-hoc, personal team) cannot carry the
            // applesignin entitlement — Apple reserves that capability for paid teams — so
            // the native sheet fails immediately (ASAuthorizationError 1000) even though the
            // app installed fine. The hosted broker needs no entitlement: fall back to the
            // same web consent the browser preview uses so sign-in still completes on device.
            // A user cancel is rethrown above, not retried through the web flow.
            return try await signInWithOAuth(provider: "apple")
        }
        #endif
    }

    /// Sign in with Google via the hosted broker (ASWebAuthenticationSession → one-time code).
    @discardableResult
    public func signInWithGoogle() async throws -> CloudUser {
        try await signInWithOAuth(provider: "google")
    }

    /// Generic broker-backed web OAuth. Opens the provider consent, captures the single-use
    /// `code` on the app's callback scheme, exchanges it for a session.
    @discardableResult
    public func signInWithOAuth(provider: String) async throws -> CloudUser {
        let scheme = Cloud.authScheme
        let authURL = "\(Cloud.baseURL)/auth/v1/authorize?provider=\(provider)"
            + "&app=\(Cloud.appId)&redirect=\(scheme)://auth-callback"
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            #if arch(wasm32) || os(Android)
            // droid-host-patch: Android has no ASWebAuthenticationSession either — rides the
            // SAME _AuthHostBridge hook the browser preview uses (Render/AuthBridge.swift);
            // droid-host's Android-side host.webAuthStart implementation (Custom Tabs +
            // redirect intent-filter) is a documented follow-up (see droid-host/README) —
            // until wired, _AuthHostBridge's droid-host stub delivers nothing (no crash,
            // matches the mission's legible-degradation contract), so sign-in throws a
            // "sign-in canceled"-shaped CloudError instead of hanging.
            _AuthHostBridge.startWebAuth(url: authURL, scheme: scheme, ephemeral: false) { url, error in
                if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? CloudError(message: "sign-in canceled", status: 0)) }
            }
            #else
            guard let url = URL(string: authURL) else {
                cont.resume(throwing: CloudError(message: "bad authorize url", status: 0)); return
            }
            var session: ASWebAuthenticationSession?
            session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { cbURL, error in
                session = nil
                if let cbURL { cont.resume(returning: cbURL) }
                else { cont.resume(throwing: error ?? CloudError(message: "sign-in canceled", status: 0)) }
            }
            session?.presentationContextProvider = _WebAuthAnchor.shared
            if session?.start() != true {
                cont.resume(throwing: CloudError(message: "could not start sign-in", status: 0))
            }
            #endif
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw CloudError(message: "no code in callback", status: 0)
        }
        return try await _completeOAuth(path: "auth/v1/token?grant_type=oauth_code",
                                        body: ["code": code])
    }

    #if arch(wasm32) || os(Android)
    /// The broker OAuth authorize URL + callback scheme for `provider`, and a helper to
    /// finish sign-in from a captured callback URL. Split out of `signInWithOAuth` so a
    /// SYNCHRONOUS caller (droid host — see AuthenticationServices/SignInWithApple.swift)
    /// can open the browser on the tap thread instead of inside an `async` body that a
    /// detached Task must drain (which the droid runtime does not reliably do — see the
    /// droid-host CAVEAT in Render/Runtime.swift). The engine-internal spawn/bridge live in
    /// the AuthenticationServices shim (not copied to device), NOT here: this file IS copied
    /// verbatim into native Xcode projects, so it must reference no engine-only helpers.
    public func _oauthAuthorizeURL(provider: String) -> (url: String, scheme: String) {
        let scheme = Cloud.authScheme
        let url = "\(Cloud.baseURL)/auth/v1/authorize?provider=\(provider)"
            + "&app=\(Cloud.appId)&redirect=\(scheme)://auth-callback"
        return (url, scheme)
    }

    /// Exchange the single-use `code` from an OAuth callback URL for a session. Async (the
    /// token POST is), but reachable only AFTER the browser redirect returns — by which point
    /// the app has resumed, the lifecycle point at which host async progresses.
    @discardableResult
    public func _completeOAuthCallback(_ callback: URL) async throws -> CloudUser {
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw CloudError(message: "no code in callback", status: 0)
        }
        return try await _completeOAuth(path: "auth/v1/token?grant_type=oauth_code",
                                        body: ["code": code])
    }
    #endif

    #if canImport(AuthenticationServices) && !arch(wasm32) && !os(Android)
    /// Finish a Sign in with Apple started by SignInWithAppleButton — hand its
    /// `onCompletion` Result here to verify the credential server-side and adopt the session.
    @discardableResult
    public func completeSignInWithApple(_ authorization: ASAuthorization) async throws -> CloudUser {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = cred.identityToken,
              let idToken = String(data: data, encoding: .utf8) else {
            throw CloudError(message: "no Apple identity token", status: 0)
        }
        return try await _completeOAuth(path: "auth/v1/grant",
                                        body: ["provider": "apple", "id_token": idToken])
    }
    #endif
}

#if canImport(AuthenticationServices) && !arch(wasm32) && !os(Android)
// Native Sign in with Apple plumbing (device only). NSObject base satisfies the
// NSObjectProtocol-rooted delegate protocols; self-managed lifetime around the continuation.
final class _AppleAuthFlow: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private let cont: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>
    private var controller: ASAuthorizationController?
    private var done = false

    init(_ cont: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) { self.cont = cont }

    func start() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let c = ASAuthorizationController(authorizationRequests: [request])
        c.delegate = self
        c.presentationContextProvider = self
        controller = c
        c.performRequests()
    }

    private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        if done { return }
        done = true
        controller = nil
        switch result {
        case .success(let cred): cont.resume(returning: cred)
        case .failure(let err): cont.resume(throwing: err)
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        if let cred = authorization.credential as? ASAuthorizationAppleIDCredential {
            finish(.success(cred))
        } else {
            finish(.failure(CloudError(message: "unexpected Apple credential", status: 0)))
        }
    }
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        finish(.failure(error))
    }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        _keyAnchor()
    }
}

final class _WebAuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = _WebAuthAnchor()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        _keyAnchor()
    }
}

// The app's key window — the anchor both AS presentation providers need on device.
func _keyAnchor() -> ASPresentationAnchor {
    #if canImport(UIKit)
    return UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first ?? UIWindow()
    #else
    return NSObject()
    #endif
}
#endif

#endif // !EMBEDDED
#endif // arch(wasm32) || canImport(AuthenticationServices) — droid-host-patch
