// DiceView.swift
// Renders a single die face with pips.

import SwiftUI

struct DiceView: View {
    let value: Int
    var used: Bool = false

    private let pipPositions: [Int: [(CGFloat, CGFloat)]] = [
        1: [(0.5, 0.5)],
        2: [(0.25, 0.25), (0.75, 0.75)],
        3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
        4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
        5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
        6: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.5), (0.75, 0.5), (0.25, 0.75), (0.75, 0.75)]
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(used ? Color.gray.opacity(0.35) : Color.white)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 1, y: 1)

            GeometryReader { geo in
                let size = geo.size
                ForEach(pipPositions[value] ?? [], id: \.0) { (x, y) in
                    Circle()
                        .fill(used ? Color.gray : Color.black)
                        .frame(width: size.width * 0.18, height: size.width * 0.18)
                        .position(x: size.width * x, y: size.height * y)
                }
            }
        }
        .frame(width: 40, height: 40)
        .opacity(used ? 0.4 : 1.0)
    }
}

struct DiceRowView: View {
    let dice: [Int]
    let usedDice: [Bool]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(dice.indices, id: \.self) { i in
                DiceView(value: dice[i], used: usedDice.indices.contains(i) ? usedDice[i] : false)
            }
        }
    }
}
