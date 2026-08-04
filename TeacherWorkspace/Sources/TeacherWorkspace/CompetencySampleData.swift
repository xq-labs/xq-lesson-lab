import Foundation

/// Sample data for the three competency-engine screens (Learner Profiles,
/// Community Graph, Project Matcher). Keyed by student name, matching the
/// convention already used by `SampleData.chatMeta`/`studentGroups` — not by
/// `Student.id`, since the demo roster in `Classroom.demo` is what these
/// screens are grounded in, and names there are stable.
extension SampleData {

    /// Shared roster for the Learner Profiles and Project Matcher student
    /// pickers — the same three named students from `Classroom.demo`'s
    /// Period 2 · Biology.
    static let competencyStudents = ["Maya Rodriguez", "Jamal Carter", "Sofia Kim"]

    // MARK: - Screen 2: Learner profiles

    static let learnerProfiles: [String: LearnerCompetencyProfile] = [
        "Maya Rodriguez": LearnerCompetencyProfile(
            studentName: "Maya Rodriguez",
            initials: "MR",
            gradeLabel: "9th grade · 12 artifacts · 9 competency claims confirmed",
            tags: ["Wetlands project", "Station leadership", "Data analysis"],
            scores: [
                CompetencyScore(name: "Analysis", score: 64),
                CompetencyScore(name: "Collaboration", score: 82),
                CompetencyScore(name: "Public communication", score: 46),
            ],
            confidenceTrend: [
                ConfidencePoint(value: 48, note: nil),
                ConfidencePoint(value: 52, note: nil),
                ConfidencePoint(value: 55, note: nil),
                ConfidencePoint(value: 44, note: "Dip"),
                ConfidencePoint(value: 50, note: nil),
                ConfidencePoint(value: 58, note: nil),
                ConfidencePoint(value: 64, note: nil),
                ConfidencePoint(value: 68, note: nil),
            ],
            confidenceCaption: "Dip in week 4 followed the primary-source reading check; recovered once claim-evidence frames from her own labs were reused.",
            peerTies: [
                PeerTie(peerName: "Elena Brooks", initials: "EB", strength: 0.9),
                PeerTie(peerName: "Tariq Nassar", initials: "TN", strength: 0.75),
                PeerTie(peerName: "Priya Shah", initials: "PS", strength: 0.7),
                PeerTie(peerName: "Jamal Carter", initials: "JC", strength: 0.25),
                PeerTie(peerName: "Sofia Kim", initials: "SK", strength: 0.2),
                PeerTie(peerName: "Owen Diaz", initials: "OD", strength: 0.15),
            ],
            engagement: [
                EngagementWeek(week: 1, value: 52), EngagementWeek(week: 2, value: 58),
                EngagementWeek(week: 3, value: 65), EngagementWeek(week: 4, value: 40),
                EngagementWeek(week: 5, value: 48), EngagementWeek(week: 6, value: 70),
                EngagementWeek(week: 7, value: 78), EngagementWeek(week: 8, value: 60),
                EngagementWeek(week: 9, value: 74), EngagementWeek(week: 10, value: 82),
                EngagementWeek(week: 11, value: 88), EngagementWeek(week: 12, value: 80),
            ],
            engagementCaption: "Peaks align with station-rotation weeks — the choice-board unit and the cell-city analogy project.",
            evidenceNotes: [
                EvidenceNote(id: 1, lead: "Strongest work follows lab days.",
                             body: "Her top-scored pieces come within a day of a hands-on station rotation, not after independent reading."),
                EvidenceNote(id: 2, lead: "Inference on dense text remains the growth edge.",
                             body: "Exit tickets show strong decoding, but her written responses list details rather than connect them into a claim."),
                EvidenceNote(id: 3, lead: "Increasingly leads station work.",
                             body: "Notes from three separate rotations flag her taking the lead role without being asked."),
            ],
            lessonSuggestions: [
                LessonSuggestion(kind: .grouping, text: "Pair with Tariq N. — strong inference, complements her data strength."),
                LessonSuggestion(kind: .entryPoint, text: "Open with her own lab claim-evidence frame before introducing the new reading."),
                LessonSuggestion(kind: .stretch, text: "Have her write the station takeaway as a claim-evidence paragraph — targets her communication gap."),
            ]),

        "Jamal Carter": LearnerCompetencyProfile(
            studentName: "Jamal Carter",
            initials: "JC",
            gradeLabel: "9th grade · 15 artifacts · 11 competency claims confirmed",
            tags: ["Genetics", "Independent research", "Peer mentoring"],
            scores: [
                CompetencyScore(name: "Analysis", score: 91),
                CompetencyScore(name: "Collaboration", score: 58),
                CompetencyScore(name: "Public communication", score: 42),
            ],
            confidenceTrend: [
                ConfidencePoint(value: 70, note: nil),
                ConfidencePoint(value: 74, note: nil),
                ConfidencePoint(value: 78, note: nil),
                ConfidencePoint(value: 62, note: "Dip"),
                ConfidencePoint(value: 68, note: nil),
                ConfidencePoint(value: 76, note: nil),
                ConfidencePoint(value: 82, note: nil),
                ConfidencePoint(value: 84, note: nil),
            ],
            confidenceCaption: "Dip in week 4 followed the CRISPR ethics mini-debate — a strength on content, not on delivery.",
            peerTies: [
                PeerTie(peerName: "Elena Brooks", initials: "EB", strength: 0.8),
                PeerTie(peerName: "Owen Diaz", initials: "OD", strength: 0.85),
                PeerTie(peerName: "Priya Shah", initials: "PS", strength: 0.7),
                PeerTie(peerName: "Maya Rodriguez", initials: "MR", strength: 0.25),
                PeerTie(peerName: "Sofia Kim", initials: "SK", strength: 0.2),
                PeerTie(peerName: "Tariq Nassar", initials: "TN", strength: 0.15),
            ],
            engagement: [
                EngagementWeek(week: 1, value: 80), EngagementWeek(week: 2, value: 84),
                EngagementWeek(week: 3, value: 88), EngagementWeek(week: 4, value: 58),
                EngagementWeek(week: 5, value: 68), EngagementWeek(week: 6, value: 76),
                EngagementWeek(week: 7, value: 90), EngagementWeek(week: 8, value: 92),
                EngagementWeek(week: 9, value: 86), EngagementWeek(week: 10, value: 94),
                EngagementWeek(week: 11, value: 90), EngagementWeek(week: 12, value: 95),
            ],
            engagementCaption: "Consistently high, with a dip in week 4 during the mini-debate — his one presentation-heavy week.",
            evidenceNotes: [
                EvidenceNote(id: 1, lead: "Fast, independent starter on new content.",
                             body: "Moves into extension work within the same class period the core lesson is introduced."),
                EvidenceNote(id: 2, lead: "Communication lags the content mastery.",
                             body: "Explanations to the class run long on detail and short on a clear takeaway."),
                EvidenceNote(id: 3, lead: "Responds well to a teaching role.",
                             body: "Peer-mentoring the Punnett-square station produced his clearest explanation of the term all year."),
            ],
            lessonSuggestions: [
                LessonSuggestion(kind: .grouping, text: "Pair with Owen D. as a peer-mentor pairing — deepens his own understanding by teaching it."),
                LessonSuggestion(kind: .entryPoint, text: "Give him the extension prompt directly; skip the core-lesson recap."),
                LessonSuggestion(kind: .stretch, text: "Ask him to present the debate takeaway in under 60 seconds — targets his communication gap."),
            ]),

        "Sofia Kim": LearnerCompetencyProfile(
            studentName: "Sofia Kim",
            initials: "SK",
            gradeLabel: "9th grade · 8 artifacts · 6 competency claims confirmed",
            tags: ["Catch-up plan", "Lab work", "Flex block"],
            scores: [
                CompetencyScore(name: "Analysis", score: 55),
                CompetencyScore(name: "Collaboration", score: 70),
                CompetencyScore(name: "Public communication", score: 60),
            ],
            confidenceTrend: [
                ConfidencePoint(value: 60, note: nil),
                ConfidencePoint(value: 58, note: nil),
                ConfidencePoint(value: 38, note: "Dip"),
                ConfidencePoint(value: 40, note: nil),
                ConfidencePoint(value: 52, note: nil),
                ConfidencePoint(value: 60, note: nil),
                ConfidencePoint(value: 66, note: nil),
                ConfidencePoint(value: 71, note: nil),
            ],
            confidenceCaption: "Dip across weeks 3–4 tracks her 4-day absence; recovered once the catch-up plan started during Thursday flex block.",
            peerTies: [
                PeerTie(peerName: "Maya Rodriguez", initials: "MR", strength: 0.75),
                PeerTie(peerName: "Elena Brooks", initials: "EB", strength: 0.7),
                PeerTie(peerName: "Owen Diaz", initials: "OD", strength: 0.65),
                PeerTie(peerName: "Priya Shah", initials: "PS", strength: 0.2),
                PeerTie(peerName: "Tariq Nassar", initials: "TN", strength: 0.2),
                PeerTie(peerName: "Jamal Carter", initials: "JC", strength: 0.15),
            ],
            engagement: [
                EngagementWeek(week: 1, value: 55), EngagementWeek(week: 2, value: 60),
                EngagementWeek(week: 3, value: 20), EngagementWeek(week: 4, value: 25),
                EngagementWeek(week: 5, value: 48), EngagementWeek(week: 6, value: 58),
                EngagementWeek(week: 7, value: 64), EngagementWeek(week: 8, value: 70),
                EngagementWeek(week: 9, value: 66), EngagementWeek(week: 10, value: 72),
                EngagementWeek(week: 11, value: 75), EngagementWeek(week: 12, value: 78),
            ],
            engagementCaption: "The weeks-3-4 trough is her absence; steady climb since the catch-up plan started.",
            evidenceNotes: [
                EvidenceNote(id: 1, lead: "Catch-up work is landing.",
                             body: "Both priority labs came back on time and at the same quality as work from before the absence."),
                EvidenceNote(id: 2, lead: "Confidence dips are logistical, not conceptual.",
                             body: "Her lowest-scored week lines up exactly with the days she was out, not with new or harder content."),
                EvidenceNote(id: 3, lead: "Flex block is her most productive slot.",
                             body: "Three of her last four catch-up submissions were started during Thursday flex block."),
            ],
            lessonSuggestions: [
                LessonSuggestion(kind: .grouping, text: "Pair with Maya R. — willing partner, can walk her through missed station notes."),
                LessonSuggestion(kind: .entryPoint, text: "Start with the condensed guided-notes reading before the full lab, so she isn't missing shared vocabulary."),
                LessonSuggestion(kind: .stretch, text: "Once caught up, add the review-game content back in as a low-stakes retrieval check."),
            ]),
    ]

