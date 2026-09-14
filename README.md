# GrantTap for iPhone, iPad, and Apple Watch

This repository publishes the SwiftUI source for the GrantTap Apple app. GrantTap
shows local coding-agent work, approvals, and task activity on iPhone, iPad, and
Apple Watch. The app is a free download; its encrypted relay and background
delivery are offered through an in-app subscription. Source visibility does not
change those service terms.

The Apple app is **not MIT-licensed**. Its existing [license](LICENSE) applies to
this source and artwork. The companion [MCP runtime](https://github.com/sergii-ziborov/granttap-mcp),
[relay](https://github.com/sergii-ziborov/granttap-relay), and
[website](https://github.com/sergii-ziborov/granttap-site) have their own licenses.

## App screenshots

These iPhone screenshots use demo tasks and computers; they do not show a live
account or promise that a tool-reported success has changed a file.

| Now: requests and active work | Task: conversation and approvals | Task: execution and runtime observations |
|:--:|:--:|:--:|
| <img src="docs/images/iphone-command-center.png" width="240" alt="Now screen with an approval request, a question, and active tasks"> | <img src="docs/images/iphone-chat.png" width="240" alt="Task conversation with handoff activity and pending approvals"> | <img src="docs/images/iphone-task-route.png" width="240" alt="Task execution showing requested and reported tool activity, with an explicit working-tree warning"> |

| Project: repositories and Mesh | Project Governance | Join a Project by QR |
|:--:|:--:|:--:|
| <img src="docs/images/iphone-project-mesh.png" width="240" alt="Project overview with Mesh status, repositories, and tasks"> | <img src="docs/images/iphone-governance.png" width="240" alt="Project Governance settings for agents, tools, and other capabilities"> | <img src="docs/images/iphone-join-project.png" width="240" alt="Join a shared Project by scanning a QR code or using a secure fallback"> |

## Build

Open `apps/ios/GrantTap.xcodeproj` in Xcode and select the `GrantTap` scheme. For
an unsigned simulator build:

```sh
xcodebuild -project apps/ios/GrantTap.xcodeproj -scheme GrantTap \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Select your own development team to sign a personal device build. Push
notifications and distribution require the corresponding Apple capabilities and
provisioning. The watch app is embedded by the iOS scheme.

See [Apple app documentation](apps/ios/README.md),
[subscription behavior](docs/subscriptions.md), and [security](SECURITY.md).
