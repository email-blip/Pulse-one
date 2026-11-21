import Foundation

// Shared data types of the "Begleiter" (companion) module. Written first as the contract between the
// sub-teams (docs/pulse-one-coordination/BEGLEITER-BAUPLAN.md). Engines live in sibling files.
// Rules: trends relative to the personal band, no diagnoses, no traffic-light semantics.

// MARK: - Statement type

/// How a sentence was produced. Mirrors the app's `StatementKind` (DesignSystem) so the UI can map 1:1.
public enum CompanionStatement: String, Codable, Sendable, CaseIterable {
    case measured, computed, observed, interpretation, suggestion, medicalCheck
}

/// Evidence label from CREATIVE-LAB-2: A solid, B partly backed, C shaky, D needs another device.
public enum EvidenceLabel: String, Codable, Sendable, CaseIterable {
    case a = "A", b = "B", c = "C", d = "D"

    public var title: String {
        switch self {
        case .a: "belastbar"
        case .b: "ansatzweise belegt"
        case .c: "wackelig, Annäherung"
        case .d: "braucht ein anderes Gerät"
        }
    }
}

// MARK: - Night and wake

/// How the wake-up moment was determined.
public enum WakeMethod: String, Codable, Sendable {
    /// The person tapped "Ich bin wach" (alarm button or in the app).
    case confirmed
    /// Heart rate rose from the night level and steps started.
    case heartRateAndSteps
    /// Only the end of the ring's sleep record.
    case sleepRecordEnd
    /// Nothing usable.
    case unknown
}

public struct WakeEstimate: Equatable, Sendable {
    public let time: Date?
    public let method: WakeMethod
    /// 0…1, how sure the estimate is (confirmed = 1).
    public let confidence: Double

    public init(time: Date?, method: WakeMethod, confidence: Double) {
        self.time = time
        self.method = method
        self.confidence = min(max(confidence, 0), 1)
    }
}

/// Summary of the last night from stored samples (and an optional live measurement after waking).
public struct NightSummary: Equatable, Sendable {
    /// Estimated sleep onset (first sustained low heart rate) or nil.
    public let sleepStart: Date?
    public let wake: WakeEstimate
    /// Seconds asleep: ring/Apple sleep duration if stored, else estimated from heart rate; nil if unknown.
    public let sleepDuration: TimeInterval?
    public let sleepDurationIsEstimated: Bool
    /// Mean of the lowest 30 minutes of night heart rate (bpm).
    public let nightRestingHeartRate: Double?
    public let lowestHeartRate: Double?
    /// Night HRV value and which kind it came from (`.ringHRV` or `.heartRateVariability`, never mixed).
    public let hrv: Double?
    public let hrvKind: SampleKind?
    public let spo2Average: Double?
    /// Positions against the personal band (nil while the band is forming).
    public let restingHeartRatePosition: BandPosition?
    public let hrvPosition: BandPosition?
    public let sleepPosition: BandPosition?
    /// Live heart rate measured right after waking (bpm), if the ring measured.
    public let morningHeartRate: Double?
    /// Kinds that were missing, for an honest coverage note.
    public let missing: [SampleKind]

    public init(sleepStart: Date?, wake: WakeEstimate, sleepDuration: TimeInterval?, sleepDurationIsEstimated: Bool,
                nightRestingHeartRate: Double?, lowestHeartRate: Double?, hrv: Double?, hrvKind: SampleKind?,
                spo2Average: Double?, restingHeartRatePosition: BandPosition?, hrvPosition: BandPosition?,
                sleepPosition: BandPosition?, morningHeartRate: Double?, missing: [SampleKind]) {
        self.sleepStart = sleepStart
        self.wake = wake
        self.sleepDuration = sleepDuration
        self.sleepDurationIsEstimated = sleepDurationIsEstimated
        self.nightRestingHeartRate = nightRestingHeartRate
        self.lowestHeartRate = lowestHeartRate
        self.hrv = hrv
        self.hrvKind = hrvKind
        self.spo2Average = spo2Average
        self.restingHeartRatePosition = restingHeartRatePosition
        self.hrvPosition = hrvPosition
        self.sleepPosition = sleepPosition
        self.morningHeartRate = morningHeartRate
        self.missing = missing
    }
}

