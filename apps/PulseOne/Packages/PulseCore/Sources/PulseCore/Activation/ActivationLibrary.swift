import Foundation

// Begleiter "Aktivierung": own bodyweight entries the Coach library lacks, plus the progression ladders.
// The Coach library is reused, not copied (AKTIVIERUNG-KONZEPT §2). Own entries live as an extension of
// `ExerciseLibrary` so the Coach file stays untouched; `ActivationLibrary.exercise(_:)` is the single lookup.

extension ExerciseLibrary {
    /// Own activation entries (PULSE ONE texts). Ids never collide with `ExerciseLibrary.all`.
    public static let activationEntries: [Exercise] = [
        // Push
        Exercise(id: "incline-pushup", name: "Schräger Liegestütz", steps: [
            "Hände schulterbreit auf eine stabile Tischkante oder Bank.",
            "Körper gerade wie ein Brett, Brust zur Kante senken.",
            "Kraftvoll zurückdrücken."
        ], pattern: .push, uses: [.activation, .snack, .strength], difficulty: 2, loads: [.shoulder, .elbowWrist],
                 dose: "3 × 10", easier: "Liegestütz an der Wand", harder: "Liegestütz auf den Knien",
                 safety: "Nur an Möbeln, die sicher stehen und nicht wegrutschen."),
        Exercise(id: "diamond-pushup", name: "Liegestütz eng", steps: [
            "Hände unter der Brust, Daumen und Zeigefinger bilden ein Dreieck.",
            "Körper gerade, Ellbogen nah am Körper nach hinten führen.",
            "Brust zu den Händen senken, hochdrücken."
        ], pattern: .push, uses: [.activation, .strength], difficulty: 4, loads: [.shoulder, .elbowWrist],
                 dose: "3 × 6", easier: "Liegestütz", harder: "Liegestütz mit erhöhten Füßen",
                 safety: "Handgelenke vorher kreisen, bei Ziehen die Hände etwas weiter stellen."),
        Exercise(id: "decline-pushup", name: "Liegestütz mit erhöhten Füßen", steps: [
            "Füße auf eine Stufe oder einen Stuhl, Hände schulterbreit am Boden.",
            "Körper gerade, Becken nicht durchhängen lassen.",
            "Brust zum Boden senken, hochdrücken."
        ], pattern: .push, uses: [.activation, .strength], difficulty: 4, loads: [.shoulder, .elbowWrist],
                 dose: "3 × 6", easier: "Liegestütz eng", harder: "Füße höher stellen",
                 safety: "Erhöhung muss rutschfest stehen."),
        // Core
        Exercise(id: "knee-plank", name: "Unterarmstütz auf den Knien", steps: [
            "Unterarme unter den Schultern, Knie am Boden.",
            "Körper von Knie bis Kopf gerade, Bauch leicht anspannen.",
            "Ruhig weiteratmen und halten."
        ], pattern: .core, uses: [.activation, .snack, .strength], difficulty: 1, loads: [.shoulder],
                 dose: "3 × 20 s", harder: "Unterarmstütz",
                 safety: "Unterlage unter die Knie legen, kein Hohlkreuz."),
        Exercise(id: "plank", name: "Unterarmstütz", steps: [
            "Unterarme unter den Schultern, Füße hüftbreit.",
            "Körper gerade wie ein Brett, Gesäß und Bauch fest.",
            "Ruhig weiteratmen und halten."
        ], pattern: .core, uses: [.activation, .snack, .strength], difficulty: 2, loads: [.shoulder],
                 dose: "3 × 30 s", easier: "Unterarmstütz auf den Knien", harder: "Stütz mit Schultertippen",
                 safety: "Becken nicht durchhängen lassen, sonst kürzer halten."),
        Exercise(id: "plank-shoulder-tap", name: "Stütz mit Schultertippen", steps: [
            "Hoher Stütz auf den Händen, Füße etwas breiter.",
            "Abwechselnd mit einer Hand die andere Schulter antippen.",
            "Becken bleibt ruhig, nicht schaukeln."
        ], pattern: .core, uses: [.activation, .strength], difficulty: 3, loads: [.shoulder, .elbowWrist],
                 dose: "3 × 30 s", easier: "Unterarmstütz", harder: "Hohlkörper",
                 safety: "Langsam tippen, Rumpf fest."),
        Exercise(id: "hollow-hold", name: "Hohlkörper", steps: [
            "Rückenlage, unterer Rücken drückt in den Boden.",
            "Arme und Beine gestreckt leicht anheben.",
            "Halten, ruhig atmen."
        ], pattern: .core, uses: [.activation, .strength], difficulty: 3, loads: [.back],
                 dose: "3 × 20 s", easier: "Knie angewinkelt", harder: "Arme über den Kopf",
                 safety: "Hebt sich der untere Rücken, Beine höher halten."),
        // Pull
        Exercise(id: "table-row", name: "Rudern unter dem Tisch", steps: [
            "Unter einen stabilen Tisch legen, Kante schulterbreit greifen.",
            "Körper gerade, Brust zur Tischkante ziehen.",
            "Langsam ablassen."
        ], pattern: .pull, uses: [.activation, .strength], difficulty: 2, loads: [.shoulder, .elbowWrist],
                 dose: "3 × 8", easier: "Knie stärker beugen", harder: "Beine gestreckt",
                 safety: "Nur an einem schweren Tisch, der nicht kippen kann."),
        Exercise(id: "dead-hang", name: "Hängen", steps: [
            "Stange schulterbreit greifen, Füße vom Boden lösen.",
            "Schultern leicht aktiv, nicht ganz locker hängen.",
            "Halten, dann kontrolliert absteigen."
        ], pattern: .pull, uses: [.activation, .strength], difficulty: 2, equipment: [.pullUpBar],
                 loads: [.shoulder, .elbowWrist], dose: "3 × 20 s", easier: "Füße leicht am Boden lassen",
                 harder: "Schulterblatt-Zug", safety: "Stange vorher auf festen Sitz prüfen."),
        Exercise(id: "scapular-pull", name: "Schulterblatt-Zug", steps: [
            "Mit gestreckten Armen an der Stange hängen.",
            "Schulterblätter nach unten und hinten ziehen, Körper hebt sich etwas.",
            "Langsam wieder lösen."
        ], pattern: .pull, uses: [.activation, .strength], difficulty: 3, equipment: [.pullUpBar],
                 loads: [.shoulder, .elbowWrist], dose: "3 × 6", easier: "Hängen", harder: "Klimmzug langsam ablassen",
                 safety: "Arme bleiben gestreckt, Bewegung kommt aus den Schultern."),
        Exercise(id: "pullup", name: "Klimmzug", steps: [
            "Stange etwas breiter als schulterbreit greifen.",
            "Brust zur Stange ziehen, bis das Kinn darüber ist.",
            "Kontrolliert ganz ablassen."
        ], pattern: .pull, uses: [.activation, .strength], difficulty: 5, equipment: [.pullUpBar],
                 loads: [.shoulder, .elbowWrist], dose: "3 × 4", easier: "Klimmzug langsam ablassen",
                 safety: "Nicht schwingen, nur saubere Wiederholungen zählen."),
        // Legs
        Exercise(id: "split-squat", name: "Geteilte Kniebeuge", steps: [
            "Schrittstellung, hintere Ferse angehoben.",
            "Senkrecht nach unten, bis das hintere Knie fast den Boden berührt.",
            "Hochdrücken, nach den Wiederholungen Seite wechseln."
        ], pattern: .lunge, uses: [.activation, .strength], difficulty: 3, loads: [.knee, .hip],
                 dose: "3 × 8 je Seite", easier: "Ausfallschritt rückwärts", harder: "Hinterer Fuß erhöht",
                 safety: "Vorderes Knie zeigt in Richtung Zehen."),
        // Cardio
        Exercise(id: "marching", name: "Marschieren auf der Stelle", steps: [
            "Aufrecht stehen.", "Knie abwechselnd zügig anheben, Arme schwingen mit.", "Gleichmäßig atmen."
        ], pattern: .endurance, uses: [.activation, .snack], difficulty: 1, dose: "60 s",
                 harder: "Hampelmann", safety: "Tempo so wählen, dass Sprechen noch geht."),
        Exercise(id: "jumping-jacks", name: "Hampelmann", steps: [
            "Füße zusammen, Arme seitlich.",
            "Mit einem kleinen Sprung Beine öffnen, Arme über den Kopf.",
            "Zurückspringen, locker im Rhythmus."
        ], pattern: .jump, uses: [.activation, .snack], difficulty: 2, loads: [.knee, .ankleFoot], dose: "30 ×",
                 easier: "Ohne Sprung seitlich tippen", harder: "Bergsteiger",
                 safety: "Weich auf dem Vorfuß landen."),
        Exercise(id: "mountain-climbers", name: "Bergsteiger", steps: [
            "Hoher Stütz auf den Händen.", "Knie abwechselnd zügig zur Brust ziehen.", "Becken bleibt tief."
        ], pattern: .endurance, uses: [.activation, .snack], difficulty: 3, loads: [.shoulder, .elbowWrist, .hip],
                 dose: "30 ×", easier: "Langsam im Wechsel", safety: "Schultern über den Händen halten."),
        // Back
        Exercise(id: "superman", name: "Rückenstrecker am Boden", steps: [
            "Bauchlage, Arme nach vorn gestreckt.",
            "Arme und Beine gleichzeitig leicht anheben, Blick zum Boden.",
            "Kurz halten, langsam ablegen."
        ], pattern: .hinge, uses: [.activation, .strength], difficulty: 2, loads: [.back], dose: "2 × 10",
                 easier: "Nur Arme oder nur Beine anheben", safety: "Kopf in Verlängerung der Wirbelsäule.")
    ]
}

