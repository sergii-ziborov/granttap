import { graphText } from './graph-language.js';
import { sectionChecks, graphPreferences, sectionKind, sectionKinds } from './graph-highlight-policy.js';

export function codeCheckDetails(content, context, section) {
  const { document, fact, state } = context;
  let checks = sectionChecks(section, state.preferences);
  if (!section) {
    const callables = (state.file.methods || []).filter(method =>
      !method.sourceRemainder && ['function', 'method'].includes(sectionKind(method)));
    const results = callables.map(method => sectionChecks(method, state.preferences));
    const measured = results.filter(value => value.status !== 'unknown').length;
    const warnings = results.filter(value => value.status === 'review').length;
    checks = { status: warnings ? 'review' : measured && measured === results.length ? 'clear' : 'unknown', reasons: [] };
    fact(content, 'Measured callable sections', `${measured} / ${callables.length}`);
    fact(content, 'Sections needing review', warnings);
  }
  const status = document.createElement('p');
  status.className = 'graph-check-status'; status.dataset.status = checks.status;
  status.textContent = graphText(document, checks.status === 'clear' ? 'Within selected code checks'
    : checks.status === 'review' ? 'Code checks need review' : 'Code checks not measured');
  content.append(status);
  if (section?.metrics?.measured) {
    const metrics = document.createElement('div'); metrics.className = 'graph-check-metrics';
    fact(metrics, 'Measured source lines', section.metrics.sourceLines);
    fact(metrics, 'Cyclomatic complexity estimate', section.metrics.cyclomatic);
    fact(metrics, 'Maximum loop nesting', section.metrics.maxLoopDepth);
    fact(metrics, 'Resolved callers', section.metrics.callers);
    content.append(metrics);
  }
  for (const reason of checks.reasons) {
    fact(content, { length: 'Section size', complexity: 'Cyclomatic complexity', nesting: 'Loop nesting' }[reason.rule],
      `${reason.value} > ${reason.limit}`);
  }
  for (const key of ['Static checks are source estimates, not proof of correctness.',
    'Test coverage and runtime performance were not measured.']) {
    const note = document.createElement('p'); note.textContent = graphText(document, key); content.append(note);
  }
}

export function decorateSectionRow(row, method, state) {
  const preferences = state.preferences ?? graphPreferences();
  const checks = sectionChecks(method, preferences);
  if (preferences.mode === 'kind') row.style.borderLeftColor = `#${sectionKinds[sectionKind(method)].color.toString(16)}`;
  row.classList.toggle('size-warning', preferences.mode === 'size' && method.loc > preferences.threshold);
  if (preferences.mode === 'health') {
    row.dataset.status = checks.status;
    row.style.borderLeftColor = { clear: '#64dca6', review: '#ff6878', unknown: '#69889a' }[checks.status];
  }
}
