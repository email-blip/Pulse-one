import Foundation
import Testing
@testable import PulseCore

// Begleiter T3 – quick actions, morning briefing, safety, prompts, engine (BEGLEITER-BAUPLAN.md T3).

private let briefingCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? TimeZone(secondsFromGMT: 3_600) ?? .current
    return calendar
}()

/// 2026-11-21 at the given local Berlin time, shifted by `dayOffset` days.
private func berlin(dayOffset: Int = 0, hour: Int, minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 11, day: 21, hour: hour, minute: minute)
    let base = briefingCalendar.date(from: components) ?? Date(timeIntervalSince1970: 1_795_239_900)
    return briefingCalendar.date(byAdding: .day, value: dayOffset, to: base) ?? base
}

private let morning = berlin(hour: 6, minute: 45)

private func makeNight(sleepHours: Double? = 7.5, estimated: Bool = false, sleepPosition: BandPosition? = .within,
                       restingHR: Double? = 54, restingPosition: BandPosition? = .within,
                       hrv: Double? = 44, hrvPosition: BandPosition? = .within,
                       missing: [SampleKind] = []) -> NightSummary {
    NightSummary(sleepStart: berlin(dayOffset: -1, hour: 23), wake: WakeEstimate(time: berlin(hour: 6, minute: 30), method: .confirmed, confidence: 1),
                 sleepDuration: sleepHours.map { $0 * 3_600 }, sleepDurationIsEstimated: estimated,
                 nightRestingHeartRate: restingHR, lowestHeartRate: restingHR.map { $0 - 4 }, hrv: hrv,
                 hrvKind: hrv == nil ? nil : .ringHRV, spo2Average: 96, restingHeartRatePosition: restingPosition,
                 hrvPosition: hrvPosition, sleepPosition: sleepPosition, morningHeartRate: nil, missing: missing)
}

private func makeInfection(_ level: InfectionLevel) -> InfectionSignal {
    switch level {
    case .none:
        InfectionSignal(level: .none, reasons: [], usedTemperature: false,
                        sentence: "Deine Nachtwerte liegen in deinem üblichen Bereich, ein Infekt-Muster sehe ich heute nicht. Das ist keine Diagnose.")
    case .watch:
        InfectionSignal(level: .watch, reasons: ["Ruhepuls 1 Nacht über deinem üblichen Bereich"], usedTemperature: false,
                        sentence: "Dein Ruhepuls lag eine Nacht über deinem üblichen Bereich. Das ist keine Diagnose.")
    case .pattern, .clarify:
        InfectionSignal(level: level, reasons: ["Ruhepuls 2 Nächte über deinem üblichen Bereich", "HRV 2 Nächte darunter"],
                        usedTemperature: false,
                        sentence: "So ein Muster sehe ich bei dir manchmal nach intensiven Tagen, nach Alkohol oder vor einem Infekt. Das ist keine Diagnose.")
    }
}

private func makeWeather(sunriseHour: Int = 7, sunriseMinute: Int = 50) -> WeatherSnapshot {
    let hours = (6...22).map { hour in
        WeatherHour(time: berlin(hour: hour), temperature: 8, apparentTemperature: 5, precipitationProbability: 20,
                    windSpeed: 12, uvIndex: 1, relativeHumidity: 80, surfacePressure: 1_015)
    }
    return WeatherSnapshot(placeName: "Teststadt", latitude: 52.52, longitude: 13.40, fetchedAt: berlin(hour: 6),
                           hours: hours, sunrise: berlin(hour: sunriseHour, minute: sunriseMinute), sunset: berlin(hour: 16, minute: 20))
}

private func makeBodyWeather(line: String = "Heute 6 bis 14 Grad, ab 15 Uhr Regen wahrscheinlich.") -> BodyWeatherReport {
    BodyWeatherReport(weatherLine: line,
                      clothing: ClothingAdvice(items: ["Pullover", "Regenjacke"], sentence: "Gefühlt 5 Grad: warme Jacke, Schal hilft."),
                      bodyNotes: [], bestOutdoorWindow: nil)
}

