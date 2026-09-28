import Foundation
import MediaAccessibility
import MusicKit
import UIKit

/// Immutable selection captured before suspension. The live adapter requires the original MusicKit Song.
struct SystemMusicTrack {
    let id: MusicItemID
    let title: String
    let artistName: String
    let isrc: String?
    let duration: TimeInterval?
    let song: Song?
    init(song: Song) {
        id = song.id; title = song.title; artistName = song.artistName
        isrc = song.isrc; duration = song.duration; self.song = song
    }
    init(id: String, title: String) {
        self.id = MusicItemID(id); self.title = title; artistName = ""
        isrc = "fixture"; duration = 30; song = nil
    }
}

/// Deterministic suspension points for service tests. Injected adapters never claim MusicKit subscription validation.
@MainActor struct SystemMusicIO {
    var subscription: () async throws -> Bool
    var play: (SystemMusicTrack) async throws -> Void
    var pause: () -> Void
    var enabled: () -> Bool
    var foreground: () -> Bool
    var trackAvailable: (String) async -> Bool
    var playbackTime: () -> TimeInterval
    static var live: Self {
        Self(
            subscription: { try await MusicSubscription.current.canPlayCatalogContent },
            play: { track in
                guard let song = track.song else { throw NSError(domain: "PulseLoom.Music", code: 1) }
                let player = ApplicationMusicPlayer.shared
                player.queue = [song]
                try await player.play()
            },
            pause: { ApplicationMusicPlayer.shared.pause() },
            enabled: {
                if #available(iOS 18.0, *) { return MAMusicHapticsManager.shared.isActive }
                return false
            },
            foreground: { UIApplication.shared.applicationState == .active },
            trackAvailable: { isrc in
                if #available(iOS 18.0, *) {
                    return await withCheckedContinuation { continuation in
                        MAMusicHapticsManager.shared.checkHapticTrackAvailabilityForMedia(matchingCode: isrc) {
                            continuation.resume(returning: $0)
                        }
                    }
                }
                return false
            },
            playbackTime: { ApplicationMusicPlayer.shared.playbackTime })
    }
}
