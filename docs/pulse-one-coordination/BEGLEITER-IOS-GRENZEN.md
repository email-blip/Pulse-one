# Begleiter – iOS-Grenzen (Recherche 2026-11-21)

## Research report: AlarmKit, fallbacks, background limits, Open-Meteo, speech

**Sources.** Apple facts come from the DocC JSON behind developer.apple.com: `https://developer.apple.com/tutorials/data/documentation/<path>.json`. I also read the WWDC25 session 230 page, its transcript and code. Open-Meteo facts come from the official repos `open-meteo/open-meteo` (README) and `open-meteo/open-meteo-website` (docs source). **open-meteo.com and api.open-meteo.com are blocked by this session's network proxy**, so I could not call any Open-Meteo URL live. The example URLs below are built from the official parameter lists but have not been run.

### 1. AlarmKit (iOS 26.0+) — confidence high (signatures taken from Apple's declarations)
- **Info.plist key:** `NSAlarmKitUsageDescription`. If the key is missing or empty, the app cannot schedule any alarms.
- **Authorization:**
  - `func requestAuthorization() async throws -> AlarmManager.AuthorizationState`
  - `var authorizationState: AlarmManager.AuthorizationState { get }`, with cases `.authorized`, `.denied`, `.notDetermined`
  - `authorizationUpdates` is an async stream.
  - If you never ask, AlarmKit asks on its own when the first alarm is scheduled. If the user denies, every schedule call fails.
- **Schedule:** `enum Alarm.Schedule { case fixed(Date); case relative(Alarm.Schedule.Relative) }`
  - `Relative.init(time: Alarm.Schedule.Relative.Time, repeats: Alarm.Schedule.Relative.Recurrence = .never)`
  - `Time.init(hour: Int, minute: Int)`
  - `Recurrence { case never; case weekly([Locale.Weekday]) }`
  - `.fixed` is an absolute Date that does not follow the time zone. `.relative` follows the device's time zone.
- **Configuration:** `static func alarm(schedule: Alarm.Schedule? = nil, attributes: AlarmAttributes<Metadata>, stopIntent: (any LiveActivityIntent)? = nil, secondaryIntent: (any LiveActivityIntent)? = nil, sound: AlertConfiguration.AlertSound = .default) -> AlarmManager.AlarmConfiguration<Metadata>`
  - Also available: `.timer(duration:…)` and `init(countdownDuration:schedule:attributes:stopIntent:secondaryIntent:sound:)`.
  - Do not use the `appEntityIdentifier:` variants: they need **iOS 27.0** and are not in our SDK.
- **Attributes:** `AlarmAttributes.init(presentation: AlarmPresentation, metadata: Metadata? = nil, tintColor: Color)`
- **Alert presentation:** `AlarmPresentation(alert:)` on its own is enough for a plain alarm.
  - `AlarmPresentation.Alert.init(title: LocalizedStringResource, secondaryButton: AlarmButton? = nil, secondaryButtonBehavior: …SecondaryButtonBehavior? = nil)` is **iOS 26.1+**. The stop button is provided by the system.
  - `init(title:stopButton:secondaryButton:secondaryButtonBehavior:)` is iOS 26.0 and **deprecated in 26.1** ("stopButton is deprecated and will no longer be used").
  - Because warnings count as errors in our build, put the 26.1 init behind `if #available(iOS 26.1, *)` and use the old one only in the `else` branch.
- **Button:** `AlarmButton.init(text: LocalizedStringResource, textColor: Color, systemImageName: String)`
- **Secondary button behaviour:** `.countdown` makes it a Repeat/snooze button that re-alerts after `postAlert`. `.custom` runs `secondaryIntent`, for example an "Open" button. Apple notes the secondary intent works only after first unlock.
- **Metadata:** `protocol AlarmMetadata: Decodable, Encodable, Hashable, Sendable`, and it may be empty.
  - Unverified: if our target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, the struct probably needs `nonisolated`. Leaving it out is fine with the default nonisolated setting.
