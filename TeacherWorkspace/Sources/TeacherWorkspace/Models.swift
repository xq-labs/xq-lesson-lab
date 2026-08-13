import Foundation

enum ArtifactType: String, Codable {
    case rubric, activity, pog, quiz, email

    var libraryName: String {
        switch self {
        case .rubric: return "Rubrics"
        case .activity: return "Activities"
        case .pog: return "Portraits of a Graduate"
        case .quiz: return "Quizzes"
        case .email: return "Email drafts"
        }
    }

    /// Inline editing exists only for the original three types so far.
    var supportsEditing: Bool {
        switch self {
        case .rubric, .activity, .pog: return true
        case .quiz, .email: return false
        }
    }
}

struct ArtifactRef: Equatable, Codable {
    var type: ArtifactType
    var id: String
}

struct RubricCriterion: Codable {
    var name: String
    /// Four cells: Beginning, Developing, Proficient, Advanced.
    var cells: [String]
}

struct Rubric: Identifiable, Codable {
    var id: String
    var title: String
    var sub: String
    var meta: String
    var criteria: [RubricCriterion]
}

struct Activity: Identifiable, Codable {
    var id: String
    var title: String
    var meta: String
    var desc: String
    var steps: [String]
}

struct PogCompetency: Codable {
    var name: String
    var desc: String
    var level: Int // 1...5
}

struct Pog: Identifiable, Codable {
    var id: String
    var title: String
    var sub: String
    var meta: String
    var comps: [PogCompetency]
}

struct QuizQuestion: Codable, Equatable {
    var prompt: String
    /// Multiple-choice options; empty for short-answer questions.
    var choices: [String] = []
    var answer: String = ""
}

struct Quiz: Identifiable, Codable {
    var id: String
    var title: String
    var sub: String
    var meta: String
    var questions: [QuizQuestion]
}

struct EmailDraft: Identifiable, Codable {
    var id: String
    /// The subject line doubles as the artifact title.
    var title: String
    var sub: String
    var meta: String
    var body: String
}

struct Chat: Identifiable, Codable {
    var id: String
    var title: String
}

/// A teacher-made grouping in the sidebar. Membership lives in
/// `AppState.chatFolder` rather than on `Chat`, so sample chats — which aren't
/// persisted — can be filed too.
struct Folder: Identifiable, Codable, Equatable {
    var id: String
    var name: String
}

struct ChatGroup: Identifiable {
    var id: String { name }
    var name: String
    var chats: [Chat]
}

struct Message: Identifiable, Codable {
    var id = UUID()
    var role: Role
    var text: String
    var artifact: ArtifactRef?
    var source: String?
    /// Names of files/artifacts attached to this (user) message — shown as chips.
    var attachmentNames: [String]?
    /// The attachments' extracted text: sent to the model with every turn
    /// that includes this message, but never rendered in the bubble.
    var hiddenContext: String?
    /// True while an artifact block is still streaming in for this message.
    /// Transient — not persisted (excluded from CodingKeys).
    var isDraftingArtifact = false

    enum Role: String, Codable { case user, assistant }

    enum CodingKeys: String, CodingKey {
        case id, role, text, artifact, source, attachmentNames, hiddenContext
    }

    /// Spelled out because the hand-written `init(from:)` below suppresses the
    /// memberwise one Swift would otherwise synthesize.
    init(id: UUID = UUID(), role: Role, text: String, artifact: ArtifactRef? = nil,
         source: String? = nil, attachmentNames: [String]? = nil,
         hiddenContext: String? = nil, isDraftingArtifact: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.artifact = artifact
        self.source = source
        self.attachmentNames = attachmentNames
        self.hiddenContext = hiddenContext
        self.isDraftingArtifact = isDraftingArtifact
    }