/// Overall character of the day, decides tone and quick actions.
public enum CompanionDayType: String, Codable, Sendable, CaseIterable {
    case recovered, normal, shortNight, unusualPattern, notEnoughData

    public var title: String {
        switch self {
        case .recovered: "Gut erholt"
        case .normal: "Normaler Start"
        case .shortNight: "Kurze Nacht"
        case .unusualPattern: "Auffälliges Muster"
        case .notEnoughData: "Noch zu wenig Daten"
        }
    }
}

// MARK: - Infection pattern (P3)

public enum InfectionLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    /// Night values within the personal band.
    case none = 0
    /// One signal outside the band for one night.
    case watch = 1
    /// Resting heart rate above the band ≥ 2 nights plus HRV below (or temperature up).
    case pattern = 2
    /// Pattern for ≥ 3 nights or strongly elevated, or the person reports alarm symptoms.
    case clarify = 3

    public static func < (lhs: InfectionLevel, rhs: InfectionLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct InfectionSignal: Equatable, Sendable {
    public let level: InfectionLevel
    /// Short factual reasons, e.g. "Ruhepuls 2 Nächte über deinem üblichen Bereich".
    public let reasons: [String]
    /// Whether skin temperature was available (R09); without it the check is weaker.
    public let usedTemperature: Bool
    /// The sentence for the briefing, always non-diagnostic, ends with "Das ist keine Diagnose." where relevant.
    public let sentence: String

    public init(level: InfectionLevel, reasons: [String], usedTemperature: Bool, sentence: String) {
        self.level = level
        self.reasons = reasons
        self.usedTemperature = usedTemperature
        self.sentence = sentence
    }
}

// MARK: - Forecast (P1 / P17)

public struct MorningForecast: Codable, Equatable, Sendable, Identifiable {
    public var id: Date { targetDay }
    /// Start of the day the forecast is for.
    public let targetDay: Date
    public let madeAt: Date
    /// Expected night resting heart rate range (bpm).
    public let restingHeartRateLow: Double
    public let restingHeartRateHigh: Double
    /// Expected HRV tendency relative to the personal median: -1 below, 0 around, +1 above. Nil without HRV.
    public let hrvTendency: Int?
    /// Number of past days the model learned from.
    public let trainingDays: Int

    public init(targetDay: Date, madeAt: Date, restingHeartRateLow: Double, restingHeartRateHigh: Double,
                hrvTendency: Int?, trainingDays: Int) {
        self.targetDay = targetDay
        self.madeAt = madeAt
        self.restingHeartRateLow = restingHeartRateLow
        self.restingHeartRateHigh = restingHeartRateHigh
        self.hrvTendency = hrvTendency
        self.trainingDays = trainingDays
    }
}

public struct ForecastOutcome: Equatable, Sendable {
    public let forecast: MorningForecast
    public let actualRestingHeartRate: Double?
    public let actualHRVTendency: Int?
    public let restingHeartRateHit: Bool?
    public let hrvHit: Bool?
    public let sentence: String

    public init(forecast: MorningForecast, actualRestingHeartRate: Double?, actualHRVTendency: Int?,
                restingHeartRateHit: Bool?, hrvHit: Bool?, sentence: String) {
        self.forecast = forecast
        self.actualRestingHeartRate = actualRestingHeartRate
        self.actualHRVTendency = actualHRVTendency
        self.restingHeartRateHit = restingHeartRateHit
        self.hrvHit = hrvHit
        self.sentence = sentence
    }
}

// MARK: - Body pace (P7)

public struct BodyPaceComponent: Equatable, Sendable {
    public let name: String
    /// Years this input adds (+) or removes (−) relative to the calendar age.
    public let years: Double
    public let detail: String

    public init(name: String, years: Double, detail: String) {
        self.name = name
        self.years = years
        self.detail = detail
    }
}

public struct BodyPaceResult: Equatable, Sendable {
    public let calendarAge: Int
    /// Approximation, rounded to whole years. Always shown with label C.
    public let paceAge: Int
    public let components: [BodyPaceComponent]
    public let label: EvidenceLabel
    public let sentence: String

    public init(calendarAge: Int, paceAge: Int, components: [BodyPaceComponent], label: EvidenceLabel = .c, sentence: String) {
        self.calendarAge = calendarAge
        self.paceAge = paceAge
        self.components = components
        self.label = label
        self.sentence = sentence
    }
}

// MARK: - Weather (I6 + P2)

public struct WeatherHour: Codable, Equatable, Sendable {
    public let time: Date
    public let temperature: Double            // °C
    public let apparentTemperature: Double    // °C
    public let precipitationProbability: Double? // 0…100
    public let windSpeed: Double?             // km/h
    public let uvIndex: Double?
    public let relativeHumidity: Double?      // %
    public let surfacePressure: Double?       // hPa

    public init(time: Date, temperature: Double, apparentTemperature: Double, precipitationProbability: Double?,
                windSpeed: Double?, uvIndex: Double?, relativeHumidity: Double?, surfacePressure: Double?) {
        self.time = time
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.precipitationProbability = precipitationProbability
        self.windSpeed = windSpeed
        self.uvIndex = uvIndex
        self.relativeHumidity = relativeHumidity
        self.surfacePressure = surfacePressure
    }
}

public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public let placeName: String
    public let latitude: Double
    public let longitude: Double
    public let fetchedAt: Date
    public let hours: [WeatherHour]
    public let sunrise: Date?
    public let sunset: Date?
    /// European AQI and pollen (grains/m³) for today, if fetched.
    public let europeanAQI: Double?
    public let pollen: [String: Double]

    public init(placeName: String, latitude: Double, longitude: Double, fetchedAt: Date, hours: [WeatherHour],
                sunrise: Date?, sunset: Date?, europeanAQI: Double? = nil, pollen: [String: Double] = [:]) {
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.fetchedAt = fetchedAt
        self.hours = hours
        self.sunrise = sunrise
        self.sunset = sunset
        self.europeanAQI = europeanAQI
        self.pollen = pollen
    }
}

