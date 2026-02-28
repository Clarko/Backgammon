// CoachingSheetView.swift
// Presents post-turn coaching feedback to the human player.
//
// Shown automatically after White completes a turn. The sheet explains:
//   • How close the played move was to the engine's best move
//   • Specific tips drawn from tactical and strategic backgammon concepts
//   • Nothing at all when the player chose the best available move

import SwiftUI

struct CoachingSheetView: View {

    let analysis: BackgammonEngine.MoveAnalysis
    let onDismiss: () -> Void

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    qualityHeader
                    if analysis.tips.isEmpty {
                        perfectPlayMessage
                    } else {
                        ForEach(analysis.tips) { tip in
                            tipCard(tip)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Quality Header

    private var qualityHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Coloured dot
            Circle()
                .fill(qualityColor)
                .frame(width: 14, height: 14)
                .shadow(color: qualityColor.opacity(0.4), radius: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(analysis.quality.label)
                    .font(.title3.bold())
                    .foregroundColor(qualityColor)

                if analysis.scoreDiff > 0.12 {
                    Text("Engine's best move scored \(String(format: "%.1f", analysis.scoreDiff)) point\(analysis.scoreDiff == 1 ? "" : "s") better")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(qualityColor.opacity(0.10))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(qualityColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Perfect Play Message

    private var perfectPlayMessage: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.largeTitle)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("You found the best move")
                    .font(.headline)
                Text("The engine would have played exactly the same position. There's nothing to improve on this roll.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Tip Card

    private func tipCard(_ tip: BackgammonEngine.CoachingTip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Category label row
            HStack(spacing: 6) {
                Image(systemName: tip.category.sfSymbol)
                    .font(.footnote.bold())
                    .foregroundColor(categoryColor(tip.category))

                Text(tip.category.rawValue.uppercased())
                    .font(.caption2.bold())
                    .tracking(1)
                    .foregroundColor(.secondary)
            }

            // Headline
            Text(tip.headline)
                .font(.headline)
                .foregroundColor(.primary)

            // Explanation — the teaching content
            Text(tip.explanation)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineSpacing(3)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Color Helpers

    private var qualityColor: Color {
        switch analysis.quality {
        case .optimal, .excellent: return .green
        case .good:                return Color(red: 0.0, green: 0.6, blue: 0.6)  // teal
        case .inaccuracy:          return .yellow
        case .mistake:             return .orange
        case .blunder:             return .red
        }
    }

    private func categoryColor(_ cat: BackgammonEngine.CoachingTip.Category) -> Color {
        switch cat {
        case .safety:    return .blue
        case .tactics:   return .red
        case .pointing:  return .yellow
        case .priming:   return .purple
        case .racing:    return .green
        case .anchoring: return .cyan
        }
    }
}
