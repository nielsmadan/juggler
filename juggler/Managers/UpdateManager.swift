//
//  UpdateManager.swift
//  Juggler
//

import Foundation
import Sparkle

final class UpdateManager {
    static let shared = UpdateManager()

    private let updaterController: SPUStandardUpdaterController

    var updater: SPUUpdater {
        updaterController.updater
    }

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }
}