    /// Hand-written for one line of it: `artifact`.
    ///
    /// `ArtifactRef` carries an `ArtifactType`, which is a `String` enum, so a
    /// ref to a type added in a later version throws — and because
    /// `extraMessages` is non-Optional on `PersistedState`, that one throw
    /// fails the whole document and `load()` hands the teacher an empty app.
    /// Dropping the ref costs a clickable card; the message keeps its text.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(Role.self, forKey: .role)
        text = try c.decode(String.self, forKey: .text)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        attachmentNames = try c.decodeIfPresent([String].self, forKey: .attachmentNames)
        hiddenContext = try c.decodeIfPresent(String.self, forKey: .hiddenContext)
        artifact = try? c.decodeIfPresent(ArtifactRef.self, forKey: .artifact)
    }
}

// MARK: - Classroom (the teacher's real setup; drives the system prompt)

struct Student: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    /// Freeform teacher notes: strengths, growth areas, accommodations.
    var notes = ""
}

struct ClassSection: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""        // e.g. "Period 2 · Biology"
    var gradeLevel = ""  // e.g. "9th grade"
    var notes = ""       // current unit, context for the assistant
    var students: [Student] = []
}

struct Classroom: Codable, Equatable {
    var teacherName = ""
    var school = ""
    var subject = ""
    var classes: [ClassSection] = []
    /// True until the teacher edits anything — while set, the app shows the
    /// demo sample chats/artifacts alongside this (editable) demo classroom.
    var isDemo = true

    var firstName: String {
        teacherName.split(separator: " ").first.map(String.init) ?? teacherName
    }

    /// Nothing typed in yet — the state right after "Start fresh". An empty
    /// class card still counts as blank, so adding one doesn't withdraw the
    /// offer to put the demo data back.
    var isBlank: Bool {
        teacherName.isEmpty && school.isEmpty && subject.isEmpty
            && classes.allSatisfy {
                $0.name.isEmpty && $0.gradeLevel.isEmpty && $0.notes.isEmpty && $0.students.isEmpty
            }
    }

    static let demo = Classroom(
        teacherName: "Dana Alvarez",
        school: "Crestview High",
        subject: "Science",
        classes: [
            ClassSection(
                name: "Period 2 · Biology",
                gradeLevel: "9th grade",
                notes: "Photosynthesis unit in progress; exit tickets every Friday.",
                students: [
                    Student(name: "Maya Rodriguez", notes: "Strong decoding, weak inference on science texts."),
                    Student(name: "Jamal Carter", notes: "Ahead in the genetics unit; needs extension work."),
                    Student(name: "Sofia Kim", notes: "Catching up after a 4-day absence."),
                ]),
            ClassSection(
                name: "Period 4 · Env. Science",
                gradeLevel: "11th grade",
                notes: "Renewable energy debate prep; wetlands field trip on May 12.",
                students: []),
        ],
        isDemo: true)
}

enum SampleData {
    static let levels4 = ["Beginning", "Developing", "Proficient", "Advanced"]
    static let pogLabels = ["Emerging", "Developing", "Approaching", "Proficient", "Exemplary"]

