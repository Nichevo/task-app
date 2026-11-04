import Foundation

/// The shared storage (app group) the app and its widgets both use.
///
/// The project asks for `group.app.taskblocks`, but sideloading tools such as AltStore re-sign the
/// app with a free Apple ID and rename the group (they add the team id to the end). They list the
/// real names in the `ALTAppGroups` Info.plist key, so that list is tried first. A name only counts
/// if this build is really allowed to use it (iOS hands back a folder for it).
enum AppGroup {
  static let projectName = "group.app.taskblocks"

  /// The group to use, or nil when this build was signed without any shared group.
  static let id: String? = candidates().first { usable($0) }

  static func candidates() -> [String] {
    var names: [String] = []
    for bundle in [Bundle.main, containingApp()].compactMap({ $0 }) {
      if let list = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
        names += list.filter { $0.hasPrefix(projectName) }
        names += list.filter { !$0.hasPrefix(projectName) }
      }
    }
    names.append(projectName)
    var seen = Set<String>()
    return names.filter { seen.insert($0).inserted }
  }

  static func usable(_ name: String) -> Bool {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: name) != nil
  }

  /// For a widget (Runner.app/PlugIns/X.appex) this is the app around it; for the app, nil.
  private static func containingApp() -> Bundle? {
    let url = Bundle.main.bundleURL
    guard url.pathExtension == "appex" else { return nil }
    return Bundle(url: url.deletingLastPathComponent().deletingLastPathComponent())
  }
}
