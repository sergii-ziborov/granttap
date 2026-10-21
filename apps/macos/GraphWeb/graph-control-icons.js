const paths = {
  'Zoom out': ['M4 10a6 6 0 1 0 12 0 6 6 0 0 0-12 0', 'm15 15 5 5', 'M7 10h6'],
  'Zoom in': ['M4 10a6 6 0 1 0 12 0 6 6 0 0 0-12 0', 'm15 15 5 5', 'M7 10h6m-3-3v6'],
  Fit: ['M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5'],
  Top: ['M5 12h14v8H5z', 'M12 3v6m-3-3 3 3 3-3'],
  ISO: ['m12 2 9 5v10l-9 5-9-5V7z', 'm3 7 9 5 9-5m-9 5v10'],
  Files: ['M8 5h13M8 12h13M8 19h13M3 5h.01M3 12h.01M3 19h.01'],
  Highlights: ['M4 6h16M4 12h16M4 18h16M8 3v6m8 0v6m-6 0v6'],
  'View settings': ['M4 6h16M4 12h16M4 18h16M8 3v6m8 0v6m-6 0v6'],
  Legend: ['M9 5h12M9 12h12M9 19h12', 'M3 3h3v4H3zM3 10h3v4H3zM3 17h3v4H3z'],
  Help: ['M9 8a3 3 0 1 1 5 2c-2 1-2 2-2 3m0 4h.01', 'M2 12a10 10 0 1 0 20 0 10 10 0 0 0-20 0'],
  'Full screen': ['M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5', 'm7 7-4-4m14 4 4-4M7 17l-4 4m14-4 4 4'],
  'Close details': ['m6 6 12 12M6 18 18 6'],
  'Close files': ['m6 6 12 12M6 18 18 6'],
};

/** Icon-only visual controls retain their full keyboard and VoiceOver names. */
export function graphControlIcon(button, key) {
  const document = button.ownerDocument, label = button.textContent;
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('aria-hidden', 'true');
  for (const d of paths[key]) {
    const path = document.createElementNS(svg.namespaceURI, 'path');
    path.setAttribute('d', d); svg.append(path);
  }
  const name = document.createElement('span'); name.className = 'graph-control-name'; name.textContent = label;
  button.setAttribute('aria-label', label); button.classList.add('graph-icon');
  button.replaceChildren(svg, name);
}
