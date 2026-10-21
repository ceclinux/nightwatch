/// The only differences between the download and the Mac App Store build (0.7.x). The App Store updates the app itself,
/// and its rule 2.4.5(vii) allows no other update mechanism, so that build has no update check. Nor has it the widget
/// helper (1.5.4), which works outside the sandbox and so cannot be in a store build: `scripts/appstore.sh` removes it.
/// Nor does it copy 0.6 settings in (1.6.2): a store user never had any, and the sandbox there may not read the old folder.
/// `scripts/appstore.sh` builds with the `APPSTORE` compilation condition (`scripts/build-app.sh`); a test keeps this
/// the only `#if APPSTORE` in the code.
enum Distribution {
#if APPSTORE
    static let checksForUpdates = false
    static let hasWidgetHelper = false
    static let copiesEarlierSettings = false
#else
    static let checksForUpdates = true
    static let hasWidgetHelper = true
    static let copiesEarlierSettings = true
#endif
}
