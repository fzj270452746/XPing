import Combine
import SceneKit
import SwiftUI

/// SceneKit 碰撞类别，使用位掩码区分球、球拍、球桌和得分边界。
private enum PhysicsCategory {
    static let ball = 1 << 0
    static let paddle = 1 << 1
    static let table = 1 << 2
    static let wall = 1 << 3
    static let playerGoal = 1 << 4
    static let aiGoal = 1 << 5
}

/// 3D 场景常量，集中描述乒乓球桌、球拍、球和玩法边界尺寸。
private enum TableSpec {
    static let tableWidth: CGFloat = 3.05
    static let tableLength: CGFloat = 5.48
    static let tableHeight: CGFloat = 0.76
    static let tableThickness: CGFloat = 0.10
    static let netHeight: CGFloat = 0.32
    static let netThickness: CGFloat = 0.035
    static let paddleWidth: CGFloat = 0.78
    static let paddleHeight: CGFloat = 0.52
    static let paddleDepth: CGFloat = 0.12
    static let ballRadius: CGFloat = 0.08
    static let playLimitX: Float = 1.34
    static let playerInputXSensitivity: Float = 1.55
    static let playerMinZ: Float = 0.34
    static let playerMaxZ: Float = 3.46
    static let aiMinZ: Float = -3.10
    static let aiMaxZ: Float = -0.34
    static let paddleY: Float = 1.15
    static let ballServeY: Float = 1.55
}

/// SwiftUI 可嵌入的 SceneKit 视图，负责把原生 SCNView 接入 SwiftUI 生命周期。
struct PingPongSceneView: UIViewRepresentable {
    @ObservedObject var controller: PingPongGameController

    /// 创建并配置原生 SceneKit 视图。
    func makeUIView(context: Context) -> SCNView {
        controller.makeSceneView()
    }

    /// SwiftUI 状态更新时保持 SceneKit 由控制器内部驱动。
    func updateUIView(_ uiView: SCNView, context: Context) { }
}

/// 乒乓球游戏核心控制器，负责 3D 场景、物理模拟、玩家输入、AI 对手和计分。
final class PingPongGameController: NSObject, ObservableObject {
    @Published var playerScore = 0
    @Published var aiScore = 0
    @Published var statusText = "Tap Start to Play"
    @Published var isRunning = false

    private let scene = SCNScene()
    private let cameraNode = SCNNode()
    private let playerPaddle = SCNNode()
    private let aiPaddle = SCNNode()
    private let ballNode = SCNNode()
    private let targetPlayerPosition = SCNNode()
    private var lastUpdateTime: TimeInterval = 0
    private var isConfigured = false
    private var canScore = true
    private var aiReactionSpeed: Float = 4.2
    private var dampingTimer: TimeInterval = 0

    /// 创建完整 SceneKit 视图，只在首次加载时搭建场景。
    func makeSceneView() -> SCNView {
        if !isConfigured {
            configureScene()
            isConfigured = true
        }

        let sceneView = SCNView(frame: .zero)
        sceneView.scene = scene
        sceneView.backgroundColor = UIColor(red: 0.035, green: 0.050, blue: 0.070, alpha: 1.0)
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 60
        sceneView.rendersContinuously = true
        sceneView.delegate = self
        sceneView.pointOfView = cameraNode
        sceneView.allowsCameraControl = false
        sceneView.isPlaying = true
        return sceneView
    }

    /// 开始一回合发球，若已经开局则重新发当前球。
    func startGame() {
        isRunning = true
        statusText = "Game On"
        serveBall(towardPlayer: false)
    }

    /// 重新开始整场游戏，并清空双方比分。
    func restartGame() {
        playerScore = 0
        aiScore = 0
        isRunning = true
        statusText = "New Match"
        serveBall(towardPlayer: false)
    }

    /// 只清空分数，不改变当前球局状态。
    func resetScores() {
        playerScore = 0
        aiScore = 0
        statusText = isRunning ? "Score Reset" : "Ready"
    }

    /// 退出当前游戏回合，停止乒乓球运动并回到待开始状态。
    func exitGame() {
        isRunning = false
        statusText = "Tap Start to Play"
        canScore = false
        ballNode.physicsBody?.clearAllForces()
        ballNode.physicsBody?.velocity = SCNVector3Zero
        ballNode.physicsBody?.angularVelocity = SCNVector4Zero
        ballNode.position = SCNVector3(0, TableSpec.ballServeY, 0)
    }

