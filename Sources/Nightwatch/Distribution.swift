/// The only difference between the download and the Mac App Store build (0.7.x). The App Store updates the app itself,
/// and its rule 2.4.5(vii) allows no other update mechanism, so that build has no update check. `scripts/appstore.sh`
/// builds it with the `APPSTORE` compilation condition (`scripts/build-app.sh`); a test keeps this the only `#if APPSTORE` in the code.
enum Distribution {
#if APPSTORE
    static let checksForUpdates = false
#else
    static let checksForUpdates = true
#endif
}
