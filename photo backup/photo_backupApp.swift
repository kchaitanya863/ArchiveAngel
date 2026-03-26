//
//  photo_backupApp.swift
//  photo backup
//
//  Created by Krishna on 11/13/23.
//

import SwiftUI

@main
struct photo_backupApp: App {
    @StateObject private var viewModel = ArchiveAngelViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }
}