    // MARK: - Screen 3: Community opportunity graph

    static let communityGraph = CommunityGraphData(
        unitName: "Period 4 · Env. Science — Wetlands & Renewable Energy Unit",
        orgCountLabel: "22 organizations within 12 miles",
        capacityLabel: "13 with current capacity",
        nodes: [
            PartnerNode(name: "Regional Watershed Council", category: .civic, strength: 0.9),
            PartnerNode(name: "City Parks & Rec", category: .civic, strength: 0.6),
            PartnerNode(name: "Crestview Public Library", category: .culturalEd, strength: 0.5),
            PartnerNode(name: "State University Extension", category: .culturalEd, strength: 0.7),
            PartnerNode(name: "Meridian Renewable Energy Co.", category: .industry, strength: 0.8),
            PartnerNode(name: "GreenGrid Solar Cooperative", category: .industry, strength: 0.55),
            PartnerNode(name: "Local mentor network", category: .individuals, strength: 0.45),
        ],
        recommended: [
            PartnerOrg(name: "Regional Watershed Council", category: .civic, fitScore: 94,
                       blurb: "A public-comment slot at the May 12 wetlands trip gives students a real audience with real stakes.",
                       tags: ["Field trip", "Speaker", "Capacity 25"]),
            PartnerOrg(name: "Meridian Renewable Energy Co.", category: .industry, fitScore: 84,
                       blurb: "Sends an engineer to judge the renewable-energy debate and loans a small solar demo kit.",
                       tags: ["Guest speaker", "Equipment"]),
            PartnerOrg(name: "State University Extension", category: .culturalEd, fitScore: 71,
                       blurb: "Two summer data-collection internships, but onboarding needs a 4-week lead time.",
                       tags: ["Internship", "Mentor"]),
        ],
        stats: [
            CommunityStat(label: "Internships open", value: "5"),
            CommunityStat(label: "Guest speakers", value: "9"),
            CommunityStat(label: "Field sites", value: "3"),
            CommunityStat(label: "Mentors available", value: "7"),
        ])

