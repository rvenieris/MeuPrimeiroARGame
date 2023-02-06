    //
    //  ViewController.swift
    //  MeuPrimeiroARGame
    //
    //  Created by Ricardo Venieris on 29/01/23.
    //

import UIKit
import SceneKit
import ARKit

class ARViewController: UIViewController {
    
    static let bombCategoryBitMask = 1 >> 1
    static let ovniCategoryBitMask = 1 >> 2
    
    @IBOutlet var sceneView: ARSCNView!
    
        // Create a new empty scene
    let scene =  SCNScene()
    
        // a queue to run object updates
    let updateQueue = DispatchQueue(label: "com.example.game.SceneKitQueue")
    
        // The Ovni where we can create other Ovnis coping this one
    var masterOvni:SCNNode = {
        let node = SCNScene(named: "art.scnassets/GameElements.scn")!
            .rootNode.childNode(withName: "ovni", recursively:true)!.clone()
        node.physicsBody?.physicsShape = node.mergeAllChildrenPhysicsShape()
        node.physicsBody?.isAffectedByGravity = false
        node.position = .init(0, 0, 0)
        return node
    }()
    
        // The bomb where to create other boms coping this one
    var masterBomb:SCNNode = {
        let node = SCNScene(named: "art.scnassets/GameElements.scn")!
            .rootNode.childNode(withName: "bomb", recursively:true)!.clone()
        node.position = .init(0, 0, 0)
        node.physicsBody?.isAffectedByGravity = false
        node.opacity = 0.7

        let fire = node.childNode(withName: "fire", recursively:true)!
        fire.isHidden = true
        return node
    }()
    
    weak var currentBomb:SCNNode?
    let wickBurnTime:TimeInterval = 2.5 // Audio time
    let rechargeWaitingTime:TimeInterval = 4
    var lastIgniteTime:Date = Date.distantPast
    let bombDamageRange:Float = 5
    let maxOvnisPerTime = 6

    var badReadingsCounter = 0 {
        didSet {
            if badReadingsCounter > 10 {badReadingsCounter = 10; return}
            if badReadingsCounter < 0 {badReadingsCounter = 0; return}
        }
    }
    
    var initialAnchorNode: SCNNode = {
        let node = SCNScene(named: "art.scnassets/GameElements.scn")!
            .rootNode.childNode(withName: "initialAnchorNode", recursively:true)!.clone()
        node.geometry?.firstMaterial?.diffuse.contents = UIColor.clear
        node.position = .init(0, 0, 0)
        return node
    }()
    
    var invasionTimer:Timer = Timer()
    
    
        // Decode the audio from disk ahead of time to prevent a delay in playback
    static let wickAndFireAudioSource = {
        let audioSource = SCNAudioSource(fileNamed: "WickAndFire.mp3")!
        audioSource.loops = false
        audioSource.isPositional = true
        audioSource.shouldStream = true
        audioSource.load()
        return audioSource
    }()
    
    static let spaceshipEngineAudioSource = {
        let audioSource = SCNAudioSource(fileNamed: "SpaceshipEngine.mp3")!
        audioSource.loops = true
        audioSource.isPositional = true
        audioSource.shouldStream = true
        audioSource.load()
        return audioSource
    }()
    


    
}


    //  MARK: - Initial Configuration
extension ARViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
            // Set the delegates
        sceneView.delegate = self
//        scene.physicsWorld.contactDelegate = self
        
            // Set the scene to the view
        sceneView.scene = scene
        
