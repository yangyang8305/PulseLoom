import Combine
import Foundation
import MediaAccessibility
import MediaPlayer
import MusicKit
import PulseLoomCore
import UIKit

/// Apple's system-authored Music Haptics path is separate from local PCM mapping.
/// Catalog entitlement, track availability and the system accessibility switch all matter.
@MainActor final class SystemMusicService: ObservableObject {
    @Published private(set) var authorized = false
    @Published private(set) var songs: [Song] = []
    @Published private(set) var selected: SystemMusicTrack?
    @Published private(set) var trackAvailable = false
    @Published private(set) var systemEnabled = false
    @Published private(set) var playing = false
    @Published var error: String?
    @Published var searching = false
    private var observer: NSObjectProtocol?
    private var playbackObserver: AnyCancellable?
    private var choiceGeneration = UUID(), searchGeneration = UUID()
    private var ownsPlayback = false
    private var requestGeneration = UUID()
    @Published private(set) var startInFlight = false
    var willPlay: (() -> Void)?
    private let io: SystemMusicIO
    init(io: SystemMusicIO? = nil) {
        self.io = io ?? .live
        systemEnabled = self.io.enabled()
        // Only live instances subscribe to external framework publishers.
        guard io == nil else { return }
        authorized = MusicAuthorization.currentStatus == .authorized
        if #available(iOS 18.0, *) {
            systemEnabled = MAMusicHapticsManager.shared.isActive
            observer = NotificationCenter.default.addObserver(
                forName: MAMusicHapticsManager.activeStatusDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.systemEnabled = MAMusicHapticsManager.shared.isActive
                    if !self.systemEnabled { self.pause() }
                }
            }
        }
        playbackObserver = ApplicationMusicPlayer.shared.state.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                guard let self, self.ownsPlayback else { return }
                self.playing = ApplicationMusicPlayer.shared.state.playbackStatus == .playing
                self.updateNowPlaying()
            }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func authorize() async {
        authorized = await MusicAuthorization.request() == .authorized
        if !authorized { error = NSLocalizedString("music.denied", comment: "") }
    }
    func search(_ query: String) async {
        guard authorized, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let generation = UUID()
        searchGeneration = generation
        searching = true
        defer { if searchGeneration == generation { searching = false } }
        do {
            // Consume MusicKit's non-Sendable response away from the UI actor.
            // Only framework-defined Sendable Song values cross this boundary.
            let result = try await SystemMusicCatalog.songs(matching: query)
            guard searchGeneration == generation, authorized, !Task.isCancelled else { return }
            songs = result
        } catch { if searchGeneration == generation { self.error = error.localizedDescription } }
    }
    func choose(_ song: Song) async { await choose(SystemMusicTrack(song: song)) }
    func choose(_ song: SystemMusicTrack) async {
        pause()
        selected = song
        trackAvailable = false
        let generation = UUID()
        choiceGeneration = generation
        if let isrc = song.isrc {
            let available = await io.trackAvailable(isrc)
            guard generation == choiceGeneration else { return }
            trackAvailable = available
        }
    }
    func play() async throws {
        // A canceled framework start may still complete. Do not let a newer start
        // overlap it: cleanup of the old operation must never pause a new song.
        guard !startInFlight else {
            throw LoomError.unavailable("The previous music request is still ending. Try again shortly.")
        }
        guard let song = selected else { return }
        guard systemEnabled, trackAvailable, io.enabled() else {
            throw LoomError.unavailable(NSLocalizedString("music.systemUnavailable", comment: ""))
        }
        pause()
        let request = UUID()
        requestGeneration = request
        let choice = choiceGeneration
        startInFlight = true
        defer { startInFlight = false }
        do {
            let canPlay = try await io.subscription()
            guard isCurrent(request, choice: choice), !Task.isCancelled else { return }
            guard io.foreground() else {
                throw LoomError.unavailable(NSLocalizedString("error.foreground", comment: ""))
            }
            guard systemEnabled, trackAvailable, io.enabled() else {
                throw LoomError.unavailable(NSLocalizedString("music.systemUnavailable", comment: ""))
            }
            guard canPlay else {
                throw LoomError.unavailable(NSLocalizedString("music.subscription", comment: ""))
            }
            willPlay?()
            // Source acquisition is synchronous but may reenter pause/choose.
            guard isCurrent(request, choice: choice), !Task.isCancelled else { return }
            ownsPlayback = true
            try await io.play(song)
            guard isCurrent(request, choice: choice), !Task.isCancelled,
                io.foreground(), io.enabled(), systemEnabled, trackAvailable
            else {
                // Compensate a framework completion arriving after the immediate Stop.
                finishOwnedPlayback(forcePause: true)
                return
            }
            playing = true
            updateNowPlaying()
        } catch {
            finishOwnedPlayback(forcePause: ownsPlayback)
            if !isCurrent(request, choice: choice) || Task.isCancelled { return }
            throw error
        }
    }
    private func isCurrent(_ request: UUID, choice: UUID) -> Bool {
        requestGeneration == request && choiceGeneration == choice
    }
    private func finishOwnedPlayback(forcePause: Bool) {
        if forcePause { io.pause() }
        playing = false
        if ownsPlayback || forcePause { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        ownsPlayback = false
    }
    private func updateNowPlaying() {
        guard ownsPlayback, let selected else { return }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = selected.title
        info[MPMediaItemPropertyArtist] = selected.artistName
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = io.playbackTime()
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        if let duration = selected.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if #available(iOS 18.0, *), let isrc = selected.isrc {
            info[MPNowPlayingInfoPropertyInternationalStandardRecordingCode] = isrc
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    func pause() {
        // Invalidate even before a subscription check or player start has returned.
        requestGeneration = UUID()
        finishOwnedPlayback(forcePause: ownsPlayback)
    }
}
