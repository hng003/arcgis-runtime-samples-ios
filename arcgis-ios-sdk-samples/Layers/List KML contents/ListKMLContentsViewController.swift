// Copyright 2018 Esri.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import ArcGIS

class ListKMLContentsViewController: UITableViewController {
    
    var kmlDataset: AGSKMLDataset?
    var parentNode: AGSKMLNode? {
        didSet{
            // set the navigation bar label to the node's name
            title = parentNode?.name
        }
    }
    var nodes: [AGSKMLNode] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard self.kmlDataset == nil else {
            return
        }
        
        // Add the source code button item to the right of navigation bar.
        (navigationItem.rightBarButtonItem as! SourceCodeBarButtonItem).filenames = ["ListKMLContentsViewController"]
        
        // create the dataset from the local kml/kmz file with the given name
        let kmlDataset = AGSKMLDataset(name: "esri_test_data")
        self.kmlDataset = kmlDataset
        
        // load the dataset asynchronously so we can list its contents
        kmlDataset.load {[weak self] (error) in
            
            guard let self = self else{
                return
            }
            
            guard error == nil else{
                // display the error as an alert
                let alertController = UIAlertController(title: error?.localizedDescription, message: nil, preferredStyle: .alert)
                alertController.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alertController, animated: true, completion: nil)
                return
            }
            
            /// Sets `isVisible` to `true` for these nodes and their descendants
            func makeNodesVisible(_ nodes: [AGSKMLNode]){
                for node in nodes{
                    node.isVisible = true
                    makeNodesVisible(self.childNodes(of: node))
                }
            }
            
            // some nodes are not visible by default so ensure that all of them are
            makeNodesVisible(kmlDataset.rootNodes)
            
            self.nodes = kmlDataset.rootNodes
            // populate the outline view now that the dataset is loaded
            self.tableView.reloadData()

        }
    }
    
    /// Returns all the child nodes of this node
    private func childNodes(of node: AGSKMLNode) -> [AGSKMLNode] {
        if let container = node as? AGSKMLContainer {
            return container.childNodes
        }
        else if let networkLink = node as? AGSKMLNetworkLink {
            return networkLink.childNodes
        }
        return []
    }
    
    //MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        if nodes.isEmpty {
            return 1
        }
        return 2
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 1 || nodes.isEmpty {
            return 1
        }
        return nodes.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 1 || nodes.isEmpty {
            // get and setup a cell to display the scene
            let cell = tableView.dequeueReusableCell(withIdentifier: "ListKMLContentsSceneCell") as! ListKMLContentsSceneCell
            cell.kmlDataset = kmlDataset
            cell.node = parentNode
            return cell
        }
        // get and setup a cell to display the node info
        let cell = tableView.dequeueReusableCell(withIdentifier: "NodeCell")!
        let node = nodes[indexPath.row]
        cell.textLabel?.text = node.name
        cell.detailTextLabel?.text = "\(type(of:node))"
        return cell
        
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 1 || nodes.isEmpty {
            return "Scene"
        }
        if parentNode != nil {
            return "Child Nodes"
        }
        return "Root Nodes"
    }
    
    //MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 0 else{
            return
        }
        let node = nodes[indexPath.row]
        // create and show a child table view controller for this node
        let tableViewController = storyboard?.instantiateViewController(withIdentifier: "ListKMLContentsViewController") as! ListKMLContentsViewController
        tableViewController.kmlDataset = kmlDataset
        tableViewController.parentNode = node
        tableViewController.nodes = childNodes(of: node)
        show(tableViewController, sender: self)
    }
    
    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 0 && !nodes.isEmpty
    }
    
}

class ListKMLContentsSceneCell: UITableViewCell {
    
    @IBOutlet weak var sceneView: AGSSceneView!
    
    weak var kmlDataset: AGSKMLDataset? {
        didSet{
            
            guard let kmlDataset = kmlDataset else {
                return
            }
            
            // initialize scene with labeled imagery
            let scene = AGSScene(basemapType: .imageryWithLabels)
            
            // create an elevation source and add it to the scene's surface
            let elevationSourceURL = URL(string: "https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer")!
            let elevationSource = AGSArcGISTiledElevationSource(url: elevationSourceURL)
            scene.baseSurface?.elevationSources.append(elevationSource)
            
            // assign the scene to the view
            sceneView.scene = scene
            
            // create a layer to display the dataset
            let kmlLayer = AGSKMLLayer(kmlDataset: kmlDataset)
            
            // add the kml layer to the map
            scene.operationalLayers.add(kmlLayer)
        }
    }
    
    weak var node: AGSKMLNode? {
        didSet{
            setSceneViewpoint()
        }
    }
    
    //MARK: - Viewpoint
    
