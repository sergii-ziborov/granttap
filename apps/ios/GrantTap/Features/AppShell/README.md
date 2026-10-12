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

## Mac pointer feedback

`pointerButtonStyle` gives custom plain controls a full-area hover shade and
border. Sidebar selection stays separate from hover; native plain-button
press and keyboard behavior are retained by an appearance-only `ButtonStyle`.
`pointerFeedback` also covers filled
and outline actions and Task cards. Filled actions use their foreground color
for contrast on either theme. Disabled controls stay visually inactive; Reduce Motion removes the
transition. The decorative overlays never intercept taps or swipes. Phone
controls retain their native plain style.

`MacPageNavigationUITests` moves the real pointer and samples rendered row
backgrounds to check hover, pointer exit, selection and click navigation.
