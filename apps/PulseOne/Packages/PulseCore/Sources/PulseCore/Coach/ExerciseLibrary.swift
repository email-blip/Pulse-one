import Foundation

// Own exercise texts (COACH-ENGINE-SPEC §5.2 "Eigene Einträge"). The wger import (CC-BY-SA, with
// attribution per entry) is a separate later step; until then every entry here is written by us.

public enum MovementPattern: String, Codable, CaseIterable, Sendable {
    case push, pull, squat, hinge, lunge, core, endurance, mobility, breathing, balance, jump
}

/// Where an exercise fits in the day.
public enum ExerciseUse: String, Codable, CaseIterable, Sendable {
    case activation, strength, snack, recovery, prevention
}

public struct Exercise: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let steps: [String]
    public let pattern: MovementPattern
    public let uses: Set<ExerciseUse>
    /// 1 (very easy) … 5 (very hard).
    public let difficulty: Int
    /// Empty = no equipment needed.
    public let equipment: Set<Equipment>
    /// Regions this exercise loads; excluded when the person has a limitation there.
    public let loads: Set<BodyRegion>
    /// Standard dose, e.g. "2 × 10" or "60 s".
    public let dose: String
    public let easier: String?
    public let harder: String?
    public let safety: String
    /// Origin and license of the entry (spec §5.1).
    public let origin: String
    /// Only offered when this sport is chosen (prevention for football, complement for riding).
    public let sport: Sport?

    public init(id: String, name: String, steps: [String], pattern: MovementPattern, uses: Set<ExerciseUse>,
                difficulty: Int, equipment: Set<Equipment> = [], loads: Set<BodyRegion> = [], dose: String,
                easier: String? = nil, harder: String? = nil, safety: String, origin: String = "PULSE ONE (eigener Text)",
                sport: Sport? = nil) {
        self.id = id
        self.name = name
        self.steps = steps
        self.pattern = pattern
        self.uses = uses
        self.difficulty = difficulty
        self.equipment = equipment
        self.loads = loads
        self.dose = dose
        self.easier = easier
        self.harder = harder
        self.safety = safety
        self.origin = origin
        self.sport = sport
    }
}

public enum ExerciseLibrary {
    public static func exercise(_ id: String) -> Exercise? { all.first { $0.id == id } }

    /// Exercises allowed for these preferences: equipment present, no limited region loaded,
    /// not harder than the level allows, and sport-bound entries only for chosen sports.
    public static func allowed(for use: ExerciseUse, preferences: CoachPreferences) -> [Exercise] {
        let maxDifficulty: Int = switch preferences.level {
        case .beginner: 2
        case .active: 3
        case .trained: 4
        case .performance: 5
        }
        return all.filter { e in
            e.uses.contains(use)
                && e.equipment.isSubset(of: preferences.equipment)
                && e.loads.isDisjoint(with: preferences.limitations)
                && e.difficulty <= maxDifficulty
                && (e.sport.map { preferences.sports.contains($0) } ?? true)
        }
    }

    /// A deterministic pick of `count` exercises, rotating by day so the plan varies without randomness.
    public static func pick(_ use: ExerciseUse, count: Int, preferences: CoachPreferences, dayIndex: Int) -> [Exercise] {
        let pool = allowed(for: use, preferences: preferences)
        guard !pool.isEmpty, count > 0 else { return [] }
        // Sport-bound entries first so a chosen sport is visible in the plan.
        let ordered = pool.filter { $0.sport != nil } + pool.filter { $0.sport == nil }
        let start = ordered.count > count ? (dayIndex * count) % ordered.count : 0
        let sportBound = ordered.filter { $0.sport != nil }.prefix(count)
        var result = Array(sportBound)
        var i = start
        while result.count < min(count, ordered.count) {
            let candidate = ordered[i % ordered.count]
            if !result.contains(candidate) { result.append(candidate) }
            i += 1
        }
        return result
    }

