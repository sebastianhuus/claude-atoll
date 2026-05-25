//
//  ScreenObserver.swift
//  ClaudeAtoll
//
//  Monitors screen configuration changes
//

import AppKit

/// Monitors screen configuration changes.
/// Isolated to MainActor (default) since notifications are observed on the main queue.
final class ScreenObserver {
    // MARK: Lifecycle

    init(onScreenChange: @escaping () -> Void) {
        self.onScreenChange = onScreenChange
        self.startObserving()
    }

    deinit {
        debounceTask?.cancel()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // MARK: Private

    /// nonisolated(unsafe) allows deinit cleanup — safe because deinit has exclusive access
    nonisolated(unsafe) private var observer: Any?
    nonisolated(unsafe) private var wakeObserver: Any?
    private let onScreenChange: () -> Void
    private var debounceTask: Task<Void, Never>?

    /// Debounce interval to coalesce rapid screen change notifications
    /// (e.g., when waking from sleep, displays reconnect in stages)
    private let debounceInterval: Duration = .milliseconds(500)

    private func startObserving() {
        self.observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleScreenChange()
            }
        }

        // Re-trigger window setup after display wakes — the panel can sink below other
        // windows or have its level reset by the WindowServer during sleep/wake.
        self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleScreenChange()
            }
        }
    }

    private func scheduleScreenChange() {
        self.debounceTask?.cancel()

        self.debounceTask = Task(name: "screen-change-debounce") { [weak self] in
            try? await Task.sleep(for: self?.debounceInterval ?? .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.onScreenChange()
        }
    }
}