private func pick(_ dayType: CompanionDayType, preferences: CompanionPreferences = CompanionPreferences(),
                  dayOffset: Int = 0, weather: WeatherSnapshot? = nil) -> [QuickAction] {
    QuickActionPicker.pick(dayType: dayType, night: makeNight(), weather: weather, preferences: preferences,
                           now: berlin(dayOffset: dayOffset, hour: 6, minute: 45), calendar: briefingCalendar)
}

private func makeParts(_ dayType: CompanionDayType, infection: InfectionLevel = .none, night: NightSummary = makeNight(),
                       weather: BodyWeatherReport? = makeBodyWeather(), withExtras: Bool = false) -> BriefingParts {
    let finding = ResearchFinding(cause: "steps", effect: "night_resting_hr", lagDays: 1, correlation: -0.45, sampleDays: 42,
                                  adjustedP: 0.03,
                                  sentence: "An Tagen mit mehr als 8.000 Schritten war dein Nachtpuls im Schnitt 3 Schläge niedriger (42 Tage, Zusammenhang, keine Ursache).",
                                  label: .b)
    let pace = BodyPaceResult(calendarAge: 45, paceAge: 43, components: [],
                              sentence: "Dein 4-Wochen-Trend entspricht etwa 41 bis 45 Jahren. Nur eine Annäherung.")
    return BriefingParts(night: night, dayType: dayType, infection: makeInfection(infection),
                         bodyPace: withExtras ? pace : nil, bodyWeather: weather,
                         actions: pick(dayType), topFinding: withExtras ? finding : nil)
}

private func compose(_ parts: BriefingParts, name: String = "Johannes",
                     tone: CompanionPreferences.Tone = .factual) -> MorningBriefing {
    MorningBriefingComposer.compose(day: parts, preferences: CompanionPreferences(firstName: name, tone: tone),
                                    now: morning, calendar: briefingCalendar)
}

private func words(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
}

// MARK: - Quick actions

@Suite("Begleiter – Jetzt tun")
struct CompanionQuickActionTests {
    @Test func catalogHasSeventeenStableActions() {
        let ids = QuickActionCatalog.all.map(\.id)
        #expect(ids.count == 17)
        #expect(Set(ids).count == ids.count)
        #expect(ids.first == "water")
        for action in QuickActionCatalog.all {
            #expect(!action.title.isEmpty && !action.detail.isEmpty && !action.symbol.isEmpty)
            #expect(CompanionSafety.violations(in: action.title + " " + action.detail).isEmpty)
        }
        #expect(QuickActionCatalog.action(id: "coffeeDelay")?.label == .c)
    }

    @Test func pickerReturnsThreeDistinctForEveryDayType() {
        for dayType in CompanionDayType.allCases {
            for offset in 0..<21 {
                let actions = pick(dayType, dayOffset: offset)
                #expect(actions.count == 3)
                #expect(Set(actions.map(\.id)).count == 3)
            }
        }
    }

    @Test func gentleDaysHaveNoStrengthOrCold() {
        let excluded = QuickActionCatalog.strengthIDs.union(QuickActionCatalog.coldIDs)
        for dayType in [CompanionDayType.shortNight, .unusualPattern] {
            for offset in 0..<21 {
                let ids = Set(pick(dayType, dayOffset: offset).map(\.id))
                #expect(ids.isDisjoint(with: excluded))
                #expect(ids.contains("water"))
            }
        }
        let pattern = pick(.unusualPattern)
        #expect(pattern.map(\.id).contains("calmBreathing"))
        #expect(!pattern.map(\.id).contains("strongCoffee"))
    }