public enum ActivationLibrary {
    /// Own activation entries (see `ExerciseLibrary.activationEntries`).
    public static var all: [Exercise] { ExerciseLibrary.activationEntries }

    /// Single lookup: own entries first, then the Coach library.
    public static func exercise(_ id: String) -> Exercise? {
        if let own = ExerciseLibrary.activationEntries.first(where: { $0.id == id }) { return own }
        return ExerciseLibrary.exercise(id)
    }

    /// Exercise ids of a family, easiest first.
    public static func ladder(_ family: ActivationFamily) -> [String] {
        switch family {
        case .push: ["wall-pushup", "incline-pushup", "knee-pushup", "pushup", "diamond-pushup", "decline-pushup"]
        case .pull: ["table-row", "dead-hang", "scapular-pull", "pullup-negative", "pullup"]
        case .core: ["knee-plank", "plank", "plank-shoulder-tap", "hollow-hold"]
        case .legs: ["chair-squat", "squat", "reverse-lunge", "split-squat"]
        case .cardio: ["marching", "jumping-jacks", "mountain-climbers"]
        case .mobility: ["arm-circles", "hip-circles", "cat-cow", "breathing-box"]
        }
    }

    /// The ladder filtered by equipment, limitations and medical clearance (difficulty ≤ 2).
    /// Without a pull-up bar but with bands, band rowing joins the pull ladder after table rowing.
    public static func allowedLadder(_ family: ActivationFamily, coach: CoachPreferences) -> [String] {
        var ids: [String] = ladder(family)
        if family == .pull && !coach.equipment.contains(.pullUpBar) && coach.equipment.contains(.bands) {
            ids.insert("band-row", at: 1)
        }
        return ids.filter { id in
            guard let entry = ActivationLibrary.exercise(id) else { return false }
            return isAllowed(entry, coach: coach)
        }
    }