//        setDebugOptionsOn()
        
        configureLighting()
        addTapGestureToSceneView()
    }
    
    func setDebugOptionsOn() {
            // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        sceneView.debugOptions = [.showPhysicsShapes, .showWorldOrigin]
    }
    
    func configureLighting() {
        sceneView.autoenablesDefaultLighting = true
        sceneView.automaticallyUpdatesLighting = true
    }
    
    func addTapGestureToSceneView() {
        let tapGestureRecognizer = UITapGestureRecognizer(target: self,
                                                          action: #selector(placeBomb(withGestureRecognizer:)))
        sceneView.addGestureRecognizer(tapGestureRecognizer)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        runARWorldTrackingConfiguration()
        addAREnvironmentProbeAnchor()
    }
    
    func runARWorldTrackingConfiguration() {
            // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.frameSemantics.insert(.personSegmentationWithDepth)
        configuration.isLightEstimationEnabled = true
        configuration.environmentTexturing = .automatic
        
        addAREnvironmentProbeAnchor()
            // Run the view's session
        sceneView.session.run(configuration)
        sceneView.session.delegate = self

    }
    
    func addAREnvironmentProbeAnchor() {
            // Create the new environment probe anchor with size 15, 15, 15 and add it to the session.
        let probeAnchor = AREnvironmentProbeAnchor(transform: simd_float4x4([[1.0, 0.0, 0.0, 0.0],
                                                                             [0.0, 1.0, 0.0, 0.0],
                                                                             [0.0, 0.0, 1.0, 0.0],
                                                                             [0.0, 1.0, 0.0, 1.0]]),
                                                   extent: simd_float3(15, 15, 15))
        sceneView.session.add(anchor: probeAnchor)
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
            // Prevent the screen from being dimmed to avoid interuppting the AR experience.
        UIApplication.shared.isIdleTimerDisabled = true
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
            // Pause the view's session
        sceneView.session.pause()
    }
}

    //  MARK: - Deal with gestures & Moviments
extension ARViewController {
    
    func updateFocus() {
            // Average using several most recent positions.
        guard -lastIgniteTime.timeIntervalSinceNow > rechargeWaitingTime else { return }
        
            // Perform ray casting only when ARKit tracking is in a good state.
        guard let camera = sceneView.session.currentFrame?.camera,
              let query = sceneView.getRaycastQuery(),
              let result = sceneView.castRay(for: query).first,
                case .normal = camera.trackingState else {
            
                // If lost camera Raycast, remove node
            guard let bomb = self.currentBomb else {return}
            badReadingsCounter += 1
            if badReadingsCounter >= 10 { bomb.removeFromParentNode() }
            
            return
        }
        
        
        badReadingsCounter -= 1
        guard badReadingsCounter <= 0 else {return}
        
        updateQueue.async {
            if let currentBomb = self.currentBomb {
                self.setPosition(of: currentBomb, for: result, camera: camera)
            } else {
                if self.initialAnchorNode.name != "placedInitialAnchorNode" {
                    self.initialAnchorNode.name = "placedInitialAnchorNode"
                    self.setPosition(of: self.initialAnchorNode, for: result, camera: camera)
                    self.sceneView.scene.rootNode.addChildNode(self.initialAnchorNode)
                    self.startInvasion()
                }
                self.currentBomb = self.newBomb()
                self.setPosition(of: self.currentBomb!, for: result, camera: camera)
                self.sceneView.scene.rootNode.addChildNode(self.currentBomb!)
                
            }
        }
        
    }
    
        // - : Set3DPosition
    private func setPosition(of node:SCNNode, for raycastResult: ARRaycastResult, camera: ARCamera?) {
        let position = raycastResult.worldTransform.translation
        node.runAction(SCNAction.move(to: SCNVector3(position.x, position.y, position.z), duration: 0.1))
    }
    
    
    @objc func placeBomb(withGestureRecognizer gestureRecognized: UIGestureRecognizer) {
        guard let currentBomb else {return}
        self.ignite(bomb: currentBomb)
        self.currentBomb = nil
        self.lastIgniteTime = Date()
    }
    
}

    // MARK: - Deal OVNI
extension ARViewController {
    
    func addOvni() {
            //1 - Creates an achorNode and place the OVNI above it
        let radius:Float = 6
        let ovni = masterOvni.clone()
        ovni.position = .init(0, radius, 0)
        let anchorNode = SCNNode()
        anchorNode.addChildNode(ovni)
        
                
            //2 - Set all needed positions
        
        let initialDestination = initialAnchorNode.position.randomPosition(in: radius)
        let finalDestination   = initialAnchorNode.position.randomPosition(in: radius/3)
        
            //3 - Place achorNode in final destination
        anchorNode.position = finalDestination
            //4 - put achorNode to rotate forever
        let rotateForever = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: 90, z: 0, duration: 180))
        anchorNode.runAction(rotateForever)
        
            //5 - Add the OVNI move action
        let moveToInitialPosition  = SCNAction.move(to: initialDestination, duration: 2)
        let moveToFinalDestination = SCNAction.move(to: finalDestination,       duration: 20)
        let moveSequence = SCNAction.sequence([moveToInitialPosition, moveToFinalDestination])
        let spaceshipEngineAudio = SCNAction.playAudio(Self.spaceshipEngineAudioSource, waitForCompletion: true)
        ovni.runAction(SCNAction.group([spaceshipEngineAudio, moveSequence]))
        
            //6 - add achorNode to scene
        initialAnchorNode.addChildNode(anchorNode)