    @Test func recoveredMayIncludeStrengthOnlyWhenAllowed() {
        let allowed = (0..<14).flatMap { pick(.recovered, dayOffset: $0).map(\.id) }
        #expect(!Set(allowed).isDisjoint(with: QuickActionCatalog.strengthIDs))
        #expect(allowed.contains("coldFace"))

        let noStrength = CompanionPreferences(allowsStrengthTips: false)
        let blocked = (0..<14).flatMap { pick(.recovered, preferences: noStrength, dayOffset: $0).map(\.id) }
        #expect(Set(blocked).isDisjoint(with: QuickActionCatalog.strengthIDs))
    }

    @Test func caffeineOnlyWhenAllowed() {
        let noCaffeine = CompanionPreferences(allowsCaffeineTips: false)
        for dayType in CompanionDayType.allCases {
            for offset in 0..<14 {
                let ids = Set(pick(dayType, preferences: noCaffeine, dayOffset: offset).map(\.id))
                #expect(ids.isDisjoint(with: QuickActionCatalog.caffeineIDs))
            }
        }
    }

    @Test func pickerIsDeterministicAndRotates() {
        #expect(pick(.normal) == pick(.normal))
        let today = pick(.normal, dayOffset: 0).map(\.id)
        let tomorrow = pick(.normal, dayOffset: 1).map(\.id)
        #expect(today != tomorrow)
    }

    @Test func darkMorningOffersIndoorLight() {
        let dark = pick(.shortNight, weather: makeWeather(sunriseHour: 7, sunriseMinute: 50))
        #expect(dark.contains { $0.id == "daylight" && $0.title == "Helles Licht" })
        let bright = pick(.shortNight, weather: makeWeather(sunriseHour: 6, sunriseMinute: 0))
        #expect(bright.contains { $0.id == "daylight" && $0.title == "Tageslicht" })
    }
}

// MARK: - Briefing

@Suite("Begleiter – Morgenbericht")
struct CompanionBriefingComposerTests {
    @Test func headlineUsesFirstNameOrStaysNeutral() {
        #expect(compose(makeParts(.normal)).headline == "Guten Morgen, Johannes.")
        #expect(compose(makeParts(.normal), name: "  ").headline == "Guten Morgen.")
    }

    @Test func outlookMatchesDayType() {
        let expected: [CompanionDayType: String] = [
            .recovered: "Dein Tag: gute Voraussetzungen für Belastung.",
            .normal: "gut für dein normales Programm",
            .shortNight: "ruhigeren Takt",
            .unusualPattern: "Geh es heute langsamer an",
            .notEnoughData: "bildet sich noch"
        ]
        for (dayType, phrase) in expected {
            let briefing = compose(makeParts(dayType, infection: dayType == .unusualPattern ? .pattern : .none))
            let outlook = briefing.sections.first { $0.kind == .outlook }
            #expect(outlook?.text.contains(phrase) == true, "\(dayType)")
            #expect(briefing.dayType == dayType)
        }
    }

    @Test func nightSectionDescribesDurationBandAndEstimate() {
        let night = makeNight(sleepHours: 5 + 40.0 / 60, estimated: true, sleepPosition: .below)
        let text = compose(makeParts(.shortNight, night: night)).sections.first { $0.kind == .night }?.text ?? ""
        #expect(text.contains("Du hast geschätzt 5 Stunden 40 geschlafen, das liegt unter deinem üblichen Bereich."))
        #expect(text.contains("54 Schlägen pro Minute, im üblichen Bereich"))
        #expect(text.contains("44 ms (Ring-Messung)"))
    }