    static func isAllowed(_ exercise: Exercise, coach: CoachPreferences) -> Bool {
        if !exercise.equipment.isSubset(of: coach.equipment) { return false }
        if !exercise.loads.isDisjoint(with: coach.limitations) { return false }
        if coach.needsMedicalClearance && exercise.difficulty > 2 { return false }
        return true
    }

    /// Holds and timed work: the target is seconds, not repetitions.
    public static func isHold(_ id: String) -> Bool {
        holdIDs.contains(id)
    }

    private static let holdIDs: Set<String> = ["knee-plank", "plank", "plank-shoulder-tap", "hollow-hold", "dead-hang"]

    /// Best clean set at which a family moves to the next ladder step (reps; core in seconds).
    public static let promoteAt: [ActivationFamily: Int] = [
        .push: 15, .pull: 8, .core: 60, .legs: 20, .cardio: 40
    ]

    /// Promotion threshold for one exercise: dead hang uses 45 s, other holds the core value.
    static func promoteThreshold(_ id: String, family: ActivationFamily) -> Int {
        if id == "dead-hang" { return 45 }
        if isHold(id) { return promoteAt[.core] ?? 60 }
        return promoteAt[family] ?? 15
    }

    /// Start level for a family from the Coach fitness level, clamped to the allowed ladder.
    /// When nothing in the family is allowed, the unclamped default is returned; the planner skips the family.
    public static func startLevel(_ family: ActivationFamily, coach: CoachPreferences, now: Date) -> ActivationLevel {
        let preferred: (id: String, best: Int) = defaultStart(family, level: coach.level)
        let allowed: [String] = allowedLadder(family, coach: coach)
        if allowed.isEmpty || allowed.contains(preferred.id) {
            return ActivationLevel(family: family, exerciseID: preferred.id, best: preferred.best, updatedAt: now)
        }
        let full: [String] = ladder(family)
        let preferredIndex: Int = full.firstIndex(of: preferred.id) ?? 0
        var chosen: String = allowed[0]
        for id in allowed {
            let index: Int = full.firstIndex(of: id) ?? 0
            if index <= preferredIndex { chosen = id }
        }
        let best: Int = clampedStartBest(chosen, family: family, level: coach.level)
        return ActivationLevel(family: family, exerciseID: chosen, best: best, updatedAt: now)
    }

