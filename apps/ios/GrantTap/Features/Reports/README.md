# Reports

[Engineering contract](../../../../../AGENTS.md).

`ReportExportSheet` is the shared iPhone/Mac entry point for Project, Task, and
chat reports. It uses `ChatSheetNavigation` for the same header and reliable Done
behavior as other chat sheets. The report title and period stay above the format
picker; the actual file fills the main area and Share remains visible below.

`ReportPreviewPreparation` renders off the UI thread and caches each format for
the current immutable report. `ReportDocumentPreview` displays the PDF with
native zoom and page scrolling, or the exact CSV text with two-axis scrolling.
The preview bytes and the file handed to the system share sheet are identical.
Temporary exports remain local and are subject to system temporary-file cleanup.
Preparation failures keep Share disabled and expose Retry. Closing the sheet
does not send a report anywhere.

`ReportBuilder` uses observed catalog/usage data; unknown measurements remain
unknown. `ReportPDF` and `ReportCSV` format the same report without measuring new
activity. Long PDF titles and metadata wrap within the page header.

Behavior tests live in `tests/ReportPreviewTests.swift`; builder/format regression
tests are in `GrantTapTests/Features/Reports`. Cross-client native UI coverage is
`GrantTapUITests/ReportPreviewUITests.swift`.