    static let rubrics: [Rubric] = [
        Rubric(id: "r1", title: "Choice Board Product Rubric",
               sub: "Photosynthesis unit — scores any product option",
               meta: "Biology · 4 criteria · Updated today",
               criteria: [
                RubricCriterion(name: "Scientific Accuracy", cells: [
                    "Major misconceptions about inputs, outputs, or sequence.",
                    "Mostly accurate with one or two errors in the process.",
                    "Accurate description of inputs, outputs, and energy transfer.",
                    "Accurate and connects the process to cellular respiration."]),
                RubricCriterion(name: "Use of Evidence", cells: [
                    "No reference to class data or texts.",
                    "Mentions evidence without explaining it.",
                    "Uses class data or texts to support claims.",
                    "Synthesizes multiple sources, including own station data."]),
                RubricCriterion(name: "Communication", cells: [
                    "Ideas are hard to follow in the chosen format.",
                    "Ideas present but organization is loose.",
                    "Clear, organized, and suited to the chosen format.",
                    "Compelling and precise; strong scientific vocabulary."]),
                RubricCriterion(name: "Craft & Completion", cells: [
                    "Incomplete or rushed.",
                    "Complete but minimal effort in the format.",
                    "Complete, careful, and revised once.",
                    "Polished; shows revision and attention to audience."]),
               ]),
        Rubric(id: "r2", title: "Lab Report Rubric",
               sub: "Standard format for all wet labs",
               meta: "Biology · 3 criteria · Updated Mar 2",
               criteria: [
                RubricCriterion(name: "Hypothesis & Variables", cells: [
                    "Hypothesis missing or untestable.",
                    "Testable but variables unclear.",
                    "Testable hypothesis with variables identified.",
                    "Precise hypothesis with controls justified."]),
                RubricCriterion(name: "Data & Analysis", cells: [
                    "Data missing or disorganized.",
                    "Data recorded but not interpreted.",
                    "Data organized and interpreted correctly.",
                    "Analysis addresses error and uncertainty."]),
                RubricCriterion(name: "Conclusion", cells: [
                    "No claim about the hypothesis.",
                    "Claim made without evidence.",
                    "Claim supported by collected data.",
                    "Claim evaluated against limitations and next steps."]),
               ]),
        Rubric(id: "r3", title: "Persuasive Essay Rubric",
               sub: "Cross-curricular argument writing",
               meta: "ELA · 3 criteria · Updated Feb 18",
               criteria: [
                RubricCriterion(name: "Claim & Thesis", cells: [
                    "States a topic without a position.",
                    "Position stated but vague.",
                    "Clear, defensible claim frames the essay.",
                    "Nuanced claim acknowledging complexity."]),
                RubricCriterion(name: "Evidence & Reasoning", cells: [
                    "Little or no supporting evidence.",
                    "Evidence listed without reasoning.",
                    "Relevant evidence tied to the claim.",
                    "Evidence weighed against counterarguments."]),
                RubricCriterion(name: "Organization", cells: [
                    "No clear structure.",
                    "Structure present but uneven.",
                    "Logical flow with transitions.",
                    "Structure strengthens the argument."]),
               ]),
        Rubric(id: "r4", title: "Socratic Seminar Rubric",
               sub: "Discussion preparation and moves",
               meta: "ELA · 3 criteria · Updated Jan 30",
               criteria: [
                RubricCriterion(name: "Preparation", cells: [
                    "Arrives without annotations.",
                    "Partial annotations or questions.",
                    "Annotated text and prepared questions.",
                    "Preparation extends beyond assigned text."]),
                RubricCriterion(name: "Discussion Moves", cells: [
                    "Does not contribute.",
                    "Contributes without building on others.",
                    "Builds on peers and asks follow-ups.",
                    "Moves the group toward deeper questions."]),
                RubricCriterion(name: "Textual Evidence", cells: [
                    "No references to the text.",
                    "General references without citations.",
                    "Cites specific passages accurately.",
                    "Connects passages across texts."]),
               ]),
    ]

    static let activities: [Activity] = [
        Activity(id: "a1", title: "Photosynthesis Choice Board",
                 meta: "Biology · 45 min · Stations",
                 desc: "Four product options at three challenge tiers, built around inputs, outputs, and energy transfer.",
                 steps: [
                    "Launch (5 min): whole-class diagram check on inputs/outputs.",
                    "Sort students into tiers using latest exit-ticket data.",
                    "Stations (30 min): students pick one product option per tier.",
                    "Close (10 min): gallery share — one takeaway per group."]),
        Activity(id: "a2", title: "Cell City Analogy",
                 meta: "Biology · 60 min · Group project",
                 desc: "Teams map organelles to city infrastructure and defend their analogies.",
                 steps: [
                    "Assign teams of 3–4 and distribute the city map template.",
                    "Teams match 8 organelles to city systems with a one-line rationale.",
                    "Speed-round defense: each team justifies two analogies to another team."]),
        Activity(id: "a3", title: "Primary Source Gallery Walk",
                 meta: "History · 50 min · Whole class",
                 desc: "Six stations of primary sources with escalating analysis prompts.",
                 steps: [
                    "Post six sources around the room with prompt cards.",
                    "Groups rotate every 6 minutes, adding to shared annotations.",
                    "Debrief: each group synthesizes one source for the class."]),
        Activity(id: "a4", title: "Exit Ticket: Light Reactions",
                 meta: "Biology · 5 min · Individual",
                 desc: "Three-question quick check: one recall, one diagram label, one transfer question.",
                 steps: [
                    "Distribute in the last 5 minutes of class.",
                    "Collect and auto-sort responses by mastery band.",
                    "Results feed tomorrow’s grouping suggestions."]),
    ]