- **Open the app from the alarm:** use a `LiveActivityIntent` with `openAppWhenRun = true`, as in the WWDC sample. The sample declares it as `static var`, which Swift 6 strict concurrency rejects, so use `static let` or a computed property.
- **Widget extension:** **not required for plain alerting alarms.** Apple's wording: "AlarmKit expects a widget extension if an app supports a countdown presentation. Otherwise, the system may unexpectedly dismiss alarms and fail to alert."
- **Sound:** `AlertConfiguration.AlertSound.named(_ name: String)` from ActivityKit, or `.default`. The file must be in the main bundle or in `Library/Sounds` of the app container (WWDC 230).
  - Not stated for AlarmKit: file format and length limit. Assume the system-sound rules: caf/aiff/wav with Linear PCM, IMA4, µLaw or aLaw, under 30 s. Test on a device.
- **Lifecycle:**
  - `func schedule<M>(id: Alarm.ID, configuration: AlarmConfiguration<M>) async throws -> Alarm` (`Alarm.ID` is a UUID)
  - `func cancel(id:) throws` deletes the alarm, even a repeating one.
  - `func stop(id:) throws` deletes a one-shot alarm; a repeating one moves on to its next time.
  - Also available: `pause(id:)`, `resume(id:)`, `countdown(id:)`, `alarms`, `alarmUpdates`. An alarm missing from `alarmUpdates` is no longer scheduled.
- **Silent mode and Focus:** Apple says an alarm "overrides both a device's focus and silent mode". It also shows on the Lock Screen and StandBy and is forwarded to a paired Apple Watch.

```swift
import AlarmKit, AppIntents, SwiftUI
struct WakeMeta: AlarmMetadata {}                       // add `nonisolated` if default isolation is MainActor
struct OpenPulseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Öffnen"
    static let openAppWhenRun = true
    @Parameter(title: "alarmID") var alarmID: String
    init() { alarmID = "" }
    init(alarmID: String) { self.alarmID = alarmID }
    func perform() async throws -> some IntentResult { .result() }
}
@available(iOS 26.0, *)
func scheduleWake(at hour: Int, _ minute: Int, weekdays: [Locale.Weekday]?, date: Date?) async throws -> UUID {
    guard try await AlarmManager.shared.requestAuthorization() == .authorized else { throw CancellationError() }
    let open = AlarmButton(text: "Öffnen", textColor: .white, systemImageName: "sun.max")
    let alert: AlarmPresentation.Alert
    if #available(iOS 26.1, *) {
        alert = .init(title: "Guten Morgen", secondaryButton: open, secondaryButtonBehavior: .custom)
    } else {
        alert = .init(title: "Guten Morgen", stopButton: AlarmButton(text: "Stopp", textColor: .white, systemImageName: "stop.fill"),
                      secondaryButton: open, secondaryButtonBehavior: .custom)
    }
    let attrs = AlarmAttributes<WakeMeta>(presentation: AlarmPresentation(alert: alert), metadata: WakeMeta(), tintColor: .orange)
    let schedule: Alarm.Schedule = if let date { .fixed(date) } else {
        .relative(.init(time: .init(hour: hour, minute: minute), repeats: weekdays.map { .weekly($0) } ?? .never)) }
    let id = UUID()
    let config = AlarmManager.AlarmConfiguration<WakeMeta>.alarm(schedule: schedule, attributes: attrs,
        secondaryIntent: OpenPulseIntent(alarmID: id.uuidString), sound: .named("wake.caf"))
    _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
    return id
}
```

Not compiled: the `if`-expression assignment to `schedule` and the generic `.alarm(...)` call should type-check, but this has not been through CI.

### 2. Fallback for iOS 18–25 (UserNotifications) — confidence high
- Use `UNMutableNotificationContent.sound = UNNotificationSound(named: UNNotificationSoundName("wake.caf"))`.
- **Where it looks for the file, in order:** `<app container>/Library/Sounds`, then the app group's `Library/Sounds`, then the main bundle.
- **Formats:** Linear PCM, MA4 (IMA/ADPCM), µLaw or aLaw, packaged as aiff, wav or caf.
- **Length:** **under 30 s.** A longer file plays the default sound instead.
- **Silent mode:** a normal notification sound is muted by the silent switch and by Focus. This is standard behaviour but not stated on the page I read.
- **Critical alerts:** `UNNotificationSound.defaultCritical` and `criticalSoundNamed(_:)` ignore mute and Do Not Disturb, but need the `com.apple.developer.usernotifications.critical-alerts` entitlement, which Apple must grant on request. A wake-up app will very likely not get it.
- **Practical setup:** a `UNCalendarNotificationTrigger` with `repeats: true` for each weekday. The banner can only open the app; it cannot keep ringing.

