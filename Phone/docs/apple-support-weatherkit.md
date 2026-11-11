# Apple code-level support request: WeatherKit fails for a new App ID (RESOLVED, see below)

**Resolved 16 Oct 2026:** the cause was on our side. WeatherKit was ticked on the App ID's Capabilities tab but NOT on its
App Services tab; both are needed (Apple DTS reply, Case-ID 22926661, pointing to forum thread 827342). Ticking App Services
fixed it: the Tonight screen now shows the Apple Weather mark. Everything below, including its claim that both tabs were
ticked, is the original draft and was wrong on that point.

**Status 14 Oct 2026:** Apple's code-level form blocks the request without a focused sample Xcode project (it shows no submit button for "No"). Owner decided not to build one, because a new project needs a new App ID and may not show the fault. So this stays unsent. The route in use is forum thread https://developer.apple.com/forums/thread/851146.

Send at: https://developer.apple.com/contact/request/code-level-support/ (sign in with the developer account first).
One issue per request, in English, as Apple asks. Paste the text between the lines into the request form. When the
acknowledgement email arrives, reply to it with the two attachments listed at the end.

---

**Subject:** WeatherKit returns WDSJWTAuthenticatorServiceListener error 2 for a new App ID on two physical devices

**Team and App ID**
- Team ID: 8B44CZ9923 (Apple Developer Program, individual)
- Bundle ID: io.github.rsutcliffe.nightwatch.phone (explicit App ID, created by Xcode automatic signing on 14 October 2026)
- Xcode 27.0, iOS and iPadOS 27.0.1
- Devices: iPhone 15 Pro and iPad Air 11-inch (M3), both registered in the account, both with Developer Mode on

**What goes wrong**
Every WeatherKit request from this app fails on both devices within 0.4 to 2.4 seconds with this exact error:

`Error Domain=WeatherDaemon.WDSJWTAuthenticatorServiceListener.Errors Code=2 "(null)"`

The call is `try await WeatherService.shared.weather(for: location, including: .hourly(startDate: start, endDate: end))`.
The app falls back to another weather source when this fails, so nothing else in the app is affected.

**What I expect**
The request to succeed, as it does for my other App ID on the same team (below).

**What I have checked**
1. The signed app's entitlements and the embedded provisioning profile both contain `com.apple.developer.weatherkit`.
2. In Certificates, Identifiers & Profiles, the App ID has WeatherKit ticked on both the Capabilities tab and the App Services tab.
3. The Apple Developer Program License Agreement update issued 13 October 2026 was pending when the App ID was created. I accepted it on 14 October 2026 (the account page now shows accepted 14 October). The failure is unchanged since.
4. I unticked WeatherKit on the App ID, saved, ticked it again and saved, then deleted the cached provisioning profile so Xcode generated a new one (profile created 09:25 UTC on 14 October, after the change), reinstalled on both devices and retested. Same error.
5. I restarted both devices and retested. Same error.
6. The failure is the same on a second device of a different model, so it is not tied to one device.
7. I pressed Download Manual Profiles in Xcode, did a clean build, deleted the app from both devices and installed it fresh. Same error.
8. More than 90 minutes have passed since WeatherKit was last enabled on the App ID, so the 30-minute activation delay some tutorials mention has long gone.
9. A public forum thread with the same details is awaiting moderation: https://developer.apple.com/forums/thread/851146

**For comparison**
Another App ID on the same team uses WeatherKit successfully. The two share no profile or App ID.

**Steps to reproduce**
1. Build the app signed with automatic signing for team 8B44CZ9923 and install it on either device.
2. Launch it. The first WeatherKit request fails with the error above.

**My question**
Is WeatherKit's registration for this new App ID stuck or incomplete on the server side? If so, can it be reset or
re-registered for io.github.rsutcliffe.nightwatch.phone under team 8B44CZ9923? If something else is needed on my side,
what is it?

Thank you,
Richard Sutcliffe

---

**Attachments to reply with (after the acknowledgement email):**
1. The exact error text above, pasted as text (run the app with the launch argument `-probeWeatherKit` to print it; the
   log line starts "WeatherKit failed after ...").
2. A screenshot of the App ID page showing WeatherKit ticked on the Capabilities and App Services tabs.
