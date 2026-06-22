# iOS Backgammon

A native iOS Backgammon game powered by a **GNU Backgammon (GNUbg)–inspired engine**, built entirely with Swift and SwiftUI.

## Features

- **Full backgammon rules** — bar entry, bearing off, hitting blots, doubles (4 moves)
- **GNUbg-style AI** — heuristic position evaluation covering pip count, blot danger, primes, anchors, and home-board coverage; selects the best move via 1-ply look-ahead
- **Interactive SwiftUI board** — tap a checker to select it, then tap a highlighted destination to move
- **Visual feedback** — selected checker highlighted in yellow; valid destinations highlighted in green
- **Pip counter** — live pip counts for both sides displayed in the control bar
- **Gammon / Backgammon detection** — engine detects and announces gammon and backgammon wins
- **New Game** — restart at any time after game-over

## Project Structure

```
Backgammon/
├── Backgammon.xcodeproj/          Xcode project (iOS 17+, Swift 5.9)
└── Backgammon/
    ├── BackgammonApp.swift         App entry point (@main)
    ├── ContentView.swift           Root SwiftUI view
    ├── Game/
    │   ├── BackgammonEngine.swift  GNUbg-inspired engine: move gen, evaluation, AI
    │   └── GameState.swift         Observable state: turn flow, human input, AI trigger
    ├── Views/
    │   ├── BoardView.swift         Full board layout, point columns, bar, bear-off
    │   └── DiceView.swift          Pip-accurate die face rendering
    └── Assets.xcassets/
```

## Engine Details

`BackgammonEngine.swift` follows GNUbg conventions:

| Feature | Implementation |
|---|---|
| Board representation | `points[24]` — positive = White, negative = Black; indices 0-23 map to points 1-24 |
| Move generation | Recursive exhaustive search; enforces max-dice-usage rule |
| Bear-off logic | Exact and over-bearing rules per Laws of Backgammon |
| AI evaluation | Pip differential · blot danger · prime length · home-board coverage · anchors · bar penalty |
| AI move selection | 1-ply best-first with full move enumeration |

## How to Play

1. **Open** `Backgammon.xcodeproj` in Xcode 15+
2. **Run** on an iPhone or iPad simulator (iOS 17+)
3. **You play White** — tap **Roll Dice** to roll, then tap a white checker to select it, and tap a highlighted point to move
4. **Black** (AI) moves automatically after your turn

## Requirements

- Xcode 15+
- iOS 17+ deployment target
- Swift 5.9
