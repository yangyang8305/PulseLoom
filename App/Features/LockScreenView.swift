import SwiftUI
import UIKit

/// Lock mode: a black screen that swallows every touch while output continues in the foreground.
/// Brightness drops to the minimum and the proximity sensor is on, so the display goes fully dark
/// in a pocket. A triple tap anywhere unlocks. The hint line stays visible but very dim.
struct LockScreenView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                Spacer()
                Text(T("lock.hint"))
                    .font(.footnote)
                    .foregroundStyle(Color(white: 0.42))
                    .padding(.bottom, 28)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 3) { app.unlock() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(T("lock.hint"))
        .accessibilityAction { app.unlock() }
        .accessibilityIdentifier("lockScreen")
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

/// Screen brightness and proximity handling for lock mode; restores the user's brightness on exit.
@MainActor final class LockMode {
    private var savedBrightness: CGFloat?
    func enter() {
        if savedBrightness == nil { savedBrightness = UIScreen.main.brightness }
        UIScreen.main.brightness = 0
        UIDevice.current.isProximityMonitoringEnabled = true
    }
    func exit() {
        UIDevice.current.isProximityMonitoringEnabled = false
        if let b = savedBrightness { UIScreen.main.brightness = b }
        savedBrightness = nil
    }
}