//        ovni.addAudioPlayer(SCNAudioPlayer(source: Self.wickAndFireAudioSource))

    }
    
    func remove(ovni:SCNNode) {
        ovni.parent?.removeFromParentNode()
    }
    
    var allOvnis:[SCNNode] {self.initialAnchorNode.childNodes.compactMap({ $0.childNode(withName: "ovni", recursively:true) })}
    
    func removeAllOvni(in range:Float, of node:SCNNode) {
        allOvnis.forEach { ovni in
            let distance = ovni.distance(to: node)
            if distance <= range {
                print("Ovni Abatido", distance)
                ovni.removeFromParentNode()
            } else {
                print("Errou", distance)
            }
        }
    }
    
    func startInvasion() {
        DispatchQueue.main.async {
            self.invasionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: {_ in
                guard self.allOvnis.count < self.maxOvnisPerTime else {return}
                self.addOvni()
            })
        }
        
    }
}

    // MARK: - Deal Bomb
extension ARViewController {
    func newBomb()->SCNNode { masterBomb.clone() }
    
    func ignite(bomb:SCNNode) {
        bomb.opacity = 1

        let wick = bomb.childNode(withName: "wick", recursively:true)!
        let fire = wick.childNode(withName: "fire", recursively:true)!
        fire.isHidden = false

            //burnWickAction
        let explosionTime:TimeInterval = 2
        let finalScale: CGFloat = CGFloat(bombDamageRange)
        let wickHeight = abs(wick.boundingBox.max.y - wick.boundingBox.min.y)*0.95
        
        let wickAndFireAudio = SCNAction.playAudio(Self.wickAndFireAudioSource, waitForCompletion: true)
        let burnWickAction = SCNAction.move(by: .init(0, -wickHeight, 0), duration: wickBurnTime)
        let suspenseWait = SCNAction.wait(duration: 0.1)
        let extinguishFire = SCNAction.removeFromParentNode()
        
        let fadeToZero = SCNAction.fadeOpacity(to: 0.3, duration: explosionTime)
        let growExplosionBody = SCNAction.scale(to: finalScale, duration: explosionTime)
        let addParticleSystem = SCNAction.run({node in node.addParticleSystem(self.explosion)})
        let shockWave = SCNAction.group([addParticleSystem, growExplosionBody, fadeToZero])
        
        wick.runAction(SCNAction.sequence([burnWickAction, extinguishFire]))

        bomb.runAction(SCNAction.group([wickAndFireAudio,
                                        SCNAction.sequence([
                                            SCNAction.wait(duration: wickBurnTime),
                                            suspenseWait,
                                            shockWave ])
                                        ]),
                       completionHandler: {
            self.removeAllOvni(in: self.bombDamageRange, of: bomb)
            bomb.runAction(extinguishFire) })
        
    }
    
    var explosion:SCNParticleSystem {
        let exp = SCNParticleSystem()
        exp.loops = false
        exp.birthRate = 3000
        exp.emissionDuration = 0.5
        exp.spreadingAngle = 180
        exp.particleDiesOnCollision = true
        exp.particleLifeSpan = 1.5
        exp.particleLifeSpanVariation = 0.3
        exp.particleVelocity = 3
        exp.particleVelocityVariation = 3
        exp.particleSize = 0.05
        exp.stretchFactor = 0.1
        exp.particleColor =  #colorLiteral(red: 0.890388507, green: 0.3745780594, blue: 0, alpha: 0.7147192544)
        exp.particleColorVariation = .init(0.25, 0.25, 0.25, 0)
        return exp
    }
    
}


extension ARViewController: ARSessionDelegate {
    /*
     Allow the session to attempt to resume after an interruption. This process may not succeed, so the app must be prepared to reset the session if the relocalizing status continues for a long time -- see `escalateFeedback` in `StatusViewController`.
     */
        /// - Tag: Relocalization
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { return true }
}

extension ARViewController: ARSCNViewDelegate {
    