public struct ClothingAdvice: Equatable, Sendable {
    /// e.g. ["Pullover", "leichte Jacke", "Regenschirm"].
    public let items: [String]
    public let sentence: String

    public init(items: [String], sentence: String) {
        self.items = items
        self.sentence = sentence
    }
}

public struct BodyWeatherReport: Equatable, Sendable {
    /// One line about the weather, e.g. "Heute 6 bis 14 Grad, ab 15 Uhr Regen wahrscheinlich."
    public let weatherLine: String
    public let clothing: ClothingAdvice
    /// Body-related weather notes (pressure drop, heat, humidity, pollen, UV), descriptive.
    public let bodyNotes: [String]
    /// Best outdoor window today for movement, if any.
    public let bestOutdoorWindow: DateInterval?
    public let attribution: String

    public init(weatherLine: String, clothing: ClothingAdvice, bodyNotes: [String], bestOutdoorWindow: DateInterval?,
                attribution: String = "Wetterdaten: Open-Meteo.com (CC BY 4.0)") {
        self.weatherLine = weatherLine
        self.clothing = clothing
        self.bodyNotes = bodyNotes
        self.bestOutdoorWindow = bestOutdoorWindow
        self.attribution = attribution
    }
}

// MARK: - Night researcher (I1, local)

public struct ResearchFinding: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(cause)->\(effect)@\(lagDays)" }
    /// Column names of the daily table, e.g. "steps" and "night_resting_hr".
    public let cause: String
    public let effect: String
    /// 0 = same day, 1 = cause day before effect day.
    public let lagDays: Int
    /// Spearman rank correlation.
    public let correlation: Double
    public let sampleDays: Int
    /// Benjamini–Hochberg adjusted p-value.
    public let adjustedP: Double
    public let sentence: String
    public let label: EvidenceLabel

    public init(cause: String, effect: String, lagDays: Int, correlation: Double, sampleDays: Int,
                adjustedP: Double, sentence: String, label: EvidenceLabel) {
        self.cause = cause
        self.effect = effect
        self.lagDays = lagDays
        self.correlation = correlation
        self.sampleDays = sampleDays
        self.adjustedP = adjustedP
        self.sentence = sentence
        self.label = label
    }
}