    static let pogs: [Pog] = [
        Pog(id: "p1", title: "Portrait of a Graduate — School Template",
            sub: "Crestview High · adopted 2025",
            meta: "5 competencies",
            comps: [
                PogCompetency(name: "Critical Thinking", desc: "Analyzes evidence, questions assumptions, and reasons through problems.", level: 3),
                PogCompetency(name: "Effective Communication", desc: "Expresses ideas clearly across formats and audiences.", level: 3),
                PogCompetency(name: "Collaboration", desc: "Contributes to shared goals and builds on others’ thinking.", level: 3),
                PogCompetency(name: "Self-Direction", desc: "Sets goals, monitors progress, and persists through setbacks.", level: 3),
                PogCompetency(name: "Civic Engagement", desc: "Connects learning to community needs and acts on them.", level: 3),
            ]),
        Pog(id: "p2", title: "Maya Rodriguez — PoG Draft",
            sub: "Period 2 · Biology · updated from exit tickets",
            meta: "5 competencies · 2 growth areas flagged",
            comps: [
                PogCompetency(name: "Critical Thinking", desc: "Strong on data tasks; inference on dense texts is the growth edge.", level: 3),
                PogCompetency(name: "Effective Communication", desc: "Clear verbally; written explanations still list rather than connect.", level: 2),
                PogCompetency(name: "Collaboration", desc: "Reliable partner; increasingly leads station work.", level: 4),
                PogCompetency(name: "Self-Direction", desc: "Uses checklists well; needs prompts to self-assess against rubrics.", level: 3),
                PogCompetency(name: "Civic Engagement", desc: "Engaged in wetlands project; hasn’t yet connected it to coursework.", level: 2),
            ]),
    ]

    static let classGroups: [ChatGroup] = [
        ChatGroup(name: "Period 2 · Biology", chats: [
            Chat(id: "c1", title: "Differentiate the photosynthesis lesson"),
            Chat(id: "c2", title: "Lab report feedback — batch 3"),
            Chat(id: "c3", title: "Quiz ideas: cell respiration"),
        ]),
        ChatGroup(name: "Period 4 · Env. Science", chats: [
            Chat(id: "c4", title: "Field trip permission letter"),
            Chat(id: "c5", title: "Debate prep: renewable energy"),
        ]),
    ]

    static let studentGroups: [ChatGroup] = [
        ChatGroup(name: "Maya Rodriguez", chats: [Chat(id: "c6", title: "Reading intervention plan")]),
        ChatGroup(name: "Jamal Carter", chats: [Chat(id: "c7", title: "Extension work — genetics")]),
        ChatGroup(name: "Sofia Kim", chats: [Chat(id: "c8", title: "Catch-up plan after absence")]),
    ]

    static let chatMeta: [String: String] = [
        "c1": "Period 2 · Biology", "c2": "Period 2 · Biology", "c3": "Period 2 · Biology",
        "c4": "Period 4 · Env. Science", "c5": "Period 4 · Env. Science",
        "c6": "Maya Rodriguez", "c7": "Jamal Carter", "c8": "Sofia Kim",
    ]

