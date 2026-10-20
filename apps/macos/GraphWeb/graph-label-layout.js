/** Keep source labels readable without changing their real world positions. */
export function layoutGraphLabels(root) {
  const bounds = root.getBoundingClientRect();
  const occupied = [...root.querySelectorAll('.granttap-inspector:not([hidden]),.graph-tools,.graph-camera')]
    .map(panel => panel.getBoundingClientRect()).filter(box => box.right > box.left && box.bottom > box.top);
  const labels = [...root.querySelectorAll('.lbl.filename'), ...root.querySelectorAll('.lbl.callout.active,.lbl.elev-more'),
    ...root.querySelectorAll('.lbl.callout:not(.active):not(.elev-more)'),
    ...root.querySelectorAll('.lbl.ring,.lbl.neighbor'), ...root.querySelectorAll('.lbl.module,.lbl.ext')];
  for (const label of labels) {
    const box = label.getBoundingClientRect();
    const outside = !box.width || !box.height || box.left < bounds.left + 8
      || box.right > bounds.right - 8 || box.top < bounds.top + 8 || box.bottom > bounds.bottom - 8;
    const overlaps = occupied.some(other => box.left < other.right + 8 && box.right > other.left - 8
      && box.top < other.bottom + 5 && box.bottom > other.top - 5);
    label.style.visibility = outside || overlaps ? 'hidden' : 'visible';
    if (!outside && !overlaps) occupied.push(box);
  }
}