// MARK: - Day rhythm (nudges)

public enum NudgeKind: String, Codable, Sendable, CaseIterable {
    case daylight, breakfast, caffeineCutoff, lunch, movement, sportWindow, nap, dinner, windDown, bedtime, hydration

    public var symbol: String {
        switch self {
        case .daylight: "sun.max"
        case .breakfast, .lunch, .dinner: "fork.knife"
        case .caffeineCutoff: "cup.and.saucer"
        case .movement: "figure.walk"
        case .sportWindow: "figure.mixed.cardio"
        case .nap: "powersleep"
        case .windDown: "moon"
        case .bedtime: "bed.double"
        case .hydration: "drop"
        }
    }
}

public struct CompanionNudge: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: NudgeKind
    public let time: Date
    public let title: String
    public let body: String

    public init(id: String, kind: NudgeKind, time: Date, title: String, body: String) {
        self.id = id
        self.kind = kind
        self.time = time
        self.title = title
        self.body = body
    }
}

public struct CompanionPreferences: Codable, Equatable, Sendable {
    public enum Tone: String, Codable, Sendable, CaseIterable {
        case factual, motivating, brief
        public var title: String {
            switch self {
            case .factual: "sachlich"
            case .motivating: "motivierend"
            case .brief: "knapp"
            }
        }
    }

    public var firstName: String
    public var tone: Tone
    /// Desired sleep need in hours (default 8).
    public var sleepNeedHours: Double
    public var maxNudgesPerDay: Int
    /// Hours (0–23) during which no nudge is sent.
    public var quietStartHour: Int
    public var quietEndHour: Int
    public var allowsCaffeineTips: Bool
    public var allowsStrengthTips: Bool
    public var speaksBriefing: Bool

    public init(firstName: String = "", tone: Tone = .factual, sleepNeedHours: Double = 8, maxNudgesPerDay: Int = 3,
                quietStartHour: Int = 22, quietEndHour: Int = 7, allowsCaffeineTips: Bool = true,
                allowsStrengthTips: Bool = true, speaksBriefing: Bool = true) {
        self.firstName = firstName
        self.tone = tone
        self.sleepNeedHours = sleepNeedHours
        self.maxNudgesPerDay = maxNudgesPerDay
        self.quietStartHour = quietStartHour
        self.quietEndHour = quietEndHour
        self.allowsCaffeineTips = allowsCaffeineTips
        self.allowsStrengthTips = allowsStrengthTips
        self.speaksBriefing = speaksBriefing
    }
}

// MARK: - Quick actions and briefing

public struct QuickAction: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// One sentence on what and why, descriptive, no promises.
    public let detail: String
    public let symbol: String
    public let minutes: Int
    public let label: EvidenceLabel

    public init(id: String, title: String, detail: String, symbol: String, minutes: Int, label: EvidenceLabel) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.minutes = minutes
        self.label = label
    }
}

public enum BriefingSectionKind: String, Codable, Sendable, CaseIterable {
    case greeting, night, forecastCheck, outlook, infection, weather, actions, breakfastCheck, research, bodyPace, coverage
}

public struct BriefingSection: Codable, Equatable, Sendable, Identifiable {
    public var id: BriefingSectionKind { kind }
    public let kind: BriefingSectionKind
    public let title: String
    public let text: String
    public let statement: CompanionStatement

    public init(kind: BriefingSectionKind, title: String, text: String, statement: CompanionStatement) {
        self.kind = kind
        self.title = title
        self.text = text
        self.statement = statement
    }
}

public struct MorningBriefing: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let dayType: CompanionDayType
    public let headline: String
    public let sections: [BriefingSection]
    public let actions: [QuickAction]
    /// Text for speech synthesis, ≤ ~110 words (about 45 s).
    public let spokenScript: String

    public init(createdAt: Date, dayType: CompanionDayType, headline: String, sections: [BriefingSection],
                actions: [QuickAction], spokenScript: String) {
        self.createdAt = createdAt
        self.dayType = dayType
        self.headline = headline
        self.sections = sections
        self.actions = actions
        self.spokenScript = spokenScript
    }
}

// MARK: - Engine input / output

