const russian = {
  'Other source lines': 'Остальные строки исходника',
  'Symbols unavailable': 'Секции не переданы',
  'External services': 'Внешние сервисы',
  'Clear search': 'Очистить поиск',
  'Files and sections': 'Файлы и секции', 'Close files': 'Закрыть файлы',
  'Find a file or symbol': 'Найти файл или символ', 'No matching files or symbols.': 'Нет подходящих файлов или символов.',
  'Highlight settings': 'Настройки подсветки', 'Close settings': 'Закрыть настройки',
  'Highlight sections above': 'Подсвечивать секции больше', 'Section size threshold': 'Порог размера секции',
  'Size uses measured source lines. A health score is not inferred.': 'Размер — измеренное число строк исходника. Оценка здоровья не вычисляется по размеру.',
  'Link and marker filters': 'Фильтры связей и маркеров', 'Graph camera controls': 'Управление камерой графа',
  'Fit': 'Всё', 'Top': 'Сверху', 'ISO': 'Изометрия', 'Orbit': 'Вращение', 'Pan': 'Сдвиг',
  'Files': 'Файлы', 'Highlights': 'Подсветка', 'Full screen': 'Полный экран', 'Help': 'Справка',
  'Graph controls': 'Управление графом', 'Close help': 'Закрыть справку',
  'Drag to orbit; choose Pan to move the scene.': 'Перетаскивайте для вращения; выберите «Сдвиг», чтобы переместить сцену.',
  'Pinch or use the zoom buttons to change scale.': 'Меняйте масштаб щипком, колесом или кнопками − и +.',
  'Click a tower or a labelled section to open its details.': 'Нажмите башню или подпись секции, чтобы открыть подробности.',
  'Scroll Sections to reach every reported symbol.': 'Прокручивайте список секций для доступа ко всем найденным символам.',
  'The tower label rail scrolls with your finger or mouse wheel.': 'Подписи секций возле башни прокручиваются пальцем или колесом мыши.',
  'Fit restores the whole map.': '«Всё» возвращает обзор всей карты.',
  'Tower details': 'Подробности башни', 'Close details': 'Закрыть подробности',
  'Sections': 'Секции', 'Links': 'Связи', 'Health': 'Состояние',
  'No source sections were reported for this tower.': 'Для этой башни нет отчёта о секциях исходника.',
  'Observed source': 'Данные исходника', 'File': 'Файл', 'Kind': 'Тип', 'Lines': 'Строки',
  'Section size': 'Размер секции', 'Source revision': 'Ревизия исходника', 'Analysis': 'Анализ',
  'Health details': 'Подробнее о состоянии', 'No links were observed in this report.': 'В этом отчёте не найдены связи.',
  'Health evidence': 'Данные о состоянии', 'Analysis fingerprint': 'Идентификатор анализа',
  'Reported file size': 'Размер файла в отчёте', 'Selected section': 'Выбранная секция',
  'Observed inbound links': 'Найденные входящие связи', 'Observed outbound links': 'Найденные исходящие связи',
  'Partial evidence: this map does not cover every input.': 'Данные частичные: карта охватывает не все входные данные.',
  'The reported analysis is complete.': 'Анализ по отчёту завершён.',
  'Coverage and complexity were not reported. Section-size highlights use measured LOC.': 'Покрытие тестами и сложность не переданы. Подсветка размера использует измеренное число строк.',
  'Size highlight threshold': 'Порог подсветки размера', 'Not reported': 'Нет данных',
  'Zoom in': 'Приблизить', 'Zoom out': 'Отдалить',
};

export function graphText(document, key) {
  return document.documentElement.lang.startsWith('ru') ? russian[key] ?? key : key;
}

export function graphButton(document, label, action, literal = false) {
  const node = document.createElement('button'); node.type = 'button';
  node.textContent = literal ? label : graphText(document, label); node.title = node.textContent;
  let touch = null, handledAt = -Infinity;
  node.addEventListener('pointerdown', event => {
    if (event.pointerType === 'touch') touch = { x: event.clientX, y: event.clientY, id: event.pointerId };
  });
  node.addEventListener('pointercancel', () => { touch = null; });
  node.addEventListener('pointerup', event => {
    const start = touch; touch = null;
    if (!start || start.id !== event.pointerId || Math.hypot(event.clientX - start.x, event.clientY - start.y) > 8) return;
    handledAt = document.defaultView.performance.now();
    event.preventDefault(); action(event);
  });
  node.addEventListener('click', event => {
    if ((event.pointerType === 'touch' || event.detail > 0)
      && document.defaultView.performance.now() - handledAt < 600) return;
    action(event);
  });
  return node;
}
