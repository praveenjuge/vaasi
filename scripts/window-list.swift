// Prints on-screen windows owned by an app: "<windowID> <x>,<y>,<w>,<h> <title>".
// Usage: swift scripts/window-list.swift Vaasi
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Vaasi"
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in info where (window[kCGWindowOwnerName as String] as? String) == owner {
    let id = window[kCGWindowNumber as String] as? Int ?? 0
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let title = window[kCGWindowName as String] as? String ?? ""
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    print("\(id) \(Int(bounds["X"] ?? 0)),\(Int(bounds["Y"] ?? 0)),\(Int(bounds["Width"] ?? 0)),\(Int(bounds["Height"] ?? 0)) layer=\(layer) \(title)")
}
