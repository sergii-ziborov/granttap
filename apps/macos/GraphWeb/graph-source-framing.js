import { fitGraphCamera } from './graph-camera-framing.js';

/** Frame a selected tower in the space left by the phone or desktop inspector. */
export function frameGraphSource(board, root, panel, file) {
  const box = root.getBoundingClientRect();
  if (!box.width || !box.height) return false;
  const detail = panel.getBoundingClientRect();
  const free = { left: 20, top: 74, right: box.width - 20, bottom: box.height - 78 };
  if (detail.right - detail.left > box.width * 0.65) free.bottom = detail.top - box.top - 18;
  else free.left = detail.right - box.left + 20;
  const width = free.right - free.left, height = free.bottom - free.top;
  if (width < 64 || height < 64) return false;
  const camera = board.getCamera(), fov = camera.fov, aspect = camera.aspect;
  camera.fov = 360 / Math.PI * Math.atan(Math.tan(fov * Math.PI / 360) * height / box.height);
  camera.aspect = width / height;
  fitGraphCamera(board, { files: [file], MODULES: [
    { _cx: file.x, _cz: file.z, _half: file.isExternal ? 5 : 1.6 },
  ] }, 'iso', 2);
  camera.fov = fov; camera.aspect = aspect;
  camera.setViewOffset(box.width, box.height, box.width / 2 - (free.left + free.right) / 2,
    box.height / 2 - (free.top + free.bottom) / 2, box.width, box.height);
  board.getControls().update();
  return true;
}
