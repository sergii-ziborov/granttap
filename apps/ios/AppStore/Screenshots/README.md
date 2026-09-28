# App Store screenshots

Upload the iPhone and iPad images in display order: `01-now`, `02-tasks`,
`03-task`, `04-usage`, `05-projects`. The English iPhone set additionally has
`06-linked-projects`, `07-architecture-graph`, and `08-code-towers`; these are
deterministic demo captures from the current UI, resized to the accepted
6.9-inch dimensions. The graph and code map visibly say `demo-revision` and
must not be described as a live customer scan. Upload `01-root`, `02-approval`,
`03-task` for Apple Watch.

The iPhone and iPad sets were captured from build 93 on 2026-09-08, from the
running app on the simulator rather than from rendered components: Now with
what needs a person first, the Tasks list, one Task as a chat with the
message block a turn is written in, Usage where every figure opens what it
counted, and Projects with the way in to a Project someone else shared. The
Apple Watch sets are from 2026-08-28; the watch screens have not changed
since.

| Folder | Locale | Pixels | Alpha | Status |
| --- | --- | ---: | --- | --- |
| `en-US/iPhone-6.9` | English (U.S.) | 1320 × 2868 | No | Ready |
| `ru/iPhone-6.9` | Russian | 1320 × 2868 | No | Ready |
| `en-US/iPad-13` | English (U.S.) | 2064 × 2752 | No | Ready |
| `ru/iPad-13` | Russian | 2064 × 2752 | No | Ready |
| `en-US/Apple-Watch-46mm` | English (U.S.) | 416 × 496 | No | Ready |
| `ru/Apple-Watch-46mm` | Russian | 416 × 496 | No | Ready |

All localized phone, tablet, and Watch sets have been captured and visually
reviewed. Landscape captures may use the inverse accepted dimensions.

The Russian sets are Russian all the way down. Before this capture the
interface still answered in English wherever a string had been handed
straight to SwiftUI instead of asked for by name — the approval buttons among
them — so those calls now go through the same lookup as everything else and
the words they need are in `Shared/ru.lproj/Localizable.strings`.

## Capturing them again

The screens come from the built-in Demo, driven by environment hooks that
exist only in a Debug build:

```
xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3
SIMCTL_CHILD_GRANTTAP_DEMO=1 SIMCTL_CHILD_GRANTTAP_TEST_LANGUAGE=ru \
  SIMCTL_CHILD_GRANTTAP_TAB=now xcrun simctl launch <udid> com.ziborov.granttap
xcrun simctl io <udid> screenshot 01-now.png
```

`GRANTTAP_TAB` takes `now`, `tasks`, `projects`, or `usage`;
`GRANTTAP_OPEN_SESSION=1` opens the first chat for `03-task`. Sizes come from
the device: iPhone 16 Pro Max gives 1320 × 2868, iPad Pro 13-inch gives
2064 × 2752. Save as JPEG without alpha.

Screenshots use deterministic, non-user sample content from the built-in Demo.
Demo is available in Release, is visibly labelled, performs no real action, and
does not expose a user's machine, source code, pairing material, or credentials.
