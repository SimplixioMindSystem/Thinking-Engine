#!/usr/bin/env swift

import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2,
      let processID = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("Usage: macos_window_id.swift <pid>\n".utf8))
    exit(2)
}

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("Unable to read the macOS window list.\n".utf8))
    exit(1)
}

let candidates: [(number: UInt32, area: CGFloat)] = windowInfo.compactMap { info in
    guard let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber,
          ownerPID.int32Value == processID,
          let layer = info[kCGWindowLayer as String] as? NSNumber,
          layer.intValue == 0,
          let alpha = info[kCGWindowAlpha as String] as? NSNumber,
          alpha.doubleValue > 0,
          let number = info[kCGWindowNumber as String] as? NSNumber,
          let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
          bounds.width >= 800,
          bounds.height >= 500 else {
        return nil
    }

    return (number.uint32Value, bounds.width * bounds.height)
}

guard let mainWindow = candidates.max(by: { $0.area < $1.area }) else {
    FileHandle.standardError.write(Data("No visible app window found for pid \(processID).\n".utf8))
    exit(1)
}

print(mainWindow.number)
