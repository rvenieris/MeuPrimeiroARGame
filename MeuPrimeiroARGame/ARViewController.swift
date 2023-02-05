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

    @IBOutlet var sceneView: ARSCNView!

        // Create a new empty scene
    let scene =  SCNScene() //SCNScene(named: "art.scnassets/GameElements.scn")!
    let updateQueue = DispatchQueue(label: "com.example.game.SceneKitQueue")

        // The Ovni where to create other boms coping this one
    lazy var masterOvni:SCNNode = {
        let node = SCNScene(named: "art.scnassets/GameElements.scn")!.rootNode.childNode(withName: "ovni", recursively:true)!
        node.physicsBody?.physicsShape = node.mergeAllChildrenPhysicsShape()
        return node
    }()

        // The bomb where to create other boms coping this one
    lazy var masterBomb:SCNNode = {
        let node = SCNScene(named: "art.scnassets/GameElements.scn")!.rootNode.childNode(withName: "bomb", recursively:true)!
        node.physicsBody = nil
        node.position = .init(0, 0, 0)
        node.opacity = 0.7


        let fire = node.childNode(withName: "fire", recursively:true)!
        fire.isHidden = true
        let radius:CGFloat = 0.3
        let torusGeometry = SCNPlane(width: radius, height: radius)
//        node.transform = SCNMatrix4MakeRotation(-Float.pi/2, 1, 0, 0)
        
        return node
    }()
    
    weak var currentBomb:SCNNode?
    let wickBurnTime:TimeInterval = 3
    let rechargeWaitingTime:TimeInterval = 6
    var lastIgniteTime:Date = Date.distantPast
    
    var badReadingsCounter = 0 {
        didSet {
            if badReadingsCounter > 10 {badReadingsCounter = 10; return}
            if badReadingsCounter < 0 {badReadingsCounter = 0; return}
        }
    }

}


//  MARK: - Initial Configuration
extension ARViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
            // Set the view's delegate
        sceneView.delegate = self
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
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(placeBomb(withGestureRecognizer:)))
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
        
        configuration.planeDetection = [.horizontal]
        
        configuration.isLightEstimationEnabled = true
        configuration.environmentTexturing = .automatic
        
            // Run the view's session
        sceneView.session.run(configuration)
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
        guard let camera = sceneView.session.currentFrame?.camera, case .normal = camera.trackingState,
              let query = sceneView.getRaycastQuery(),
              let result = sceneView.castRay(for: query).first,
                  camera.trackingState == .normal else {
            
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
    }
    
}


// Deal Ovni
extension ARViewController {
    func addOvni() {
        let node = masterOvni.clone()
        node.position = self.sceneView.pointOfView?.convertPosition(node.position, to: nil) ?? node.position


        scene.rootNode.addChildNode(node)
    }
    
}

    // Deal Bomb
extension ARViewController {
    func newBomb()->SCNNode { masterBomb.clone() }
    
    func ignite(bomb:SCNNode) {
        bomb.opacity = 1
        let wick = bomb.childNode(withName: "wick", recursively:true)!
        let fire = wick.childNode(withName: "fire", recursively:true)!
        fire.isHidden = false
        
        //burnWickAction
        let explosionTime:TimeInterval = 0.6
        let wickHeight = abs(wick.boundingBox.max.y - wick.boundingBox.min.y)*0.95
        
        let burnWickAction = SCNAction.move(by: .init(0, -wickHeight, 0), duration: wickBurnTime)
        let suspenseWait = SCNAction.wait(duration: 0.1)
        let extinguishFire = SCNAction.removeFromParentNode()

        let fadeToZero = SCNAction.fadeOpacity(to: 0, duration: explosionTime)
        let growExplosionBody = SCNAction.scale(to: 1.5, duration: explosionTime)
        let shockWave = SCNAction.group([growExplosionBody, fadeToZero])
        
        self.lastIgniteTime = Date()

        wick.runAction(burnWickAction) {
            wick.runAction(extinguishFire)
            bomb.addParticleSystem(self.explosion)
            bomb.runAction(suspenseWait) {
                bomb.runAction(shockWave) {
                    bomb.runAction(extinguishFire)
                }
            }
            
        }
        
        
        

//        bomb.addParticleSystem(explosion)
//        bomb.geometry?.materials.first?.diffuse.contents = nil
//        bomb.addParticleSystem(exp, withTransform: SCNMatrix4MakeRotation(0, 0, 0, 0))

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


extension ARViewController: ARSCNViewDelegate {
    
        // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async {
            self.updateFocus()
        }
        
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
//        updateQueue.async {
//            self.currentBomb?.simdPosition = anchor.transform.translation
//        }
    }
}

extension ARViewController: ARSessionDelegate {
    /*
     Allow the session to attempt to resume after an interruption.
     This process may not succeed, so the app must be prepared
     to reset the session if the relocalizing status continues
     for a long time -- see `escalateFeedback` in `StatusViewController`.
     */
        /// - Tag: Relocalization
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        return true
    }
}


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
