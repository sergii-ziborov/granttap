/** Frame received source bounds using the viewport's horizontal and vertical FOV. */
export function fitGraphCamera(board, data, view = 'reset') {
  const camera = board.getCamera(), controls = board.getControls();
  camera.clearViewOffset();
  const vector = (x, y, z) => camera.position.clone().set(x, y, z);
  const points = [];
  for (const module of data.MODULES || []) {
    for (const dx of [-1, 1]) for (const dz of [-1, 1]) {
      points.push(vector(module._cx + dx * module._half, 0, module._cz + dz * module._half));
    }
  }
  for (const file of [...data.files, ...(data.exts || [])]) {
    points.push(vector(file.x, 0, file.z), vector(file.x, file.height || 0, file.z));
  }
  const finite = points.filter(point => point.toArray().every(Number.isFinite));
  if (!finite.length || !Number.isFinite(camera.aspect) || camera.aspect <= 0) return false;
  const minimum = vector(Infinity, Infinity, Infinity), maximum = minimum.clone().negate();
  finite.forEach(point => { minimum.min(point); maximum.max(point); });
  minimum.addScalar(-8); maximum.addScalar(8);
  const center = minimum.clone().add(maximum).multiplyScalar(0.5);
  const direction = view === 'top' ? vector(0, 1, 0.001) : view === 'iso' ? vector(0.7, 0.8, 1)
    : camera.position.clone().sub(controls.target);
  if (direction.lengthSq() < 0.001) direction.set(0.7, 0.8, 1);
  direction.normalize();
  board.stopCameraFlight();
  camera.position.copy(center).add(direction); camera.lookAt(center); camera.updateMatrixWorld();
  const right = vector(1, 0, 0).applyQuaternion(camera.quaternion);
  const up = vector(0, 1, 0).applyQuaternion(camera.quaternion);
  const vertical = Math.tan(camera.fov * Math.PI / 360), horizontal = vertical * camera.aspect;
  let distance = 8;
  for (const x of [minimum.x, maximum.x]) for (const y of [minimum.y, maximum.y]) {
    for (const z of [minimum.z, maximum.z]) {
      const point = vector(x, y, z).sub(center), depth = point.dot(direction);
      distance = Math.max(distance, depth + 2 * camera.near,
        depth + Math.max(Math.abs(point.dot(right)) / horizontal, Math.abs(point.dot(up)) / vertical) * 1.15);
    }
  }
  camera.position.copy(center).addScaledVector(direction, distance);
  controls.target.copy(center);
  controls.maxDistance = Math.max(12_000, distance * 4);
  camera.far = Math.max(camera.far, distance + maximum.distanceTo(minimum) * 2);
  camera.updateProjectionMatrix(); updateGraphFog(board); controls.update();
  return true;
}

/** Preserve readable geometry when a narrow viewport needs a farther camera. */
export function updateGraphFog(board) {
  const fog = board.getScene?.().fog;
  if (!fog?.isFogExp2) return;
  const distance = board.getCamera().position.distanceTo(board.getControls().target);
  if (distance > 0) fog.density = Math.min(fog.density, 0.35 / distance);
}

export function hasVisibleGraphSource(board, data) {
  const camera = board.getCamera();
  camera.lookAt(board.getControls().target); camera.updateMatrixWorld();
  const sources = [...data.files, ...(data.exts || [])];
  if (!sources.length) return false;
  const points = sources.map(file => camera.position.clone().set(file.x, file.height / 2, file.z).project(camera));
  const visible = points.filter(point => point.toArray().every(value => Number.isFinite(value) && Math.abs(value) <= 1));
  if (visible.length < Math.ceil(sources.length / 2)) return false;
  const outline = (data.MODULES || []).flatMap(module => [-1, 1].flatMap(dx => [-1, 1].map(dz =>
    camera.position.clone().set(module._cx + dx * module._half, 0, module._cz + dz * module._half).project(camera))));
  const bounds = [...visible, ...outline];
  const span = key => Math.max(...bounds.map(point => point[key])) - Math.min(...bounds.map(point => point[key]));
  if (sources.length > 1 && Math.max(span('x'), span('y')) < 0.12) return false;
  return camera.position.y > 0;
}