    @Test func sectionsFollowContractOrder() throws {
        let briefing = compose(makeParts(.recovered, withExtras: true))
        let order = BriefingSectionKind.allCases
        let indices = try briefing.sections.map { section in try #require(order.firstIndex(of: section.kind)) }
        #expect(indices == indices.sorted())
        #expect(briefing.sections.first?.kind == .greeting)
        let kinds = briefing.sections.map(\.kind)
        #expect(kinds.contains(.weather) && kinds.contains(.actions) && kinds.contains(.breakfastCheck))
        #expect(briefing.sections.first { $0.kind == .breakfastCheck }?.text == "Am Frühstückstisch messe ich noch einmal kurz deinen Puls.")
        #expect(briefing.sections.first { $0.kind == .actions }?.text.hasPrefix("Jetzt: ") == true)
        #expect(briefing.actions.count == 3)
    }

    @Test func infectionStatementFollowsLevel() {
        let calm = compose(makeParts(.normal, infection: .none)).sections.first { $0.kind == .infection }
        #expect(calm?.statement == .computed)
        #expect(calm?.text.contains("Das ist keine Diagnose.") == true)

        let clarify = compose(makeParts(.unusualPattern, infection: .clarify)).sections.first { $0.kind == .infection }
        #expect(clarify?.statement == .medicalCheck)
        #expect(clarify?.text.contains("ärztlich abklären") == true)
    }

    @Test func unsafeEngineSentenceIsReplaced() {
        let unsafe = InfectionSignal(level: .none, reasons: [], usedTemperature: false, sentence: "Du bist nicht krank.")
        let parts = BriefingParts(night: makeNight(), dayType: .normal, infection: unsafe, actions: pick(.normal))
        let text = compose(parts).sections.first { $0.kind == .infection }?.text ?? ""
        #expect(!text.contains("nicht krank"))
        #expect(text.contains("Das ist keine Diagnose."))
    }

    @Test func briefToneDropsResearchAndBodyPace() {
        let parts = makeParts(.recovered, withExtras: true)
        let factual = compose(parts, tone: .factual).sections.map(\.kind)
        #expect(factual.contains(.research) && factual.contains(.bodyPace))
        let brief = compose(parts, tone: .brief).sections.map(\.kind)
        #expect(!brief.contains(.research) && !brief.contains(.bodyPace))
        let motivating = compose(parts, tone: .motivating)
        #expect(motivating.sections.first?.text.contains("Schön, dass du wach bist.") == true)
        #expect(motivating.sections.first { $0.kind == .bodyPace }?.text.contains("Etikett C") == true)
    }

    @Test func coverageNamesMissingKindsAndFormingBand() {
        let night = makeNight(restingPosition: nil, hrv: nil, hrvPosition: nil, missing: [.ringHRV, .ringHRV, .oxygenSaturation])
        let text = compose(makeParts(.notEnoughData, night: night)).sections.first { $0.kind == .coverage }?.text ?? ""
        #expect(text.contains("HRV (Ring), Sauerstoffsättigung"))
        #expect(text.contains("bildet sich noch"))
    }

    @Test func spokenScriptStaysWithinLimitAndKeepsCore() {
        let longLine = Array(repeating: "Heute bleibt es den ganzen Tag wechselhaft mit Wolken und etwas Wind.", count: 8)
            .joined(separator: " ")
        for dayType in CompanionDayType.allCases {
            for tone in CompanionPreferences.Tone.allCases {
                let parts = makeParts(dayType, infection: dayType == .unusualPattern ? .clarify : .none,
                                      weather: makeBodyWeather(line: longLine))
                let script = compose(parts, tone: tone).spokenScript
                #expect(words(script) <= MorningBriefingComposer.maxSpokenWords)
                #expect(script.hasPrefix("Guten Morgen, Johannes."))
                #expect(script.contains("Jetzt: "))
            }
        }
        let normal = compose(makeParts(.normal)).spokenScript
        #expect(normal.contains("ab 15 Uhr Regen"))
        #expect(!normal.contains("Open-Meteo"))
    }

    @Test func everyBriefingTextPassesSafety() {
        for dayType in CompanionDayType.allCases {
            for level in InfectionLevel.allCases {
                for tone in CompanionPreferences.Tone.allCases {
                    let briefing = compose(makeParts(dayType, infection: level, withExtras: true), tone: tone)
                    for section in briefing.sections {
                        #expect(CompanionSafety.violations(in: section.text).isEmpty, "\(section.kind): \(section.text)")
                    }
                    #expect(CompanionSafety.violations(in: briefing.spokenScript).isEmpty)
                }
            }
        }
    }
}

// MARK: - Safety

@Suite("Begleiter – Sicherheitsregeln")
struct CompanionSafetyTests {
    @Test func catchesForbiddenPhrases() {
        #expect(CompanionSafety.violations(in: "Du bist nicht krank.").contains("du bist nicht krank"))
        #expect(CompanionSafety.violations(in: "DU BIST GESUND!").contains("du bist gesund"))
        #expect(CompanionSafety.violations(in: "Diagnose: Erkältung").contains("diagnose:"))
        #expect(CompanionSafety.violations(in: "Du hast eine Grippe.").contains("du hast eine"))
        #expect(!CompanionSafety.violations(in: "Diese Therapie hilft garantiert.").isEmpty)
        #expect(CompanionSafety.violations(in: "Nimm ein Medikament.") == ["medikament"])
        #expect(CompanionSafety.sanitize("Infektion festgestellt.") == nil)
    }