    static let baseMessages: [String: [Message]] = [
        "c1": [
            Message(role: .user, text: "I need to differentiate tomorrow’s photosynthesis lesson for Period 2. A few students are still shaky on inputs and outputs, and three finished the unit early."),
            Message(role: .assistant,
                    text: "Here’s a three-tier plan for tomorrow:\n\n1. Support tier — small-group station revisiting inputs/outputs with last week’s diagram sort.\n2. Core tier — a choice board with four product options at grade level.\n3. Extension tier — a design-an-experiment prompt on limiting factors for your three early finishers.\n\nI built the choice board as a reusable activity — open it to review the stations.",
                    artifact: ArtifactRef(type: .activity, id: "a1"),
                    source: "Context: Period 2 roster · Google Classroom"),
            Message(role: .user, text: "Great — draft a rubric for the choice board products too."),
            Message(role: .assistant,
                    text: "Done — a four-level rubric focused on scientific accuracy and communication rather than product type, so any option on the board can be scored with it.",
                    artifact: ArtifactRef(type: .rubric, id: "r1"),
                    source: "Saved to Drive · Rubrics folder"),
        ],
        "c2": [
            Message(role: .user, text: "Summarize the common feedback from batch 3 lab reports."),
            Message(role: .assistant, text: "Most reports lost points on data analysis — 9 of 24 described results without citing their own measurements. Conclusions were stronger than batch 2. Want me to draft a 10-minute mini-lesson on citing your own data?"),
        ],
        "c3": [
            Message(role: .user, text: "Give me 10 quiz questions on cell respiration, mixed difficulty."),
            Message(role: .assistant, text: "Drafted 10 questions — 4 recall, 4 application, 2 data-interpretation. Want them pushed to Period 2 as a Google Form in Classroom?"),
        ],
        "c4": [
            Message(role: .user, text: "Draft a permission letter for the wetlands field trip on May 12."),
            Message(role: .assistant, text: "Draft is ready — it covers logistics, the $8 cost with a waiver line, and photo consent. Your calendar shows a staff meeting that afternoon; I set the return time for 2:30. Want it prepped as an email to families via Gmail?"),
        ],
        "c5": [
            Message(role: .user, text: "Prep debate materials on renewable energy."),
            Message(role: .assistant, text: "I set up two source packets (pro and con) and a prep organizer. The Socratic Seminar rubric in your library could be adapted for scoring — want me to make a debate version?"),
        ],
        "c6": [
            Message(role: .user, text: "Put together a reading intervention plan for Maya based on her last three exit tickets."),
            Message(role: .assistant,
                    text: "Her exit tickets show strong decoding but weak inference on science texts. I sketched a 4-week plan pairing short passages with the claim-evidence frames she already uses in labs — and updated her Portrait of a Graduate draft to match. Open it to adjust the levels.",
                    artifact: ArtifactRef(type: .pog, id: "p2"),
                    source: "Context: exit tickets · PowerSchool"),
        ],
        "c7": [
            Message(role: .user, text: "Extension ideas for Jamal — he’s ahead in the genetics unit."),
            Message(role: .assistant, text: "Three options: a pedigree-analysis case study, a CRISPR ethics mini-debate, or mentoring the Punnett-square station. His PoG flags communication as a growth area — the mini-debate targets it directly."),
        ],
        "c8": [
            Message(role: .user, text: "Sofia missed four days — build a catch-up plan."),
            Message(role: .assistant, text: "Built a prioritized plan: the two must-do labs, one condensed reading with guided notes, and it skips the review game. Roughly 3 hours of work spread across this week, with the first lab during Thursday’s flex block per her schedule."),
        ],
    ]

    struct IntegrationDef {
        var key: String
        var name: String
        var initial: String
        var desc: String
    }

