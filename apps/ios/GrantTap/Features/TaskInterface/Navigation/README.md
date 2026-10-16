# Page navigation

`PageNavigation` owns the compact Mac page header. Chat, Mesh, Log, Settings,
and their detail pages use the same 40-point row and plain back chevron.
Page actions remain in the row. Phone and tablet retain native navigation and
the original toolbar placements. Modal editors keep their own confirmation
and cancellation controls.

Chat sheets (Files, Agent conversations and Task controls) share
`ChatSheetNavigation` and `ChatSheetDoneButton`. The header is a layout row,
inside the clickable content, rather than a safe-area overlay in the sheet.
Their presenting views supply the close action,
so a click clears the actual sheet binding even after nested navigation updates.
On Mac, Done uses a native Catalyst primary action with a 64 × 36 point hit
area. It dismisses the containing presented controller and then clears its
owner's binding, avoiding a stale SwiftUI dismissal environment. Escape also
closes the native sheet. Phone and tablet keep their native toolbar action.
`ChatModalDismissalUITests` verifies closing and reopening all three surfaces.

`MainWindowMeshNavigation` routes a Mac chat's Mesh action to the existing Mesh
section in the main window, using the resolved project and session identity.
Back returns to the Mesh list; selecting another sidebar section clears the
project route. If a snapshot has not arrived, the same route shows the shared
pending view and retains the project identity. It does not modify Tasks,
permissions, pairing or the native Mac window chrome.

Tests: `GrantTapTests/Features/TaskInterface/Navigation/MacPageNavigationTests.swift`.
