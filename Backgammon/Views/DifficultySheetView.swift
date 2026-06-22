import SwiftUI

struct DifficultySheetView: View {
    @ObservedObject var gameState: GameState
    let onDismiss: () -> Void

    private let presets: [(String, Double, String)] = [
        ("Novice",       0.10, "Plays mostly at random — good for first-timers."),
        ("Beginner",     0.30, "Makes basic moves but misses tactics."),
        ("Intermediate", 0.55, "Solid positional play with occasional errors."),
        ("Advanced",     0.78, "Strong lookahead, rarely blunders."),
        ("Expert",       1.00, "Full 2-ply expectimax — plays near-optimally."),
    ]

    var body: some View {
        NavigationView {
            Form {
                // Input mode
                Section {
                    Picker("Input Mode", selection: $gameState.inputMode) {
                        ForEach(InputMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Control Scheme")
                } footer: {
                    Text(gameState.inputMode == .checkerFirst
                         ? "Tap a checker, then tap its destination."
                         : "Tap a die to select it, then tap any point — the app finds which checker to move.")
                }

                // Adaptive AI
                Section {
                    Toggle("Dynamic AI", isOn: Binding(
                        get: { gameState.isAdaptiveAI },
                        set: { if $0 { gameState.enableAdaptiveAI() } else { gameState.setFixedDifficulty(gameState.aiSkill) } }
                    ))
                } header: {
                    Text("AI Mode")
                } footer: {
                    Text("Dynamic AI adapts its skill to match yours so you're always challenged but never dominated.")
                }

                if gameState.isAdaptiveAI {
                    Section("Current State") {
                        LabeledContent("Your Rating") {
                            Text(gameState.playerRatingLabel)
                                .foregroundColor(.secondary)
                        }
                        LabeledContent("AI Skill") {
                            Text(gameState.aiSkillLabel)
                                .foregroundColor(.secondary)
                        }
                        LabeledContent("Turns Analyzed") {
                            Text("\(gameState.adaptiveTurnsCount)")
                                .foregroundColor(.secondary)
                        }
                        ProgressView("Player Rating", value: gameState.playerRatingValue)
                            .tint(.blue)
                        ProgressView("AI Skill", value: gameState.aiSkill)
                            .tint(.orange)
                    }
                } else {
                    Section("Fixed Difficulty") {
                        ForEach(presets, id: \.0) { name, skill, desc in
                            Button {
                                gameState.setFixedDifficulty(skill)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name).foregroundColor(.primary).font(.headline)
                                        Text(desc).foregroundColor(.secondary).font(.caption)
                                    }
                                    Spacer()
                                    if abs(gameState.aiSkill - skill) < 0.05 {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("How Dynamic AI Works") {
                    Text("Each move you make is evaluated against the optimal move. Your rating gradually adjusts — better play raises it, mistakes lower it. The AI targets your rating plus a small edge to keep the game competitive.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }
}