    public static let all: [Exercise] = [
        // Activation and mobility
        Exercise(id: "breathing-box", name: "Ruhige Atmung", steps: [
            "Aufrecht sitzen oder stehen.", "4 Sekunden durch die Nase einatmen.",
            "4 Sekunden halten, 6 Sekunden langsam ausatmen.", "Wiederholen, Schultern locker lassen."
        ], pattern: .breathing, uses: [.activation, .recovery], difficulty: 1, dose: "2 min",
                 safety: "Bei Schwindel normal weiteratmen und pausieren."),
        Exercise(id: "cat-cow", name: "Katze und Kuh", steps: [
            "Vierfüßlerstand, Hände unter den Schultern.", "Rücken langsam rund machen, Kinn zur Brust.",
            "Dann Brust nach vorn schieben, Blick leicht nach vorn.", "Im Atemrhythmus wechseln."
        ], pattern: .mobility, uses: [.activation, .recovery], difficulty: 1, loads: [.elbowWrist], dose: "8 ×",
                 easier: "Im Sitzen mit Händen auf den Knien", safety: "Nur im schmerzfreien Bereich bewegen."),
        Exercise(id: "arm-circles", name: "Armkreisen", steps: [
            "Aufrecht stehen, Arme seitlich.", "Kleine Kreise nach vorn, langsam größer werden.",
            "Dann rückwärts kreisen."
        ], pattern: .mobility, uses: [.activation, .snack], difficulty: 1, loads: [.shoulder], dose: "je Richtung 10 ×",
                 safety: "Kreise nur so groß, wie es angenehm ist."),
        Exercise(id: "hip-circles", name: "Hüftkreisen", steps: [
            "Hüftbreit stehen, Hände an die Hüfte.", "Becken langsam im Kreis bewegen.", "Richtung wechseln."
        ], pattern: .mobility, uses: [.activation, .recovery, .snack], difficulty: 1, loads: [.hip], dose: "je Richtung 8 ×",
                 safety: "Oberkörper ruhig halten."),
        Exercise(id: "thoracic-rotation", name: "Brustwirbelsäule drehen", steps: [
            "Seitlich liegen, Knie angewinkelt, Arme nach vorn.", "Oberen Arm wie ein Buch nach hinten öffnen.",
            "Blick folgt der Hand, kurz halten, zurück."
        ], pattern: .mobility, uses: [.activation, .recovery], difficulty: 1, loads: [.back, .shoulder], dose: "je Seite 6 ×",
                 safety: "Knie bleiben aufeinander liegen."),
        Exercise(id: "calf-raise", name: "Fersenheben", steps: [
            "Hüftbreit stehen, eine Hand an der Wand.", "Langsam auf die Zehenspitzen.", "Kontrolliert absenken."
        ], pattern: .balance, uses: [.activation, .snack, .strength], difficulty: 1, loads: [.ankleFoot], dose: "2 × 12",
                 harder: "Einbeinig", safety: "Langsam absenken, nicht federn."),
        Exercise(id: "hamstring-stretch", name: "Rückseite Oberschenkel dehnen", steps: [
            "Ein Bein gestreckt auf eine niedrige Stufe legen.", "Rücken lang, Oberkörper leicht nach vorn neigen.",
            "Halten, ruhig atmen, Seite wechseln."
        ], pattern: .mobility, uses: [.recovery], difficulty: 1, dose: "je Seite 30 s",
                 safety: "Ziehen ja, Schmerz nein."),
        Exercise(id: "hip-flexor-stretch", name: "Hüftbeuger dehnen", steps: [
            "Halber Kniestand, hinteres Knie auf einer Unterlage.", "Becken leicht nach vorn schieben.",
            "Halten, Seite wechseln."
        ], pattern: .mobility, uses: [.recovery], difficulty: 1, loads: [.knee], dose: "je Seite 30 s",
                 safety: "Unterlage unter das Knie legen."),
        // Snacks
        Exercise(id: "stairs", name: "Treppe gehen", steps: [
            "Eine oder zwei Etagen zügig hoch.", "Gemütlich wieder runter."
        ], pattern: .endurance, uses: [.snack], difficulty: 1, loads: [.knee], dose: "2 min",
                 safety: "Am Geländer festhalten, wenn nötig."),
        Exercise(id: "walk-short", name: "Kurz gehen", steps: [
            "Aufstehen und ein paar Minuten gehen, drinnen oder draußen."
        ], pattern: .endurance, uses: [.snack, .recovery], difficulty: 1, dose: "3 min",
                 safety: "Keine."),
        Exercise(id: "chair-squat", name: "Aufstehen vom Stuhl", steps: [
            "Vorn auf einen Stuhl setzen, Füße hüftbreit.", "Ohne Hände aufstehen.", "Langsam wieder hinsetzen."
        ], pattern: .squat, uses: [.snack, .strength], difficulty: 1, loads: [.knee, .hip], dose: "10 ×",
                 harder: "Kniebeuge ohne Stuhl", safety: "Knie zeigen in Richtung Zehen."),
        // Strength (bodyweight ladder)
        Exercise(id: "squat", name: "Kniebeuge", steps: [
            "Füße etwas weiter als hüftbreit.", "Hüfte nach hinten und unten, Brust bleibt offen.",
            "So tief es sauber geht, dann hochdrücken."
        ], pattern: .squat, uses: [.strength], difficulty: 2, loads: [.knee, .hip], dose: "3 × 10",
                 easier: "Aufstehen vom Stuhl", harder: "Kniebeuge mit Kurzhanteln", safety: "Fersen bleiben am Boden."),
        Exercise(id: "wall-pushup", name: "Liegestütz an der Wand", steps: [
            "Hände schulterbreit an die Wand.", "Körper gerade, Brust zur Wand senken.", "Zurückdrücken."
        ], pattern: .push, uses: [.strength], difficulty: 1, loads: [.shoulder, .elbowWrist], dose: "3 × 10",
                 harder: "Liegestütz auf den Knien", safety: "Kein Hohlkreuz."),
        Exercise(id: "knee-pushup", name: "Liegestütz auf den Knien", steps: [
            "Hände schulterbreit, Knie am Boden.", "Körper von Knie bis Kopf gerade.", "Brust zum Boden, hochdrücken."
        ], pattern: .push, uses: [.strength], difficulty: 2, equipment: [.mat], loads: [.shoulder, .elbowWrist], dose: "3 × 8",
                 easier: "Liegestütz an der Wand", harder: "Liegestütz", safety: "Ellbogen leicht am Körper."),
        Exercise(id: "pushup", name: "Liegestütz", steps: [
            "Hände schulterbreit, Körper gerade wie ein Brett.", "Brust bis kurz über den Boden.", "Kraftvoll hochdrücken."
        ], pattern: .push, uses: [.strength], difficulty: 3, loads: [.shoulder, .elbowWrist], dose: "3 × 8",
                 easier: "Liegestütz auf den Knien", safety: "Rumpf fest, Becken nicht durchhängen lassen."),
        Exercise(id: "glute-bridge", name: "Beckenheben", steps: [
            "Rückenlage, Füße aufgestellt.", "Becken heben, bis Knie, Hüfte und Schulter eine Linie bilden.",
            "Kurz halten, langsam absenken."
        ], pattern: .hinge, uses: [.strength, .activation], difficulty: 1, equipment: [.mat], loads: [.hip], dose: "3 × 12",
                 harder: "Einbeiniges Beckenheben", safety: "Nicht ins Hohlkreuz drücken."),
        Exercise(id: "dead-bug", name: "Toter Käfer", steps: [
            "Rückenlage, Arme zur Decke, Knie über der Hüfte.", "Gegenüberliegenden Arm und Bein langsam strecken.",
            "Lendenwirbelsäule bleibt am Boden, Seite wechseln."
        ], pattern: .core, uses: [.strength, .prevention], difficulty: 2, equipment: [.mat], dose: "3 × 8 je Seite",
                 safety: "Langsam, unterer Rücken bleibt am Boden.", sport: nil),
        Exercise(id: "side-plank", name: "Seitstütz", steps: [
            "Seitlich auf den Unterarm stützen, Knie oder Füße am Boden.", "Becken heben, Körper gerade.", "Halten, Seite wechseln."
        ], pattern: .core, uses: [.strength], difficulty: 2, equipment: [.mat], loads: [.shoulder], dose: "3 × 20 s je Seite",
                 easier: "Mit Knien am Boden", safety: "Schulter über dem Ellbogen."),
        Exercise(id: "reverse-lunge", name: "Ausfallschritt rückwärts", steps: [
            "Aufrecht stehen.", "Ein Bein nach hinten setzen, beide Knie beugen.", "Mit dem vorderen Bein zurückdrücken."
        ], pattern: .lunge, uses: [.strength], difficulty: 3, loads: [.knee, .hip], dose: "3 × 8 je Seite",
                 easier: "Kniebeuge", safety: "Vorderes Knie über dem Fuß."),
        Exercise(id: "band-row", name: "Rudern mit Band", steps: [
            "Band auf Brusthöhe befestigen.", "Ellbogen nach hinten ziehen, Schulterblätter zusammen.", "Langsam zurück."
        ], pattern: .pull, uses: [.strength], difficulty: 2, equipment: [.bands], loads: [.elbowWrist], dose: "3 × 12",
                 safety: "Schultern bleiben unten."),
        Exercise(id: "dumbbell-row", name: "Rudern mit Kurzhantel", steps: [
            "Eine Hand und ein Knie auf eine Bank.", "Hantel zur Hüfte ziehen.", "Langsam ablassen."
        ], pattern: .pull, uses: [.strength], difficulty: 2, equipment: [.dumbbells], loads: [.back, .elbowWrist], dose: "3 × 10 je Seite",
                 safety: "Rücken gerade, nicht drehen."),
        Exercise(id: "goblet-squat", name: "Kniebeuge mit Kurzhantel", steps: [
            "Hantel vor der Brust halten.", "Tief in die Hocke, Brust offen.", "Hochdrücken."
        ], pattern: .squat, uses: [.strength], difficulty: 3, equipment: [.dumbbells], loads: [.knee, .hip, .back], dose: "3 × 10",
                 easier: "Kniebeuge", safety: "Gewicht so wählen, dass 2 Wiederholungen übrig bleiben."),
        Exercise(id: "kettlebell-deadlift", name: "Kreuzheben mit Kettlebell", steps: [
            "Kettlebell zwischen den Füßen.", "Hüfte nach hinten, Rücken gerade, greifen.", "Mit den Beinen hochdrücken, Hüfte strecken."
        ], pattern: .hinge, uses: [.strength], difficulty: 3, equipment: [.kettlebell], loads: [.back, .hip], dose: "3 × 10",
                 easier: "Beckenheben", safety: "Rücken bleibt gerade, nicht rund."),
        Exercise(id: "pullup-negative", name: "Klimmzug langsam ablassen", steps: [
            "Mit Hilfe eines Stuhls oben an die Stange.", "In 3–5 Sekunden langsam ablassen."
        ], pattern: .pull, uses: [.strength], difficulty: 4, equipment: [.pullUpBar], loads: [.shoulder, .elbowWrist], dose: "3 × 4",
                 easier: "Rudern mit Band", safety: "Nur so viele, wie sauber gehen."),
        // Sport-bound prevention and complements
        Exercise(id: "nordic-hamstring", name: "Nordic Hamstrings (mit Partner)", steps: [
            "Kniend, Partner hält die Fersen.", "Körper gerade langsam nach vorn sinken lassen.", "Mit den Händen abfangen."
        ], pattern: .hinge, uses: [.prevention], difficulty: 4, equipment: [.mat], loads: [.knee], dose: "2 × 5",
                 safety: "Langsam beginnen, Muskelkater ist anfangs üblich.", sport: .football),
        Exercise(id: "adductor-squeeze", name: "Adduktoren drücken", steps: [
            "Rückenlage, Ball oder Kissen zwischen die Knie.", "Knie 5 Sekunden fest zusammendrücken.", "Lösen."
        ], pattern: .core, uses: [.prevention], difficulty: 1, equipment: [.mat], loads: [.hip], dose: "2 × 8",
                 safety: "Druck nur so stark, dass es schmerzfrei bleibt.", sport: .football),
        Exercise(id: "single-leg-balance", name: "Einbeinstand", steps: [
            "Auf einem Bein stehen, Knie leicht gebeugt.", "Blick nach vorn, halten.", "Seite wechseln."
        ], pattern: .balance, uses: [.prevention, .activation], difficulty: 1, loads: [.ankleFoot], dose: "je Seite 30 s",
                 harder: "Mit geschlossenen Augen", safety: "In Reichweite einer Wand üben.", sport: .riding),
        Exercise(id: "hip-opener-90-90", name: "Hüftöffner 90/90", steps: [
            "Sitzen, beide Knie 90 Grad gebeugt, eins vorn, eins seitlich.", "Aufrecht sitzen, Oberkörper leicht über das vordere Bein.",
            "Halten, Seite wechseln."
        ], pattern: .mobility, uses: [.prevention, .recovery], difficulty: 2, equipment: [.mat], loads: [.hip, .knee], dose: "je Seite 45 s",
                 safety: "Nur im angenehmen Bereich.", sport: .riding),
        Exercise(id: "rowing-technique", name: "Rudertechnik: Beine, Rumpf, Arme", steps: [
            "Erst die Beine strecken, dann den Oberkörper leicht zurück, zuletzt die Arme ziehen.",
            "Zurück in umgekehrter Reihenfolge.", "Ruhig, mit niedriger Schlagzahl."
        ], pattern: .pull, uses: [.prevention], difficulty: 2, equipment: [.rower], loads: [.back], dose: "5 min",
                 safety: "Rücken lang, nicht mit den Armen beginnen.", sport: .rowing)
    ]
}