    // MARK: - Screen 4: Project / mentor matcher

    static let matcherProfiles: [String: MatcherProfile] = [
        "Maya Rodriguez": MatcherProfile(
            studentName: "Maya Rodriguez",
            initials: "MR",
            matchingTags: [
                MatchTag(label: "Gap · written inference on dense text", kind: .gap),
                MatchTag(label: "Gap · connecting evidence to a claim", kind: .gap),
                MatchTag(label: "Strength · data analysis", kind: .strength),
                MatchTag(label: "Interest · wetlands project", kind: .interest),
            ],
            matches: [
                MatchCandidate(orgName: "Regional Watershed Council", contactName: "Renee Castillo",
                                fitScore: 92,
                                blurb: "Testify at the May 12 public-comment session using her own water-quality data.",
                                breakdown: [
                                    ScoreBreakdownItem(label: "Gap closure", weight: 0.5, rawScore: 93),
                                    ScoreBreakdownItem(label: "Interest", weight: 0.2, rawScore: 90),
                                    ScoreBreakdownItem(label: "Logistics", weight: 0.3, rawScore: 92),
                                ],
                                detail: MatchDetail(commitment: "2 hrs/week · 5 weeks",
                                                     format: "In-person · field site",
                                                     vetting: "District approved",
                                                     bonus: "Ties directly to the Period 4 field trip"),
                                draftIntroNote: "Hi Renee — I'm a 9th grader at Crestview High working with water-quality data from our own class testing. I'd like to help prepare for the May 12 public comment — could we talk this week?",
                                lowRankReason: nil),
                MatchCandidate(orgName: "Crestview Public Library", contactName: "Marcus Yi",
                                fitScore: 79,
                                blurb: "A four-session workshop on turning a dataset into a short public presentation.",
                                breakdown: nil, detail: nil, draftIntroNote: nil, lowRankReason: nil),
                MatchCandidate(orgName: "Crestview Science Olympiad", contactName: "Coach Dana Reyes",
                                fitScore: 58,
                                blurb: "Competitive data-analysis events, mostly individual work.",
                                breakdown: nil, detail: nil, draftIntroNote: nil,
                                lowRankReason: "Ranked lower because it rewards the data-analysis strength she already has and offers no writing or presenting practice."),
            ]),

        "Jamal Carter": MatcherProfile(
            studentName: "Jamal Carter",
            initials: "JC",
            matchingTags: [
                MatchTag(label: "Gap · explaining findings to a general audience", kind: .gap),
                MatchTag(label: "Gap · concise delivery", kind: .gap),
                MatchTag(label: "Strength · independent research", kind: .strength),
                MatchTag(label: "Interest · genetics / biotech", kind: .interest),
            ],
            matches: [
                MatchCandidate(orgName: "State University Extension", contactName: "Dr. Priya Raman",
                                fitScore: 90,
                                blurb: "Shadow a research assistant and present one finding to the lab each week.",
                                breakdown: [
                                    ScoreBreakdownItem(label: "Gap closure", weight: 0.5, rawScore: 88),
                                    ScoreBreakdownItem(label: "Interest", weight: 0.2, rawScore: 95),
                                    ScoreBreakdownItem(label: "Logistics", weight: 0.3, rawScore: 86),
                                ],
                                detail: MatchDetail(commitment: "3 hrs/week · 6 weeks",
                                                     format: "In-person · campus",
                                                     vetting: "District approved",
                                                     bonus: "Direct genetics tie-in"),
                                draftIntroNote: "Hi Dr. Raman — I'm a 9th grader who's ahead in our genetics unit and looking for a research placement. I'd like to get better at presenting findings to non-specialists — could we talk?",
                                lowRankReason: nil),
                MatchCandidate(orgName: "Local mentor network", contactName: "Alicia Wong (biotech mentor)",
                                fitScore: 76,
                                blurb: "Biweekly video check-ins with a biotech-industry mentor on career pathways.",
                                breakdown: nil, detail: nil, draftIntroNote: nil, lowRankReason: nil),
                MatchCandidate(orgName: "Punnett-square peer-tutoring club", contactName: "Student-run",
                                fitScore: 55,
                                blurb: "Weekly tutoring sessions for classmates on Mendelian genetics basics.",
                                breakdown: nil, detail: nil, draftIntroNote: nil,
                                lowRankReason: "Ranked lower because it builds a strength he already has (content mastery) rather than his communication gap."),
            ]),

        "Sofia Kim": MatcherProfile(
            studentName: "Sofia Kim",
            initials: "SK",
            matchingTags: [
                MatchTag(label: "Gap · consistent weekly commitment", kind: .gap),
                MatchTag(label: "Strength · lab technique", kind: .strength),
                MatchTag(label: "Interest · environmental science", kind: .interest),
            ],
            matches: [
                MatchCandidate(orgName: "City Parks & Rec", contactName: "Ben Ortiz",
                                fitScore: 88,
                                blurb: "Flexible weekend hours make this easy to fit around her catch-up schedule.",
                                breakdown: [
                                    ScoreBreakdownItem(label: "Gap closure", weight: 0.5, rawScore: 85),
                                    ScoreBreakdownItem(label: "Interest", weight: 0.2, rawScore: 88),
                                    ScoreBreakdownItem(label: "Logistics", weight: 0.3, rawScore: 94),
                                ],
                                detail: MatchDetail(commitment: "1.5 hrs/week · flexible days",
                                                     format: "In-person · 2 mi",
                                                     vetting: "District approved",
                                                     bonus: "No fixed weekly slot required"),
                                draftIntroNote: "Hi Ben — I'm a 9th grader looking for flexible hands-on science hours while I catch up on some missed classwork. Could we talk about the community-garden program?",
                                lowRankReason: nil),
                MatchCandidate(orgName: "Local mentor network", contactName: "Grace Palmer (virtual check-ins)",
                                fitScore: 70,
                                blurb: "Short weekly video check-ins on environmental-science career paths.",
                                breakdown: nil, detail: nil, draftIntroNote: nil, lowRankReason: nil),
                MatchCandidate(orgName: "Meridian Renewable Energy Co.", contactName: "Summer internship",
                                fitScore: 52,
                                blurb: "Fixed 3-day-a-week onsite summer internship.",
                                breakdown: nil, detail: nil, draftIntroNote: nil,
                                lowRankReason: "Ranked lower because its fixed 3-day-a-week onsite schedule conflicts with her current catch-up plan."),
            ]),
    ]
}
