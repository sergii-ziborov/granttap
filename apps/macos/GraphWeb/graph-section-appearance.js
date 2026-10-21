/** Keep vendor focus emphasis inside the readable range of the host palette. */
export function retainSectionAppearance(node, sourceBody, visible) {
  const material = node.material;
  node.visible = visible;
  if (visible) node.layers.enable(0);
  else node.layers.disable(0);
  node.userData.graphAppearance = { sourceBody, opacityLimit: Math.min(material.opacity, sourceBody ? 0.58 : 1) };
  if (!node.userData.graphAppearanceInstalled) {
    const beforeRender = node.onBeforeRender;
    node.onBeforeRender = function (...args) {
      beforeRender?.apply(this, args);
      normalizeSectionAppearance(this);
    };
    node.userData.graphAppearanceInstalled = true;
  }
  // Focus also changes opacity after selection callbacks. Keep blending enabled
  // so a later focus fade never renders as an opaque block.
  if (!material.transparent) material.needsUpdate = true;
  material.transparent = true;
  normalizeSectionAppearance(node);
}

function normalizeSectionAppearance(node) {
  const material = node.material, body = node.userData.graphAppearance.sourceBody;
  material.emissiveIntensity = Math.min(material.emissiveIntensity, body ? 0.12 : 0.35);
  material.opacity = Math.min(material.opacity, node.userData.graphAppearance.opacityLimit);
}

export const sourceBodyColor = 0x69889a;