/// Everything the companion engine needs, gathered by the app (no I/O inside PulseCore).
public struct CompanionInput: Sendable {
    public let now: Date
    public let calendar: Calendar
    /// All usable samples of the last ~35 days for the relevant kinds (heart rate, resting HR, HRV kinds,
    /// SpO₂, steps, sleep duration, skin temperature kinds, active energy, training duration).
    public let samples: [HealthSample]
    public let preferences: CompanionPreferences
    public let birthYear: Int?
    /// Moment the person confirmed being awake (alarm button / app), if any.
    public let confirmedWake: Date?
    /// Time the alarm rang, if any.
    public let alarmTime: Date?
    /// Live heart rate measured after waking (bpm).
    public let morningHeartRate: Double?
    public let weather: WeatherSnapshot?
    /// Forecast made yesterday evening for today, if any.
    public let pendingForecast: MorningForecast?
    /// Latest stored findings of the night researcher.
    public let findings: [ResearchFinding]
    /// Person reports feeling ill / alarm symptoms (from the coach's subjective check), if known.
    public let feelsSick: Bool
    public let alarmSymptoms: Bool
    /// Pain the person reported in the coach's last evening review; no strength step loads these regions.
    public let painRegions: Set<BodyRegion>
    /// Permanent limitations from the coach setup.
    public let limitations: Set<BodyRegion>
    /// A coach health question was answered with yes and no doctor has confirmed yet.
    public let needsMedicalClearance: Bool

    public init(now: Date, calendar: Calendar, samples: [HealthSample], preferences: CompanionPreferences,
                birthYear: Int?, confirmedWake: Date? = nil, alarmTime: Date? = nil, morningHeartRate: Double? = nil,
                weather: WeatherSnapshot? = nil, pendingForecast: MorningForecast? = nil,
                findings: [ResearchFinding] = [], feelsSick: Bool = false, alarmSymptoms: Bool = false,
                painRegions: Set<BodyRegion> = [], limitations: Set<BodyRegion> = [], needsMedicalClearance: Bool = false) {
        self.now = now
        self.calendar = calendar
        self.samples = samples
        self.preferences = preferences
        self.birthYear = birthYear
        self.confirmedWake = confirmedWake
        self.alarmTime = alarmTime
        self.morningHeartRate = morningHeartRate
        self.weather = weather
        self.pendingForecast = pendingForecast
        self.findings = findings
        self.feelsSick = feelsSick
        self.alarmSymptoms = alarmSymptoms
        self.painRegions = painRegions
        self.limitations = limitations
        self.needsMedicalClearance = needsMedicalClearance
    }

    /// The shared day guard for this morning: the coach's last review and setup plus the Begleiter's night reading.
    public func dayGuard(dayType: CompanionDayType, infection: InfectionLevel) -> DayGuard {
        DayGuard.evaluate(DayGuardInput(
            subjective: SubjectiveCheck(painRegions: painRegions, feelsSick: feelsSick, alarmSymptoms: alarmSymptoms),
            limitations: limitations, needsMedicalClearance: needsMedicalClearance,
            companionDayType: dayType, infectionLevel: infection))
    }
}

/// Result of one companion run (morning or re-plan during the day).
public struct CompanionDay: Sendable {
    public let night: NightSummary
    public let dayType: CompanionDayType
    public let infection: InfectionSignal
    public let forecastOutcome: ForecastOutcome?
    public let nextForecast: MorningForecast?
    public let bodyPace: BodyPaceResult?
    public let bodyWeather: BodyWeatherReport?
    public let nudges: [CompanionNudge]
    public let briefing: MorningBriefing

    public init(night: NightSummary, dayType: CompanionDayType, infection: InfectionSignal,
                forecastOutcome: ForecastOutcome?, nextForecast: MorningForecast?, bodyPace: BodyPaceResult?,
                bodyWeather: BodyWeatherReport?, nudges: [CompanionNudge], briefing: MorningBriefing) {
        self.night = night
        self.dayType = dayType
        self.infection = infection
        self.forecastOutcome = forecastOutcome
        self.nextForecast = nextForecast
        self.bodyPace = bodyPace
        self.bodyWeather = bodyWeather
        self.nudges = nudges
        self.briefing = briefing
    }
}