    @Test func allowsNoDiagnosisSentence() {
        let text = "Dein Ruhepuls liegt über deinem üblichen Bereich. Das ist keine Diagnose."
        #expect(CompanionSafety.violations(in: text).isEmpty)
        #expect(CompanionSafety.sanitize(text) == text)
    }
}

// MARK: - Prompts

@Suite("Begleiter – KI-Prompts")
struct CompanionPromptTests {
    private func makeDay() -> CompanionDay {
        let parts = makeParts(.unusualPattern, infection: .pattern, withExtras: true)
        let briefing = compose(parts)
        return CompanionDay(night: parts.night, dayType: parts.dayType, infection: parts.infection, forecastOutcome: nil,
                            nextForecast: nil, bodyPace: parts.bodyPace, bodyWeather: parts.bodyWeather, nudges: [],
                            briefing: briefing)
    }

    @Test func minimalFactsHaveNoNameOrPlace() {
        let facts = CompanionPrompts.minimalFacts(makeDay())
        #expect(!facts.contains("Johannes"))
        #expect(!facts.contains("Teststadt"))
        #expect(facts.contains("Tagestyp: Auffälliges Muster"))
        #expect(facts.contains("Nachtruhepuls: 54"))
        #expect(facts.contains("Ring-Methode"))
        #expect(facts.contains("Jetzt-Schritte:"))
        #expect(facts.contains("Das ist keine Diagnose."))
    }

    @Test func rewritePromptCarriesRules() {
        let prompt = CompanionPrompts.briefingRewrite(makeDay(), preferences: CompanionPreferences(firstName: "Johannes"))
        #expect(prompt.system.contains("Keine Diagnosen"))
        #expect(prompt.system.contains("110 Wörter"))
        #expect(prompt.system.contains("Das ist keine Diagnose."))
        #expect(!prompt.user.contains("Johannes"))
    }

    @Test func conferenceHasFourRolesAndDisagreementBlock() throws {
        let roles = CompanionPrompts.conferenceRoles
        #expect(roles.count == 4)
        #expect(roles.map(\.title) == ["Herz", "Schlaf", "Sport", "Ernährung"])
        #expect(roles.map(\.symbol) == ["heart", "bed.double", "figure.run", "fork.knife"])
        #expect(Set(roles.map(\.id)).count == 4)
        #expect(CompanionPrompts.conferenceTitle == "Expertenrunde")
        #expect(CompanionPrompts.conferenceDisclaimer.contains("keine echten Ärztinnen oder Ärzte"))

        let heart = try #require(roles.first)
        let round = CompanionPrompts.conferenceRound(role: heart, facts: "Nachtruhepuls: 58")
        #expect(round.system.contains("Kardiologische Sicht"))
        #expect(round.user.contains("Nachtruhepuls: 58"))

        let synthesis = CompanionPrompts.conferenceSynthesis(facts: "Nachtruhepuls: 58",
                                                             statements: roles.map { ($0, "Beitrag \($0.title)") })
        #expect(synthesis.system.contains("Hier sind wir uns nicht einig"))
        #expect(synthesis.user.contains("Ernährung: Beitrag Ernährung"))
    }
}

// MARK: - Engine end to end

@Suite("Begleiter – Engine")
struct CompanionEngineTests {
    private func sample(_ kind: SampleKind, _ value: Double, start: Date, end: Date? = nil, id: String) -> HealthSample {
        HealthSample(profileID: nil, kind: kind, value: value, unit: kind.canonicalUnit, start: start, end: end,
                     timeZoneIdentifier: "Europe/Berlin", source: .colmiRing, deviceID: "ring-test",
                     originalSampleID: id, importedAt: morning, quality: .valid, method: .deviceHistory)
    }