    private static func defaultStart(_ family: ActivationFamily, level: FitnessLevel) -> (id: String, best: Int) {
        switch family {
        case .push:
            switch level {
            case .beginner: return ("knee-pushup", 6)
            case .active: return ("pushup", 10)
            case .trained: return ("pushup", 20)
            case .performance: return ("diamond-pushup", 12)
            }
        case .pull:
            switch level {
            case .beginner: return ("dead-hang", 20)
            case .active: return ("pullup-negative", 3)
            case .trained: return ("pullup", 6)
            case .performance: return ("pullup", 12)
            }
        case .core:
            switch level {
            case .beginner: return ("plank", 20)
            case .active: return ("plank", 40)
            case .trained: return ("plank", 60)
            case .performance: return ("hollow-hold", 30)
            }
        case .legs:
            switch level {
            case .beginner: return ("squat", 10)
            case .active: return ("squat", 15)
            case .trained: return ("squat", 20)
            case .performance: return ("split-squat", 10)
            }
        case .cardio:
            switch level {
            case .beginner: return ("jumping-jacks", 20)
            case .active: return ("jumping-jacks", 30)
            case .trained: return ("jumping-jacks", 40)
            case .performance: return ("mountain-climbers", 30)
            }
        case .mobility:
            return ("arm-circles", 30)
        }
    }

    private static func clampedStartBest(_ id: String, family: ActivationFamily, level: FitnessLevel) -> Int {
        if id == "table-row" || id == "band-row" {
            switch level {
            case .beginner: return 6
            case .active: return 8
            case .trained: return 10
            case .performance: return 12
            }
        }
        if isHold(id) { return 20 }
        if family == .mobility { return 30 }
        let threshold: Int = promoteThreshold(id, family: family)
        let start: Int = Int(Double(threshold) * 0.6)
        return max(3, start)
    }
}
