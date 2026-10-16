# Mesh insights

Shared Mac, iPhone and iPad presentation of repository reports and refresh routes.
`ProjectInsightReports` chooses one current report per repository identity and
retains enrichment between lightweight catalog updates only while bindings stay
compatible. Forks sharing a name remain separate.
Fresh scoped Git observations may prove that a historical local path and a
canonical identity refer to the same checkout. Their reports then share one
current result; an obsolete alias failure cannot restart a successful build.
Missing or conflicting identity evidence keeps the reports separate.

`ProjectGraphRefreshPlan` sends admitted local projects through the local MCP and
other connected computers through their relay. Local completion, remote request,
partial failure and unavailable routes have distinct outcomes. The visible
Health, Graph and Statistics views refresh their selected project while open.

Regression tests live in `GrantTapTests/Features/ProjectMesh/Usage`.

Health and Graph share one analysis request state. Active Projects with missing
or changed repository reports request an automatic build, with bounded retry.
A fresh analysis response ends waiting, including an unavailable report; a plain
Mesh refresh or an old report cannot confirm a new analysis. Graph renders one
progress indicator and explicit rebuild can be retried after a failed request.

Explicit analysis responses carry a request receipt. Every controller waiting on
the same coalesced build receives its own receipt. Routine cached reports cannot
acknowledge an explicit rebuild; local Mac requests complete from their own RPC.

Only real `COMPLETE`/`INCOMPLETE` analysis qualifies as architecture evidence.
Legacy placeholders trigger an automatic build. Git source revision is separate
from the Weavatrix content fingerprint. Mixed successful and unavailable
repositories are reported as partial. Transport receipts and request waiting
have deadlines; a matching late analysis can replace a timed-out request.