### 3. Background reality — confidence medium-high
- **Bluetooth (`UIBackgroundModes: bluetooth-central`):** a connection that is already open stays alive while the app is suspended. Characteristic notifications wake the app briefly (a few seconds) to handle them.
  - Background scanning works only with service UUIDs, and allow-duplicates is ignored.
  - If the system kills the app, state restoration relaunches it: set `CBCentralManagerOptionRestoreIdentifierKey` and implement `centralManager(_:willRestoreState:)`.
  - In scene-based apps the launch options are always nil, so keep the restore identifier fixed in `UserDefaults`, as the doc says.
  - **If the user force-quits the app, it is not relaunched.** The ring's own behaviour overnight (sleep or disconnect) needs a real test.
- **BGTaskScheduler:** `earliestBeginDate` is a lower bound only ("doesn't guarantee launching the task at the specified date"). `BGAppRefreshTask` and `BGProcessingTask` run opportunistically and cannot be used for timing.
- **Moving an alarm earlier from the background:** probably possible but **unverified**. Nothing in the docs restricts `AlarmManager` calls to the foreground. While the app is awake (a Bluetooth callback or a BG task), the pattern would be `cancel(id:)` then `schedule(id: newID, …)`. There is no update or reschedule call; I could not confirm whether reusing the same ID is allowed. Test on a device.
- **Speech:** `AVSpeechSynthesizer` can speak once the app is in the foreground after the alarm's Open intent. Speaking while the app is backgrounded or locked needs the `audio` background mode and an active `.playback` session. This is standard behaviour, not re-verified here.

### 4. Open-Meteo — confidence medium-high (from docs source, URLs not run)
- **Terms:** "free for non-commercial use", no API key, fair use. The README asks you to contact them above 10,000 requests per day. Search results quoting the terms page also give 5,000 per hour and 600 per minute.
- **Licence and attribution:** CC BY 4.0. Put a link next to every place the data is shown: `<a href="https://open-meteo.com/">Weather data by Open-Meteo.com</a>`. Credit, a link to the licence and a note of any changes are required.
- **Forecast:** all requested variable names are confirmed in the docs options. Example:
  `https://api.open-meteo.com/v1/forecast?latitude=48.14&longitude=11.58&hourly=temperature_2m,apparent_temperature,precipitation_probability,wind_speed_10m,uv_index,surface_pressure,relative_humidity_2m&daily=sunrise,sunset&timezone=Europe%2FBerlin&forecast_days=3`
  `wind_speed_unit` (for example `kmh`, the default) was not confirmed in this pass.
- **Geocoding:** endpoints `/v1/search` and `/v1/get`, parameters `name`, `count`, `language`, `format`, `countryCode`. Result fields include `name`, `latitude`, `longitude`, `country_code`, `admin1`, `timezone`, `population`, `postcodes`. Example:
  `https://geocoding-api.open-meteo.com/v1/search?name=M%C3%BCnchen&count=5&language=de&format=json`
- **Air quality and pollen:** endpoint `/v1/air-quality`.
  - AQI variables: `european_aqi`, `european_aqi_pm2_5`, `european_aqi_pm10`, `european_aqi_nitrogen_dioxide`, `european_aqi_ozone`, `european_aqi_sulphur_dioxide`, plus `us_aqi*`.
  - Pollen variables: `alder_pollen`, `birch_pollen`, `grass_pollen`, `mugwort_pollen`, `olive_pollen`, `ragweed_pollen`.
  - Pollen is "only available in Europe during pollen season with 4 days forecast" (from CAMS Europe).
  - Example: `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=48.14&longitude=11.58&hourly=european_aqi,birch_pollen,grass_pollen,alder_pollen,mugwort_pollen,ragweed_pollen&timezone=Europe%2FBerlin&forecast_days=4`