    /// 根据手指在屏幕中的位置更新玩家球拍目标点，映射为己方半场的左右和前后移动。
    func updatePlayerPaddle(dragLocation: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        let normalizedX = Float((dragLocation.x / size.width) * 2.0 - 1.0)
        let normalizedZ = Float(dragLocation.y / size.height)
        let mappedX = clamp(
            normalizedX * TableSpec.playerInputXSensitivity * TableSpec.playLimitX,
            -TableSpec.playLimitX,
            TableSpec.playLimitX
        )
        let mappedZ = clamp(
            TableSpec.playerMinZ + normalizedZ * (TableSpec.playerMaxZ - TableSpec.playerMinZ),
            TableSpec.playerMinZ,
            TableSpec.playerMaxZ
        )

        targetPlayerPosition.position = SCNVector3(mappedX, TableSpec.paddleY, mappedZ)
    }

    /// 搭建球桌、球拍、球、灯光、相机、边界和物理世界。
    private func configureScene() {
        scene.physicsWorld.gravity = SCNVector3(0, -5.2, 0)
        scene.physicsWorld.speed = 1.0
        scene.physicsWorld.contactDelegate = self

        scene.rootNode.addChildNode(cameraNode)
        configureCamera()
        addLights()
        addFloor()
        addTable()
        addNet()
        addPaddles()
        addBall()
        addBoundaries()

        targetPlayerPosition.position = playerPaddle.position
        serveBall(towardPlayer: false, launchImmediately: false)
    }

