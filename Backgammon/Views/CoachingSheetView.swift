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
                        bestMoveCard
                    } else {
                        ForEach(analysis.tips) { tip in
                            tipCard(tip)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Move Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    private var qualityHeader: some View {
        VStack(spacing: 6) {
            Text(analysis.quality.label)
                .font(.title2.bold())
                .foregroundColor(qualityColor)
            if analysis.quality != .optimal {
                Text(String(format: "Score difference: %.2f", analysis.scoreDiff))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(qualityColor.opacity(0.12))
        .cornerRadius(12)
    }

    private var bestMoveCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)
            Text("You found the best move! Well played.")
                .font(.body)
        }
        .padding()
        .background(Color.green.opacity(0.08))
        .cornerRadius(12)
    }

    private func tipCard(_ tip: CoachingTip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: tip.category.sfSymbol)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Text(tip.headline)
                    .font(.headline)
            }
            Text(tip.explanation)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private var qualityColor: Color {
        switch analysis.quality.colorName {
        case "green":  return .green
        case "mint":   return .mint
        case "blue":   return .blue
        case "yellow": return .yellow
        case "orange": return .orange
        case "red":    return .red
        default:       return .gray
        }
    }
}
