// DifficultySheetView.swift
// Lets the player choose how strong the AI opponent is, or enable the
// adaptive mode that automatically calibrates to their demonstrated skill.

import SwiftUI

struct DifficultySheetView: View {

    @ObservedObject var gameState: GameState
    let onDismiss: () -> Void

    // The five fixed difficulty presets, mapped to [0, 1] skill values.
    private let presets: [(label: String, skill: Double, description: String)] = [
        ("Novice",       0.10, "Plays randomly, rarely recognises tactical opportunities."),
        ("Beginner",     0.30, "Makes obvious plays but often misses hits and key points."),
        ("Intermediate", 0.55, "Solid fundamentals; occasionally leaves avoidable blots."),
        ("Advanced",     0.78, "Strong play with good lookahead; rarely makes clear mistakes."),
        ("Expert",       1.00, "Full 2-ply expectimax — always finds the strongest move."),
    ]

    var body: some View {
        NavigationView {
            List {
                adaptiveSection
                fixedSection
                if gameState.isAdaptiveAI { adaptiveStatusSection }
                howItWorksSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("AI Difficulty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done", action: onDismiss).fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Adaptive Mode Section

    private var adaptiveSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dynamic AI")
                        .font(.body.bold())
                    Text("Automatically matches the AI strength to yours as you play.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { gameState.isAdaptiveAI },
                    set: { enabled in
                        if enabled { gameState.enableAdaptiveAI() }
                        else { gameState.setFixedDifficulty(gameState.aiSkill) }
                    }
                ))
                .labelsHidden()
            }
            .padding(.vertical, 4)
        } header: {
            Text("Adaptive Mode")
        }
    }

    // MARK: - Fixed Difficulty Section

    private var fixedSection: some View {
        Section {
            ForEach(presets, id: \.label) { preset in
                Button {
                    gameState.setFixedDifficulty(preset.skill)
                } label: {
                    HStack(spacing: 12) {
                        // Coloured difficulty dot
                        Circle()
                            .fill(difficultyColor(preset.skill))
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.label)
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(preset.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Checkmark when this preset is active.
                        if !gameState.isAdaptiveAI,
                           abs(gameState.aiSkill - preset.skill) < 0.05 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                                .font(.body.bold())
                        }
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Fixed Difficulty")
        } footer: {
            Text("Selecting a preset disables Dynamic AI.")
                .font(.caption)
        }
    }

    // MARK: - Adaptive Status Section

    private var adaptiveStatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                ratingRow(
                    label: "Your skill",
                    value: gameState.playerRatingValue,
                    name: gameState.playerRatingLabel
                )
                ratingRow(
                    label: "AI strength",
                    value: gameState.aiSkill,
                    name: gameState.aiSkillLabel
                )

                if gameState.adaptiveTurnsCount > 0 {
                    Text("Based on \(gameState.adaptiveTurnsCount) turn\(gameState.adaptiveTurnsCount == 1 ? "" : "s") analysed this session.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Current State")
        }
    }

    private func ratingRow(label: String, value: Double, name: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(name)
                    .font(.subheadline.bold())
                    .foregroundColor(difficultyColor(value))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill)).frame(height: 6)
                    Capsule()
                        .fill(difficultyColor(value))
                        .frame(width: geo.size.width * value, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - How It Works Section

    private var howItWorksSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                bulletPoint(
                    icon: "lightbulb.fill", color: .yellow,
                    text: "After each of your turns the coaching system scores your move quality — from Blunder to Best Move."
                )
                bulletPoint(
                    icon: "chart.line.uptrend.xyaxis", color: .blue,
                    text: "Those scores feed a smoothed skill rating that persists across sessions, so the AI already knows your level when you return."
                )
                bulletPoint(
                    icon: "target", color: .red,
                    text: "The AI targets a strength ~15% above your current rating — always challenging, never crushing."
                )
                bulletPoint(
                    icon: "arrow.left.arrow.right", color: .green,
                    text: "Adjustments are gradual, so a single bad roll won't suddenly make the AI easier, and a lucky win won't make it harder."
                )
            }
            .padding(.vertical, 4)
        } header: {
            Text("How Dynamic AI Works")
        }
    }

    private func bulletPoint(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 18)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Color Helper

    private func difficultyColor(_ skill: Double) -> Color {
        switch skill {
        case ..<0.20: return .gray
        case ..<0.40: return .green
        case ..<0.60: return .teal
        case ..<0.80: return .blue
        case ..<0.95: return .orange
        default:      return .red
        }
    }
}
