# Apple app shell

[Apple client index](../../../README.md) describes the application and build.
`GrantTapApp.swift` is the public application entry point;
`Compatibility.swift` owns shared navigation compatibility.

`CompatNavigationStack` uses native `NavigationStack` on iOS 16 and later,
including iPhone, iPad and Mac Catalyst. Pushed pages survive full-screen
inspectors and return to the same parent when dismissed. iOS 15 keeps the
explicit stack-style `NavigationView` fallback, avoiding an empty iPad detail
column. The large code-city UI scenario verifies search, file inspection and
return to Health in `GrantTapUITests/ProjectGraphUITests.swift`.
