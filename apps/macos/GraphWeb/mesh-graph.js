import { createCyberboard } from './cb-core.js';
import { boardData } from './board-data.js';
import { createGraphInspector } from './graph-inspector.js';
import { createGraphControls } from './graph-controls.js';
import { graphText } from './graph-language.js';

let cyberboard;
let hostControls;
window.mountMeshGraph = () => {
  try {
    const data = boardData(window.meshReports);
    for (const file of data.files) for (const segment of file.methods) {
      if (segment.sourceRemainder) segment.name = graphText(document, segment.name);
    }
    hostControls?.save();
    hostControls?.dispose();
    hostControls = undefined;
    cyberboard?.destroy();
    cyberboard = undefined;
    const message = document.getElementById('empty');
    message.textContent = 'No analyzed repository graph is available in this Mesh.';
    message.style.display = data.files.length ? 'none' : 'grid';
    if (data.files.length) {
      let inspector;
      cyberboard = createCyberboard(document.getElementById('graph'), { data,
        onFileSelect: selection => inspector?.openFile(selection),
        onFileBadgeOpen: selection => inspector?.openFile(selection),
        onMethodOpen: selection => inspector?.openMethod(selection),
        onMethodClose: () => inspector?.close(),
        onEdgeOpen: selection => inspector?.openEdge(selection),
      });
      const root = document.querySelector('.cb-root');
      for (const module of data.MODULES) {
        if (module.label?.element && module.displayName) {
          module.label.element.textContent = module.displayName.split('/').at(-1);
          module.label.element.title = module.displayName;
        }
      }
      for (const external of data.exts) {
        if (external.label?.element) external.label.element.textContent = external.name.split(' · ')[0];
      }
      inspector = createGraphInspector(root, data, cyberboard);
      hostControls = createGraphControls(root, data, cyberboard, inspector);
      window.graphViewSnapshot = () => {
        const camera = cyberboard.getCamera();
        camera.updateMatrixWorld();
        const segments = [];
        cyberboard.getScene().traverse(node => {
          if (Number.isInteger(node.userData?.methodIndex) && node.material?.color) segments.push({
            fileId: node.userData.fileId, index: node.userData.methodIndex,
            color: node.material.color.getHex(), opacity: node.material.opacity,
            emissiveIntensity: node.material.emissiveIntensity, visible: node.visible,
            sourceBody: node.userData.sourceBody === true,
          });
        });
        return { segments, position: camera.position.toArray(), target: cyberboard.getControls().target.toArray(),
          fogDensity: cyberboard.getScene().fog?.density || 0,
          aspect: camera.aspect, towers: [...data.files, ...data.exts].map(file => ({ id: file.id,
            projected: camera.position.clone().set(file.x, file.height / 2, file.z).project(camera).toArray(),
            distance: camera.position.distanceTo(camera.position.clone().set(file.x, file.height / 2, file.z)),
          })) };
      };
      // Geometry is ready; the desktop's decorative boot delay must not
      // cover received source evidence or delay the phone's controls.
      root.querySelector('#boot')?.remove();
    }
  } catch (error) {
    window.graphFailure(error);
  }
};
if (window.meshReports) window.mountMeshGraph();