    /// 设置固定跟随球桌视角的相机，展示完整球桌和双方球拍。
    private func configureCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 55
        camera.zNear = 0.1
        camera.zFar = 60
        camera.wantsHDR = true
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 4.85, 7.15)
        cameraNode.eulerAngles = SCNVector3(-0.59, 0, 0)
    }

    /// 添加环境柔光和定向光源，提高画面层次并保持性能稳定。
    private func addLights() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 410
        ambient.color = UIColor(white: 0.78, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 920
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 5
        key.shadowSampleCount = 8
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.86, -0.45, -0.22)
        scene.rootNode.addChildNode(keyNode)
    }

    /// 添加低多边形地面和物理承托面。
    private func addFloor() {
        let floor = SCNFloor()
        floor.reflectivity = 0.0
        floor.firstMaterial?.diffuse.contents = UIColor(red: 0.07, green: 0.09, blue: 0.11, alpha: 1)
        floor.firstMaterial?.metalness.contents = 0.0
        floor.firstMaterial?.roughness.contents = 1.0

        let floorNode = SCNNode(geometry: floor)
        floorNode.physicsBody = SCNPhysicsBody.static()
        floorNode.physicsBody?.categoryBitMask = PhysicsCategory.wall
        floorNode.physicsBody?.collisionBitMask = PhysicsCategory.ball
        floorNode.physicsBody?.friction = 0.8
        floorNode.physicsBody?.restitution = 0.18
        scene.rootNode.addChildNode(floorNode)
    }

    /// 创建标准比例球桌、中心线和桌腿。
    private func addTable() {
        let tableGeometry = SCNBox(
            width: TableSpec.tableWidth,
            height: TableSpec.tableThickness,
            length: TableSpec.tableLength,
            chamferRadius: 0.025
        )
        tableGeometry.firstMaterial?.diffuse.contents = UIColor(red: 0.02, green: 0.22, blue: 0.18, alpha: 1)
        tableGeometry.firstMaterial?.roughness.contents = 0.62

        let tableNode = SCNNode(geometry: tableGeometry)
        tableNode.position = SCNVector3(0, TableSpec.tableHeight, 0)
        tableNode.physicsBody = SCNPhysicsBody.static()
        tableNode.physicsBody?.categoryBitMask = PhysicsCategory.table
        tableNode.physicsBody?.collisionBitMask = PhysicsCategory.ball
        tableNode.physicsBody?.contactTestBitMask = PhysicsCategory.ball
        tableNode.physicsBody?.friction = 0.42
        tableNode.physicsBody?.restitution = 0.86
        scene.rootNode.addChildNode(tableNode)

        addTableLine(width: 0.025, length: TableSpec.tableLength + 0.01, position: SCNVector3(0, 0.818, 0))
        addTableLine(width: TableSpec.tableWidth + 0.01, length: 0.025, position: SCNVector3(0, 0.819, 0))
        addTableLegs()
    }

    /// 添加球桌白色标线。
    private func addTableLine(width: CGFloat, length: CGFloat, position: SCNVector3) {
        let line = SCNBox(width: width, height: 0.008, length: length, chamferRadius: 0)
        line.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.92)
        let node = SCNNode(geometry: line)
        node.position = position
        scene.rootNode.addChildNode(node)
    }

    /// 添加简化桌腿，保持低面数模型。
    private func addTableLegs() {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.10, green: 0.12, blue: 0.13, alpha: 1)
        let xPositions: [Float] = [-1.28, 1.28]
        let zPositions: [Float] = [-2.25, 2.25]

        for x in xPositions {
            for z in zPositions {
                let leg = SCNCylinder(radius: 0.04, height: TableSpec.tableHeight)
                leg.radialSegmentCount = 8
                leg.firstMaterial = material
                let legNode = SCNNode(geometry: leg)
                legNode.position = SCNVector3(x, Float(TableSpec.tableHeight / 2), z)
                scene.rootNode.addChildNode(legNode)
            }
        }
    }

    /// 创建球网和半透明网面。
    private func addNet() {
        let net = SCNBox(
            width: TableSpec.tableWidth + 0.18,
            height: TableSpec.netHeight,
            length: TableSpec.netThickness,
            chamferRadius: 0.01
        )
        net.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.42)
        net.firstMaterial?.isDoubleSided = true

        let netNode = SCNNode(geometry: net)
        netNode.position = SCNVector3(0, Float(TableSpec.tableHeight + TableSpec.netHeight / 2), 0)
        netNode.physicsBody = SCNPhysicsBody.static()
        netNode.physicsBody?.categoryBitMask = PhysicsCategory.wall
        netNode.physicsBody?.collisionBitMask = PhysicsCategory.ball
        netNode.physicsBody?.friction = 0.12
        netNode.physicsBody?.restitution = 0.58
        scene.rootNode.addChildNode(netNode)
    }

    /// 创建玩家和 AI 球拍，并配置可碰撞的运动学物理体。
    private func addPaddles() {
        configurePaddle(playerPaddle, color: UIColor.systemCyan)
        playerPaddle.position = SCNVector3(0, TableSpec.paddleY, 2.45)
        playerPaddle.eulerAngles = SCNVector3(-0.12, 0, 0)
        scene.rootNode.addChildNode(playerPaddle)

        configurePaddle(aiPaddle, color: UIColor.systemOrange)
        aiPaddle.position = SCNVector3(0, TableSpec.paddleY, -2.45)
        aiPaddle.eulerAngles = SCNVector3(0.12, 0, 0)
        scene.rootNode.addChildNode(aiPaddle)
    }

    /// 配置单个球拍节点的几何体、材质和物理属性。
    private func configurePaddle(_ paddle: SCNNode, color: UIColor) {
        let geometry = SCNBox(
            width: TableSpec.paddleWidth,
            height: TableSpec.paddleHeight,
            length: TableSpec.paddleDepth,
            chamferRadius: 0.08
        )
        geometry.firstMaterial?.diffuse.contents = color
        geometry.firstMaterial?.roughness.contents = 0.36
        paddle.geometry = geometry
        paddle.physicsBody = SCNPhysicsBody.kinematic()
        paddle.physicsBody?.categoryBitMask = PhysicsCategory.paddle
        paddle.physicsBody?.collisionBitMask = PhysicsCategory.ball
        paddle.physicsBody?.contactTestBitMask = PhysicsCategory.ball
        paddle.physicsBody?.friction = 0.18
        paddle.physicsBody?.restitution = 1.05
    }

    /// 创建可交互乒乓球，并配置重力、弹性、摩擦和阻尼。
    private func addBall() {
        let ball = SCNSphere(radius: TableSpec.ballRadius)
        ball.segmentCount = 16
        ball.firstMaterial?.diffuse.contents = UIColor.white
        ball.firstMaterial?.roughness.contents = 0.32
        ballNode.geometry = ball
        ballNode.physicsBody = SCNPhysicsBody.dynamic()
        ballNode.physicsBody?.categoryBitMask = PhysicsCategory.ball
        ballNode.physicsBody?.collisionBitMask = PhysicsCategory.table | PhysicsCategory.paddle | PhysicsCategory.wall
        ballNode.physicsBody?.contactTestBitMask = PhysicsCategory.paddle | PhysicsCategory.playerGoal | PhysicsCategory.aiGoal
        ballNode.physicsBody?.mass = 0.026
        ballNode.physicsBody?.friction = 0.24
        ballNode.physicsBody?.rollingFriction = 0.16
        ballNode.physicsBody?.restitution = 0.92
        ballNode.physicsBody?.damping = 0.015
        ballNode.physicsBody?.angularDamping = 0.24
        ballNode.physicsBody?.continuousCollisionDetectionThreshold = TableSpec.ballRadius * 0.75
        scene.rootNode.addChildNode(ballNode)
    }

    /// 添加侧墙、后墙和隐形得分边界，防止球无限飞出可玩区域。
    private func addBoundaries() {
        addWall(name: "leftWall", position: SCNVector3(-1.82, 1.55, 0), size: SCNVector3(0.08, 2.7, 7.2), category: PhysicsCategory.wall)
        addWall(name: "rightWall", position: SCNVector3(1.82, 1.55, 0), size: SCNVector3(0.08, 2.7, 7.2), category: PhysicsCategory.wall)
        addWall(name: "backStopPlayer", position: SCNVector3(0, 1.55, 3.72), size: SCNVector3(3.8, 2.7, 0.08), category: PhysicsCategory.playerGoal)
        addWall(name: "backStopAI", position: SCNVector3(0, 1.55, -3.72), size: SCNVector3(3.8, 2.7, 0.08), category: PhysicsCategory.aiGoal)
        addWall(name: "ceiling", position: SCNVector3(0, 3.15, 0), size: SCNVector3(3.8, 0.08, 7.2), category: PhysicsCategory.wall)
    }

    /// 创建单个场景边界，得分墙保持透明但保留物理接触。
    private func addWall(name: String, position: SCNVector3, size: SCNVector3, category: Int) {
        let geometry = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: 0)
        geometry.firstMaterial?.diffuse.contents = category == PhysicsCategory.wall
            ? UIColor.white.withAlphaComponent(0.03)
            : UIColor.clear
        geometry.firstMaterial?.transparency = category == PhysicsCategory.wall ? 0.06 : 0.0

        let node = SCNNode(geometry: geometry)
        node.name = name
        node.position = position
        node.physicsBody = SCNPhysicsBody.static()
        node.physicsBody?.categoryBitMask = category
        node.physicsBody?.collisionBitMask = category == PhysicsCategory.wall ? PhysicsCategory.ball : 0
        node.physicsBody?.contactTestBitMask = PhysicsCategory.ball
        node.physicsBody?.friction = 0.12
        node.physicsBody?.restitution = 0.72
        scene.rootNode.addChildNode(node)
    }

    /// 发球到指定方向，可选择只重置位置而不立即施加速度。
    private func serveBall(towardPlayer: Bool, launchImmediately: Bool = true) {
        canScore = false
        ballNode.physicsBody?.clearAllForces()
        ballNode.physicsBody?.velocity = SCNVector3Zero
        ballNode.physicsBody?.angularVelocity = SCNVector4Zero
        ballNode.position = SCNVector3(0, TableSpec.ballServeY, 0)

        let zVelocity: Float = towardPlayer ? 3.35 : -3.35
        let xVelocity = Float.random(in: -0.55...0.55)
        if launchImmediately {
            ballNode.physicsBody?.velocity = SCNVector3(xVelocity, 1.0, zVelocity)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.canScore = true
        }
    }

    /// 平滑移动玩家球拍，让触控输入保持顺滑。
    private func updatePlayerPaddle(deltaTime: Float) {
        let current = playerPaddle.position
        let target = targetPlayerPosition.position
        let factor = min(deltaTime * 13.0, 1.0)
        playerPaddle.position = SCNVector3(
            current.x + (target.x - current.x) * factor,
            TableSpec.paddleY,
            current.z + (target.z - current.z) * factor
        )
    }

    /// 根据球的当前位置和速度移动 AI 球拍，形成难度适中的自动对手。
    private func updateAIPaddle(deltaTime: Float) {
        let ball = ballNode.presentation.position
        let velocity = ballNode.physicsBody?.velocity ?? SCNVector3Zero
        let isApproachingAI = velocity.z < 0
        let desiredX = isApproachingAI ? ball.x + velocity.x * 0.10 : ball.x * 0.28
        let desiredZ = isApproachingAI ? min(max(ball.z - 0.42, TableSpec.aiMinZ), TableSpec.aiMaxZ) : -2.45
        let factor = min(deltaTime * aiReactionSpeed, 1.0)

        let current = aiPaddle.position
        aiPaddle.position = SCNVector3(
            current.x + (clamp(desiredX, -TableSpec.playLimitX, TableSpec.playLimitX) - current.x) * factor,
            TableSpec.paddleY,
            current.z + (desiredZ - current.z) * factor
        )
    }

    /// 定期限制球速范围并补偿过低速度，避免回合停滞或物理异常。
    private func stabilizeBallIfNeeded(currentTime: TimeInterval) {
        guard isRunning, currentTime - dampingTimer > 0.25, let body = ballNode.physicsBody else { return }
        dampingTimer = currentTime

        var velocity = body.velocity
        let speed = max(length(velocity), 0.001)
        if speed > 7.2 {
            velocity = multiply(normalize(velocity), 7.2)
        } else if speed < 1.3 && ballNode.position.y > 0.9 {
            let zBoost: Float = ballNode.position.z >= 0 ? -2.0 : 2.0
            velocity = SCNVector3(velocity.x, max(velocity.y, 0.55), zBoost)
        }
        body.velocity = velocity
    }

    /// 根据碰撞位置对球拍反弹角度施加微调，模拟真实击球落点差异。
    private func applyPaddleBounce(from paddle: SCNNode) {
        guard let body = ballNode.physicsBody else { return }

        let localHitX = clamp(ballNode.presentation.position.x - paddle.presentation.position.x, -0.42, 0.42)
        let spin = localHitX / 0.42
        let directionZ: Float = paddle === playerPaddle ? -1 : 1
        let currentSpeed = max(length(body.velocity), 3.6)
        let zSpeed = min(max(abs(currentSpeed) * 0.92, 3.2), 5.8) * directionZ
        let ySpeed: Float = 1.35 + (1.0 - abs(spin)) * 0.42

        body.velocity = SCNVector3(spin * 2.25, ySpeed, zSpeed)
        body.angularVelocity = SCNVector4(0, spin * 7.0, 0, abs(spin) + 0.2)
    }

    /// 处理得分，更新比分并在短暂停顿后自动发下一球。
    private func scorePoint(playerScored: Bool) {
        guard canScore else { return }
        canScore = false

        if playerScored {
            playerScore += 1
            statusText = "Player Scores"
        } else {
            aiScore += 1
            statusText = "AI Scores"
        }

        ballNode.physicsBody?.velocity = SCNVector3Zero
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.statusText = "Next Serve"
            self.serveBall(towardPlayer: playerScored)
        }
    }

    /// 将数值限制在指定区间。
    private func clamp(_ value: Float, _ minValue: Float, _ maxValue: Float) -> Float {
        min(max(value, minValue), maxValue)
    }

    /// 计算三维向量长度。
    private func length(_ vector: SCNVector3) -> Float {
        sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    }

    /// 标准化三维向量。
    private func normalize(_ vector: SCNVector3) -> SCNVector3 {
        let vectorLength = length(vector)
        guard vectorLength > 0 else { return SCNVector3Zero }
        return SCNVector3(vector.x / vectorLength, vector.y / vectorLength, vector.z / vectorLength)
    }

    /// 按比例缩放三维向量。
    private func multiply(_ vector: SCNVector3, _ scalar: Float) -> SCNVector3 {
        SCNVector3(vector.x * scalar, vector.y * scalar, vector.z * scalar)
    }
}