        // MARK: - ARSCNViewDelegate
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async { self.updateFocus() }
    }
}


    // MARK: - SCNPhysicsContactDelegate
//extension ARViewController: SCNPhysicsContactDelegate {
//
//    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
//        let pos = initialAnchorNode.position
//        let parent = initialAnchorNode.parent
//        initialAnchorNode.removeFromParentNode()
//        initialAnchorNode = masterOvni.clone()
//        parent?.addChildNode(initialAnchorNode)
//        guard let ovni = [contact.nodeA, contact.nodeB].filter({$0.name == "ovni"}).first else {return}
//    }
//
//}




/*
 ----------------------------------------------------------
 Helpers, Elements Extensions, etc
 ----------------------------------------------------------
 */

extension SCNNode {
    
    func mergeAllChildrenPhysicsShape()->SCNPhysicsShape? {
        let myShape = SCNPhysicsShape(geometry: self.geometry ?? SCNGeometry())
        let myTranslation = SCNMatrix4MakeTranslation(0, 0, 0) as NSValue
        
        var orderedShapes:[SCNPhysicsShape] = [myShape]
        var orderedTranslations:[NSValue] = [myTranslation]
        
        let childrenShapes = self.childNodes.compactMap{ $0.mergeAllChildrenPhysicsShape() }
        let childrenTranslation = self.childNodes.map {SCNMatrix4MakeTranslation($0.position) as NSValue}
        
        orderedShapes.append(contentsOf: childrenShapes)
        orderedTranslations.append(contentsOf: childrenTranslation)
        
        return SCNPhysicsShape(shapes: orderedShapes, transforms: orderedTranslations)
    }
    
    func distance(to other:SCNNode)->Float {
        let localPosition = self.convertPosition(other.position, to: nil)
        return localPosition.distance(to: other.position)
        
    }
}


func SCNMatrix4MakeTranslation(_ position: SCNVector3 ) -> SCNMatrix4 {
    SCNMatrix4MakeTranslation(position.x, position.y, position.z)
}


extension ARSCNView {
    /**
     Type conversion wrapper for original `unprojectPoint(_:)` method.
     Used in contexts where sticking to SIMD3<Float> type is helpful.
     */
    func unprojectPoint(_ point: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(unprojectPoint(SCNVector3(point)))
    }
    
        // - Tag: CastRayForFocusSquarePosition
    func castRay(for query: ARRaycastQuery) -> [ARRaycastResult] {
        return session.raycast(query)
    }
    
        // - Tag: GetRaycastQuery
    func getRaycastQuery(for alignment: ARRaycastQuery.TargetAlignment = .any) -> ARRaycastQuery? {
        return raycastQuery(from: screenCenter, allowing: .estimatedPlane, alignment: alignment)
    }
    
    var screenCenter: CGPoint {
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }
}


    // MARK: - float4x4 extensions
extension float4x4 {
    /**
     Treats matrix as a (right-hand column-major convention) transform matrix
     and factors out the translation component of the transform.
     */
    var translation: SIMD3<Float> {
        get {
            let translation = columns.3
            return [translation.x, translation.y, translation.z]
        }
        set(newValue) {
            columns.3 = [newValue.x, newValue.y, newValue.z, columns.3.w]
        }
    }
    
    /**
     Factors out the orientation component of the transform.
     */
    var orientation: simd_quatf {
        return simd_quaternion(self)
    }
    
    /**
     Creates a transform matrix with a uniform scale factor in all directions.
     */
    init(uniformScale scale: Float) {
        self = matrix_identity_float4x4
        columns.0.x = scale
        columns.1.y = scale
        columns.2.z = scale
    }
}


extension SCNVector3 {

    static func + (lhs: SCNVector3, rhs: SCNVector3)->SCNVector3 {
        return SCNVector3(x: lhs.x + rhs.x,
                          y: lhs.y + rhs.y,
                          z: lhs.z + rhs.z)
    }
    
    init(_ cgFloat: CGFloat) {
        let float = Float(cgFloat)
        self.init(float, float, float)
    }
    
    func distance(to vector: SCNVector3) -> Float {
        return simd_distance(simd_float3(self), simd_float3(vector))
    }
    
    func randomPosition(in radius:Float)->SCNVector3 {
        let x = Float.random(in: -radius...radius)
        let z = sqrt((radius*radius) - (x*x))
        return SCNVector3(x, 0.1, z)
    }
}

