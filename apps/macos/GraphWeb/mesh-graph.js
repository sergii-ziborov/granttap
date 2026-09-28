import { createCyberboard } from './cb-core.js';
import { boardData } from './board-data.js';

let cyberboard;
window.mountMeshGraph = () => {
  try {
    const data = boardData(window.meshReports);
    cyberboard?.destroy();
    cyberboard = undefined;
    const message = document.getElementById('empty');
    message.textContent = 'No analyzed repository graph is available in this Mesh.';
    message.style.display = data.files.length ? 'none' : 'grid';
    if (data.files.length) cyberboard = createCyberboard(document.getElementById('graph'), { data });
  } catch {
    window.graphFailure();
  }
};
if (window.meshReports) window.mountMeshGraph();