    private func setSceneViewpoint(){
        if let node = node{
            if let nodeViewpoint = viewpoint(for: node),
                !nodeViewpoint.targetGeometry.isEmpty {
                // set the viewpoint for the node
                sceneView.setViewpoint(nodeViewpoint)
            }
            else {
                // this node has no viewpoint so hide the scene view, showing the info text
                sceneView.isHidden = true
            }
        }
        else {
            // this cell is in the root view controller of the sample, so just show the whole layer
            if let operationalLayers = sceneView.scene?.operationalLayers as? [Any],
                let kmlLayer = operationalLayers.last as? AGSKMLLayer,
                let extent = kmlLayer.fullExtent {
                // set the viewpoint based on the layer's geometry extent
                sceneView.setViewpoint(AGSViewpoint(targetExtent: extent))
            }
        }
    }
    
    /// Returns the elevation of the scene's surface corresponding to the point's x/y.
    private func sceneSurfaceElevation(for point: AGSPoint) -> Double? {
        guard let surface = sceneView.scene?.baseSurface else {
            return nil
        }
        
        var surfaceElevation: Double? = nil
        let group = DispatchGroup()
        group.enter()
        // we want to return the elevation synchronously, so run the task in the background and wait
        DispatchQueue.global(qos: .userInteractive).async {
            surface.elevation(for: point, completion: { (elevation, error) in
                if error == nil{
                    surfaceElevation = elevation
                }
                group.leave()
            })
        }
        // wait, but not longer than three seconds
        _ = group.wait(timeout: .now() + 3)
        return surfaceElevation
    }
    
    /// Returns the viewpoint showing the node, converting it from the node's AGSKMLViewPoint if possible.
    private func viewpoint(for node: AGSKMLNode) -> AGSViewpoint? {
        
        if let kmlViewpoint = node.viewpoint {
            // Convert the KML viewpoint to a viewpoint for the scene.
            // The KML viewpoint may not correspond to the node's geometry.
            
            switch kmlViewpoint.type{
            case .lookAt:
                var lookAtPoint = kmlViewpoint.location
                if kmlViewpoint.altitudeMode != .absolute{
                    // if the elevation is relative, account for the surface's elevation
                    let elevation = sceneSurfaceElevation(for: lookAtPoint) ?? 0
                    lookAtPoint = AGSPoint(x: lookAtPoint.x, y: lookAtPoint.y, z: lookAtPoint.z + elevation, spatialReference: lookAtPoint.spatialReference)
                }
                let camera = AGSCamera(lookAt: lookAtPoint,
                                       distance: kmlViewpoint.range,
                                       heading: kmlViewpoint.heading,
                                       pitch: kmlViewpoint.pitch,
                                       roll: kmlViewpoint.roll)
                // only the camera parameter is used by the scene
                return AGSViewpoint(center: kmlViewpoint.location, scale: 1, camera: camera)
            case .camera:
                // convert the KML viewpoint to a camera
                let camera = AGSCamera(location: kmlViewpoint.location,
                                       heading: kmlViewpoint.heading,
                                       pitch: kmlViewpoint.pitch,
                                       roll: kmlViewpoint.roll)
                // only the camera parameter is used by the scene
                return AGSViewpoint(center: kmlViewpoint.location, scale: 1, camera: camera)
            case .unknown:
                print("Unexpected AGSKMLViewpointType \(kmlViewpoint.type)")
                return nil
            }
        }
            // the node does not have a predefined viewpoint, so create a viewpoint based on its extent
        else if let extent = node.extent,
            // some nodes do not include a geometry, so check that the extent isn't empty
            !extent.isEmpty {
            
            var center = extent.center
            // take the scene's elevation into account
            let elevation = sceneSurfaceElevation(for: center) ?? 0
            
            // It's possible for `isEmpty` to be false but for width/height to still be zero.
            if extent.width == 0,
                extent.height == 0 {
                
                center = AGSPoint(x: center.x, y: center.y, z: center.z + elevation, spatialReference: extent.spatialReference)
                // Defaults based on Google Earth.
                let camera = AGSCamera(lookAt: center, distance: 1000, heading: 0, pitch: 45, roll: 0)
                // only the camera parameter is used by the scene
                return AGSViewpoint(targetExtent: extent, camera: camera)
                
            }
            else {
                // expand the extent to give some margins when framing the node
                let bufferRadius = [extent.width, extent.height].max()! / 20
                let bufferedExtent = AGSEnvelope(xMin: extent.xMin - bufferRadius,
                                                 yMin: extent.yMin - bufferRadius,
                                                 zMin: extent.zMin - bufferRadius + elevation,
                                                 xMax: extent.xMax + bufferRadius,
                                                 yMax: extent.yMax + bufferRadius,
                                                 zMax: extent.zMax + bufferRadius + elevation,
                                                 spatialReference: .wgs84())
                return AGSViewpoint(targetExtent: bufferedExtent)
            }
        }
        // the node doesn't have a predefined viewpoint or geometry
        return nil
    }

}