/// SceneKit 帧更新回调，驱动球拍平滑移动、AI 和速度稳定。
extension PingPongGameController: SCNSceneRendererDelegate {
    /// 每帧更新玩家球拍、AI 球拍和乒乓球速度。
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = time
        }

        let deltaTime = Float(min(time - lastUpdateTime, 1.0 / 30.0))
        lastUpdateTime = time

        updatePlayerPaddle(deltaTime: deltaTime)
        updateAIPaddle(deltaTime: deltaTime)
        stabilizeBallIfNeeded(currentTime: time)
    }
}

/// SceneKit 物理碰撞回调，负责球拍击球和得分检测。
extension PingPongGameController: SCNPhysicsContactDelegate {
    /// 处理乒乓球与球拍、得分边界的首次接触。
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        let firstCategory = contact.nodeA.physicsBody?.categoryBitMask ?? 0
        let secondCategory = contact.nodeB.physicsBody?.categoryBitMask ?? 0
        let combined = firstCategory | secondCategory

        if combined & PhysicsCategory.ball != 0, combined & PhysicsCategory.paddle != 0 {
            if contact.nodeA === playerPaddle || contact.nodeB === playerPaddle {
                applyPaddleBounce(from: playerPaddle)
            } else if contact.nodeA === aiPaddle || contact.nodeB === aiPaddle {
                applyPaddleBounce(from: aiPaddle)
            }
            return
        }

        if combined & PhysicsCategory.ball != 0, combined & PhysicsCategory.playerGoal != 0 {
            DispatchQueue.main.async { [weak self] in
                self?.scorePoint(playerScored: false)
            }
        } else if combined & PhysicsCategory.ball != 0, combined & PhysicsCategory.aiGoal != 0 {
            DispatchQueue.main.async { [weak self] in
                self?.scorePoint(playerScored: true)
            }
        }
    }
}
