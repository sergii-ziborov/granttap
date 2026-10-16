# Product information

Public entry: `ProductInformationView`. Built-in About, Help, Terms, Privacy,
licenses and pricing live in the existing Settings flow. Mac's native About and
Help menus use `ProductInformationMenus` and request the same main-window pages;
they never open the system's unavailable Help panel or a separate app window.

The EN/RU documents in `Resources` are generated customer text from the
website’s `app/ProductInformation` and `app/ProductOffer` public entries. Run
`node --import tsx scripts/product-information/sync.ts --apple-root <apple-checkout>`
from the sibling website repository after updating the catalog or documents.
The same source renders the public website pages. They work without a relay, pairing, purchase or
internet connection. Keep website and bundled copies aligned when terms change.
Prices here describe the US launch plan; purchasing always displays StoreKit's
localized product price and availability. App Store apps use Apple's Standard
EULA until a custom EULA is actually configured in App Store Connect.

Tests exercise bundled content in both languages, document links, menu entries,
route delivery and rendering. The UI scenario opens Terms and Help inside the
About navigation flow. Actual Mac menu operation is verified in the normal app.

About → Third-party notices retains full original TweetNacl SwiftWrap and
Three.js license texts offline. Help includes current setup screenshots with
sample data and no pairing credentials; each illustration opens at full size.
