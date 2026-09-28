# Page navigation

`PageNavigation` owns the compact Mac page header. Chat, Mesh, Log, Settings,
and their detail pages use the same 40-point row and plain back chevron.
Page actions remain in the row. Phone and tablet retain native navigation and
the original toolbar placements. Modal editors keep their own confirmation
and cancellation controls.

`MainWindowMeshNavigation` routes a Mac chat's Mesh action to the existing Mesh
section in the main window, using the resolved project and session identity.
Back returns to the Mesh list; selecting another sidebar section clears the
project route. If a snapshot has not arrived, the same route shows the shared
pending view and retains the project identity. It does not modify Tasks,
permissions, pairing or the native Mac window chrome.

Tests: `GrantTapTests/Features/TaskInterface/Navigation/MacPageNavigationTests.swift`.
