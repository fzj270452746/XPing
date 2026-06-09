//
//  ContentView.swift
//  XPing
//
//  Created by Zhao on 2026/6/4.
//

import SwiftUI

/// 主界面，负责叠加 3D 游戏视图、分数面板和触控输入层。
struct ContentView: View {
    @StateObject private var gameController = PingPongGameController()
    @StateObject private var recordStore = GameRecordStore()
    @State private var hasEnteredGame = false
    @State private var showsGameHint = false
    @State private var showsExitConfirmation = false
    @State private var showsRecords = false
    @State private var hintGeneration = 0

    /// 构建适配全屏的 SwiftUI 游戏界面。
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PingPongSceneView(controller: gameController)
                    .ignoresSafeArea()

                if hasEnteredGame {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    gameController.updatePlayerPaddle(
                                        dragLocation: value.location,
                                        in: proxy.size
                                    )
                                }
                        )

                    gameOverlay
                } else {
                    startOverlay
                }
            }
        }
        .alert("Exit Match?", isPresented: $showsExitConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Exit", role: .destructive) {
                exitGame()
            }
        } message: {
            Text("Your current rally will stop and you will return to the start screen.")
        }
        .sheet(isPresented: $showsRecords) {
            GameRecordsView(recordStore: recordStore)
        }
    }

    /// 进入游戏并立即开始新回合。
    private func enterGame() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            hasEnteredGame = true
            showsGameHint = true
        }
        gameController.restartGame()
        scheduleHintHide()
    }

    /// 退出游戏并返回初始页面。
    private func exitGame() {
        saveCurrentRecordIfNeeded()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            hasEnteredGame = false
            showsGameHint = false
        }
        hintGeneration += 1
        gameController.exitGame()
    }

    /// 在当前比分有效时保存一条游戏记录。
    private func saveCurrentRecordIfNeeded() {
        recordStore.addRecord(
            playerScore: gameController.playerScore,
            aiScore: gameController.aiScore
        )
    }

    /// 安排游戏说明在几秒后自动隐藏。
    private func scheduleHintHide() {
        hintGeneration += 1
        let currentGeneration = hintGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            guard hasEnteredGame, currentGeneration == hintGeneration else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                showsGameHint = false
            }
        }
    }

    /// 游戏进行中的 HUD，展示比分、状态、说明和控制按钮。
    private var gameOverlay: some View {
        VStack(spacing: 14) {
            topGameBar
                .padding(.top, 14)

            if showsGameHint {
                instructionStrip
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer()

            Text(gameController.statusText)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.44), in: Capsule())

            controlBar
                .padding(.bottom, 26)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    /// 游戏顶部栏，展示比分和退出按钮。
    private var topGameBar: some View {
        HStack(spacing: 10) {
            compactScoreCard(title: "PLAYER", score: gameController.playerScore, tint: .cyan)
            compactScoreCard(title: "AI", score: gameController.aiScore, tint: .orange)

            Spacer(minLength: 4)

            Button {
                showsExitConfirmation = true
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .black))

                    Text("Exit")
                        .lineLimit(1)
                }
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.red.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: .red.opacity(0.24), radius: 12, x: 0, y: 8)
            }
            .buttonStyle(PressScaleButtonStyle())
        }
        .padding(.horizontal, 16)
    }

    /// 初始页面，展示游戏标题、分数记录和玩法说明。
    private var startOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.76), .black.opacity(0.36), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                VStack(spacing: 14) {
                    Text("LitePong 3D")
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Swipe, rally, and beat the AI.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))

                    scoreBoard
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 10) {
                        instructionRow(icon: "hand.draw.fill", text: "Drag anywhere to move your paddle.")
                        instructionRow(icon: "scope", text: "Hit different paddle areas for angled shots.")
                        instructionRow(icon: "trophy.fill", text: "Score when the ball passes the AI side.")
                    }
                    .padding(.top, 6)
                }
                .padding(22)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.38), radius: 28, x: 0, y: 18)
                .padding(.horizontal, 22)

                Button {
                    enterGame()
                } label: {
                    Label("Start Match", systemImage: "play.fill")
                        .font(.headline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.cyan, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: .cyan.opacity(0.34), radius: 18, x: 0, y: 10)
                }
                .padding(.horizontal, 40)

                Button {
                    showsRecords = true
                } label: {
                    Label("Records", systemImage: "list.bullet.rectangle.portrait.fill")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.white.opacity(0.14), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.22), lineWidth: 1)
                        )
                }
                .buttonStyle(PressScaleButtonStyle())
                .padding(.horizontal, 54)

                Spacer()
            }
        }
        .transition(.opacity)
    }

    /// 显示双方实时分数。
    private var scoreBoard: some View {
        HStack(spacing: 18) {
            scoreCard(title: "PLAYER", score: gameController.playerScore, tint: .cyan)
            scoreCard(title: "AI", score: gameController.aiScore, tint: .orange)
        }
        .padding(.horizontal, 16)
    }

    /// 展示游戏内简短玩法说明。
    private var instructionStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.point.up.left.fill")
                .foregroundStyle(.cyan)

            Text("Drag to move your paddle. Keep the rally alive and score past the AI.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    /// 显示开局、重新开局、清分等控制按钮。
    private var controlBar: some View {
        HStack(spacing: 10) {
            GameActionButton(title: "Serve", systemImage: "paperplane.fill", colors: [.cyan, .blue]) {
                gameController.startGame()
            }

            GameActionButton(title: "Restart", systemImage: "arrow.clockwise", colors: [.indigo, .purple]) {
                saveCurrentRecordIfNeeded()
                gameController.restartGame()
            }

            GameActionButton(title: "Reset Score", systemImage: "0.circle.fill", colors: [.orange, .red]) {
                saveCurrentRecordIfNeeded()
                gameController.resetScores()
            }
        }
        .padding(.horizontal, 18)
    }

    /// 构建单个分数卡片。
    private func scoreCard(title: String, score: Int, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)

            Text("\(score)")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.72), lineWidth: 1)
        )
    }

    /// 构建游戏顶部紧凑记分牌，避免与退出按钮重叠。
    private func compactScoreCard(title: String, score: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(tint)

                Text(title == "PLAYER" ? "You" : "Bot")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 4)

            Text("\(score)")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.horizontal, 12)
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.58), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
    }

    /// 构建带图标的说明条目。
    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.cyan)
                .frame(width: 24, height: 24)
                .background(.white.opacity(0.12), in: Circle())

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.86))
        }
    }
}

/// 游戏底部操作按钮，使用渐变背景和按压缩放反馈。
private struct GameActionButton: View {
    let title: String
    let systemImage: String
    let colors: [Color]
    let action: () -> Void

    /// 构建带图标、渐变和玻璃描边的控制按钮。
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .black))

                Text(title)
                    .font(.caption.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: colors.first?.opacity(0.26) ?? .clear, radius: 14, x: 0, y: 8)
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

/// 通用按压缩放按钮样式，用于提升点击反馈。
private struct PressScaleButtonStyle: ButtonStyle {
    /// 生成轻量按压缩放动画。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

