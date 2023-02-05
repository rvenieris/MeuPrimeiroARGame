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
    let scene =  SCNScene()
    
        // The Ovni where we can create other Ovnis coping this one
    lazy var masterOvni:SCNNode = {
        let node = SCNScene(named: "art.scnassets/GameElements.scn")!
                   .rootNode.childNode(withName: "ovni", recursively:true)!
        node.physicsBody?.physicsShape = node.mergeAllChildrenPhysicsShape()
        return node
    }()
}


    //  MARK: - Initial Configuration
extension ARViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(placeOvni(withGestureRecognizer:)))
        sceneView.addGestureRecognizer(tapGestureRecognizer)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        runARWorldTrackingConfiguration()
        
    }
    
    func runARWorldTrackingConfiguration() {
            // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        
//        configuration.frameSemantics.insert(.personSegmentationWithDepth)
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
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
            // Pause the view's session
        sceneView.session.pause()
    }
}



    //  MARK: - Deal with gestures & Moviments
extension ARViewController {
    
    @objc func placeOvni(withGestureRecognizer gestureRecognized: UIGestureRecognizer) {
        addOvni()
    }
    
}


    // MARK: - Deal OVNI
extension ARViewController {
    func addOvni() {
        let node = masterOvni.clone()
        node.position = self.sceneView.pointOfView?.convertPosition(node.position, to: nil) ?? node.position
        
        
        scene.rootNode.addChildNode(node)
    }
    
}


extension ARViewController: ARSessionDelegate {
    /*
     Allow the session to attempt to resume after an interruption. This process may not succeed, so the app must be prepared to reset the session if the relocalizing status continues for a long time -- see `escalateFeedback` in `StatusViewController`.
     */
        /// - Tag: Relocalization
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool { return true }
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
