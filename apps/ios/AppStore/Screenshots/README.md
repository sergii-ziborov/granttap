# App Store screenshots

Display order for iPhone and iPad: `01-now`, `02-tasks`, `03-task`, `04-usage`,
`05-projects`. The fifth image opens the sample Project's Mesh details.
Apple Watch order: `01-root`, `02-approval`, `03-task`.

The English and Russian iPhone/iPad sets were recaptured on October 22, 2026
from **Release build 212** on iOS 26.5. XCTest enters through the public
Explore demo button rather than an automatic DEBUG demo flag. The same journey
checks a sample decision and Exit Demo. Native images are converted to RGB JPEG
without changing the UI content.

The Watch sets use the current build-212 native watchOS 26.5 interface with
deterministic sample state supplied by DEBUG capture hooks. They are not proof
of physical iPhone-to-Watch delivery. Do not describe these images as a Watch
Release demo entry or a live approval result.

| Folder | Locale | Pixels | Alpha |
| --- | --- | ---: | --- |
| `en-US/iPhone-6.9` | English (U.S.) | 1320 × 2868 | No |
| `ru/iPhone-6.9` | Russian | 1320 × 2868 | No |
| `en-US/iPad-13` | English (U.S.) | 2064 × 2752 | No |
| `ru/iPad-13` | Russian | 2064 × 2752 | No |
| `en-US/Apple-Watch-46mm` | English (U.S.) | 416 × 496 | No |
| `ru/Apple-Watch-46mm` | Russian | 416 × 496 | No |

These sets show non-user sample work. No private prompts, pairing material,
provider credentials or live computer authorization are included. Uploading
screenshots to a draft does not establish that Apple received a submission.

## Recapture

`AppReviewJourneyUITests` drives the public phone/tablet demo and attaches all
five screens in both languages. Use a Release test scheme containing only the
UI-test target; the regular unit-test target contains separate DEBUG fixtures.
The tests set both Apple language/locale and the app language. iPhone 17 Pro Max
produces 1320 × 2868; iPad Pro 13-inch produces 2064 × 2752.

Before capturing, set the simulator status bar to a consistent time and battery:

```bash
xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3
```

Watch capture hooks are DEBUG-only: `GRANTTAP_DEMO=1`,
`GRANTTAP_WATCH_CAPTURE=root|approval|task` and `GRANTTAP_TEST_LANGUAGE=en|ru`.
The phone/tablet's public demo is available in App Store builds, visibly labelled,
requires no account, purchase or computer, and never sends sample actions to a
computer. Do not apply simulator capture flags to a user's physical device.
