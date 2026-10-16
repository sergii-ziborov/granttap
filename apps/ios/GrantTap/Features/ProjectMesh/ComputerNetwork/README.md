# Project computer network

Public entry: `AppModelProjectComputerNetwork`. `ProjectNetworkCoordinator`
creates and confirms controller-issued grants for the Project's own computers.
Manual Task transfer and automatic resource routing have separate policy flags.

Each ordered computer pair gets a distinct writer credential on the destination
relay room. Computers receive only their Project peer keys and scoped writer
credentials. Room owner credentials stay with the paired app. The complete plan
is saved in the device-only Keychain before any grant is published, so retries
reuse the same identity and credentials after interruption.

Configuration is confirmed by the exact paired room, Project, computer,
revision and request ID. A timeout or rejection prevents preparing that
destination. A previously confirmed, unchanged grant supports the computer's
persistent sender while the app is closed.

Tests live in `tests/` and exercise directional scope, isolated credentials,
confirmation boundaries and durable provisioning before HTTP publication.