    /// 30 nights (23:00–06:30) with heart rate every 10 minutes, ring HRV, sleep duration and morning steps.
    private func syntheticSamples() -> [HealthSample] {
        var samples: [HealthSample] = []
        for offset in -29...0 {
            let bedtime = berlin(dayOffset: offset - 1, hour: 23)
            let wake = berlin(dayOffset: offset, hour: 6, minute: 30)
            let nightLevel = 52 + Double((offset + 30) % 5)
            var time = bedtime
            var index = 0
            while time < wake {
                samples.append(sample(.heartRate, nightLevel + Double(index % 3), start: time, id: "hr-\(offset)-\(index)"))
                if index % 6 == 0 {
                    samples.append(sample(.ringHRV, 40 + Double((offset + 30) % 7), start: time, id: "hrv-\(offset)-\(index)"))
                }
                time = time.addingTimeInterval(600)
                index += 1
            }
            samples.append(sample(.sleepDuration, 7.5 * 3_600, start: bedtime, end: wake, id: "sleep-\(offset)"))
            for minute in stride(from: 35, through: 45, by: 5) {
                let start = berlin(dayOffset: offset, hour: 6, minute: minute)
                samples.append(sample(.heartRate, 70, start: start, id: "hr-morning-\(offset)-\(minute)"))
                samples.append(sample(.steps, 120, start: start, end: start.addingTimeInterval(300), id: "steps-\(offset)-\(minute)"))
            }
            if offset < 0 {
                let evening = berlin(dayOffset: offset, hour: 18)
                samples.append(sample(.steps, 8_000, start: berlin(dayOffset: offset, hour: 9), end: evening, id: "steps-day-\(offset)"))
            }
        }
        return samples
    }

    @Test func runProducesSafeCompleteBriefing() {
        let input = CompanionInput(now: morning, calendar: briefingCalendar, samples: syntheticSamples(),
                                   preferences: CompanionPreferences(firstName: "Johannes"), birthYear: 1981,
                                   confirmedWake: berlin(hour: 6, minute: 32), weather: makeWeather())
        let day = CompanionEngine.run(input)
        let briefing = day.briefing

        #expect(briefing.actions.count == 3)
        #expect(briefing.headline == "Guten Morgen, Johannes.")
        #expect(briefing.sections.first?.kind == .greeting)
        #expect(briefing.sections.contains { $0.kind == .night })
        #expect(briefing.sections.contains { $0.kind == .outlook })
        #expect(briefing.sections.contains { $0.kind == .infection })
        #expect(briefing.dayType == day.dayType)
        #expect(day.bodyWeather != nil)
        #expect(day.forecastOutcome == nil)
        #expect(words(briefing.spokenScript) <= MorningBriefingComposer.maxSpokenWords)
        for section in briefing.sections {
            #expect(CompanionSafety.violations(in: section.text).isEmpty, "\(section.kind): \(section.text)")
        }
        let facts = CompanionPrompts.minimalFacts(day)
        #expect(!facts.contains("Johannes"))
        #expect(!facts.contains("ring-test"))
    }
}