    static let integrationDefs: [IntegrationDef] = [
        IntegrationDef(key: "classroom", name: "Google Classroom", initial: "C", desc: "Rosters, assignments, and grades give the assistant class context."),
        IntegrationDef(key: "drive", name: "Google Drive", initial: "D", desc: "Rubrics and activities save straight to your teaching folders."),
        IntegrationDef(key: "sis", name: "PowerSchool SIS", initial: "P", desc: "Gradebook and attendance inform interventions and catch-up plans."),
        IntegrationDef(key: "gmail", name: "Gmail", initial: "M", desc: "Family emails drafted in chat, sent from your address."),
        IntegrationDef(key: "seesaw", name: "Seesaw", initial: "S", desc: "Pull student portfolio evidence into PoG updates."),
        IntegrationDef(key: "canvas", name: "Canvas LMS", initial: "C", desc: "Sync modules and assignments for cross-listed courses."),
    ]

    struct SkillDef {
        var key: String
        var name: String
        var icon: String
        var desc: String
    }

    /// Task-specific skills shown on the Plugins → Skills tab.
    static let skillDefs: [SkillDef] = [
        SkillDef(key: "rubric-builder", name: "Rubric Builder", icon: "tablecells",
                 desc: "Four-level rubrics in your school's format, ready to grade with."),
        SkillDef(key: "lesson-planner", name: "Lesson Planner", icon: "calendar",
                 desc: "Timed agendas that fit your periods, with materials lists."),
        SkillDef(key: "exit-tickets", name: "Exit Tickets", icon: "checklist",
                 desc: "Quick checks for understanding, scored against your rubrics."),
        SkillDef(key: "family-emails", name: "Family Emails", icon: "envelope",
                 desc: "Warm, clear notes home — drafted for your review, you send."),
        SkillDef(key: "differentiation", name: "Differentiation Coach", icon: "person.2",
                 desc: "Adapts tomorrow's lesson for the students in your roster."),
        SkillDef(key: "pog-updater", name: "PoG Updater", icon: "person.crop.square",
                 desc: "Turns recent work and observations into Portrait updates."),
    ]

    struct CalendarEvent: Identifiable {
        let id = UUID()
        var start: Date
        var end: Date
        var title: String
        var detail: String
    }

    /// Demo schedule anchored to "now" so it always looks live on stage.
    static func todaysSchedule(now: Date = Date()) -> [CalendarEvent] {
        func at(_ minutes: Int) -> Date { now.addingTimeInterval(TimeInterval(minutes * 60)) }
        return [
            CalendarEvent(start: at(-20), end: at(25), title: "Period 4 · Biology",
                          detail: "Photosynthesis lab · Room 118"),
            CalendarEvent(start: at(35), end: at(85), title: "Prep period",
                          detail: "Grade exit tickets · plan Friday review"),
            CalendarEvent(start: at(95), end: at(145), title: "Period 5 · Biology",
                          detail: "Photosynthesis lab · Room 118"),
            CalendarEvent(start: at(160), end: at(200), title: "Science dept. meeting",
                          detail: "Room 210 · curriculum review"),
            CalendarEvent(start: at(210), end: at(255), title: "Office hours",
                          detail: "Tutoring — Jamal, Sofia"),
        ]
    }

    struct Suggestion {
        var title: String
        var sub: String
        var seed: String
    }

    static let suggestions: [Suggestion] = [
        Suggestion(title: "Draft a rubric", sub: "Four levels, ready to grade with", seed: "Draft a 4-level rubric for "),
        Suggestion(title: "Plan a lesson", sub: "Timed agenda, saved to Activities", seed: "Create a lesson plan for "),
        Suggestion(title: "Make an exit ticket", sub: "Quick check for understanding", seed: "Create a 5-question exit ticket quiz on "),
        Suggestion(title: "Write home to families", sub: "Drafted for your review — you send it", seed: "Draft an email to families about "),
        Suggestion(title: "Differentiate for a student", sub: "Grounded in your roster notes", seed: "How should I adapt tomorrow’s lesson for "),
        Suggestion(title: "Update a student’s PoG", sub: "From recent work and observations", seed: "Update the Portrait of a Graduate for "),
    ]
}