### 5. AVSpeechSynthesizer — confidence high
- `AVSpeechSynthesisVoice(language: "de-DE")` takes a BCP 47 code and returns nil if the code is invalid.
- `AVSpeechSynthesisVoice.speechVoices()` lists the voices; filter on `language == "de-DE"` and prefer `quality` in the order `.premium`, then `.enhanced`, then `.default`.
- Enhanced and premium voices exist only if the user downloaded them (Settings > Accessibility > Spoken Content), so always fall back to the default voice.
- **Audio session:** for occasional spoken prompts, Apple recommends
  `try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])`.
  - Apple says to set `.duckOthers` together with `interruptSpokenAudioAndMixWithOthers` unless there is a reason not to.
  - `.spokenAudio` mode means our speech pauses, rather than ducks, when another app plays a spoken prompt.
  - Afterwards call `setActive(false, options: .notifyOthersOnDeactivation)`.
  - `.playback` keeps playing with the silent switch on.

### Not verified
- AlarmKit sound file format and length limit.
- Moving or rescheduling an AlarmKit alarm from the background.
- Whether `AlarmMetadata` must be `nonisolated` under MainActor default isolation.
- The Open-Meteo example URLs. To check them live, open-meteo.com, api.open-meteo.com, geocoding-api.open-meteo.com and air-quality-api.open-meteo.com have to be allowed in the session's network settings.

Sources: developer.apple.com/documentation/alarmkit (scheduling-an-alarm-with-alarmkit, alarmmanager, alarmconfiguration, alarmpresentation/alert, alarmbutton, alarmattributes, alarmmetadata, alarm/schedule), developer.apple.com/videos/play/wwdc2025/230, usernotifications/unnotificationsound, critical-alerts entitlement, backgroundtasks/bgtaskrequest/earliestbegindate, corebluetooth/cbcentralmanageroptionrestoreidentifierkey, avfaudio docs, github.com/open-meteo/open-meteo README, github.com/open-meteo/open-meteo-website docs source, [open-meteo.com/en/terms](https://open-meteo.com/en/terms) (via search results).

## Nachtrag 2026-11-22: TN3115 und Bluetooth im Hintergrund (Codex P1-005)

Quelle: Apple Technote TN3115 „Bluetooth State Restoration app relaunch rules“.

- iOS startet eine App mit State Restoration neu, wenn das System sie aus dem Speicher genommen hat, nach einem Absturz, nach Bluetooth- oder Flugmodus-Umschalten im Kontrollzentrum und nach einem Neustart (sobald das iPhone einmal entsperrt wurde).
- Kein Neustart nach Wegwischen durch die Person und nach Bluetooth-Aus in den Einstellungen.
- Neustart nur, wenn die App auf ein bestimmtes Bluetooth-Ereignis wartet (Verbindung, abonnierte Meldung, Suche).
- **iOS 26: Nur Apps, die ihr Zubehör über AccessorySetupKit eingerichtet haben, werden nach Beendigung neu gestartet.** PULSE ONE nutzt AccessorySetupKit noch nicht. Folge: Solange die App im Hintergrund pausiert ist, kommen Ring-Ereignisse an; wird sie beendet, bleibt der Ring bis zum nächsten Öffnen getrennt. Ein Umstieg auf AccessorySetupKit ist als eigener Schritt nötig.

Getrennte Zustände (nie gleichsetzen): Bluetooth verbunden · Verlauf abgeglichen (mit Zeitpunkt) · echter Live-Strom. Pro Messart zu berichten: Rate, Verzögerung, Lücken, Akkulast. Lückenlose R03-Daten werden erst nach einem Realtest behauptet.

Weitere Fakten: Entsperren ist kein Aufwachsignal. Ein Fokus-Filter ist keine Schlafüberwachung. BGAppRefresh und BGProcessing sind getrennte Aufgaben ohne garantierte Zeit. AlarmKit gibt es erst ab iOS 26. Eine Live Activity bekommt keine Bluetooth-Daten und läuft nicht endlos.

