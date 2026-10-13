import { createCyberboard } from './cb-core.js';
import { boardData } from './board-data.js';
import { createGraphInspector } from './graph-inspector.js';
import { createGraphControls } from './graph-controls.js';

let cyberboard;
let hostControls;
window.mountMeshGraph = () => {
  try {
    const data = boardData(window.meshReports);
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
      inspector = createGraphInspector(root, data, cyberboard);
      hostControls = createGraphControls(root, data, cyberboard, inspector);
    }
  } catch {
    window.graphFailure();
  }
};
if (window.meshReports) window.mountMeshGraph();
