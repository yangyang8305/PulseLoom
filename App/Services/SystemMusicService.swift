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
        do {
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = 20
            let result = try await request.response()
            guard searchGeneration == generation else { return }
            songs = Array(result.songs)
        } catch { if searchGeneration == generation { self.error = error.localizedDescription } }
        if searchGeneration == generation { searching = false }
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
        guard let song = selected else { return }
        guard systemEnabled, trackAvailable else {
            throw LoomError.unavailable(NSLocalizedString("music.systemUnavailable", comment: ""))
        }
        let generation = choiceGeneration
        let canPlay = try await io.subscription()
        guard generation == choiceGeneration else { return }
        guard io.foreground() else {
            throw LoomError.unavailable(NSLocalizedString("error.foreground", comment: ""))
        }
        guard canPlay else {
            throw LoomError.unavailable(NSLocalizedString("music.subscription", comment: ""))
        }
        willPlay?()
        ownsPlayback = true
        do {
            try await io.play(song)
            guard io.foreground() else {
                pause()
                return
            }
            playing = true
            updateNowPlaying()
        } catch {
            ownsPlayback = false
            throw error
        }
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
        guard ownsPlayback else { return }
        io.pause()
        playing = false
        updateNowPlaying()
        ownsPlayback = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
}
