//
//  NotchLauncherLayout.swift
//  MyIsland
//
//  Layout model for launcher icons in the notch header.
//

import Foundation

enum NotchLauncherItem: Hashable {
    case pet
    case clipboard
    case meetingAssistant
}

enum NotchLauncherLayout {
    static let openedRows: [[NotchLauncherItem]] = [
        [.pet],
        [.clipboard, .meetingAssistant]
    ]
}
