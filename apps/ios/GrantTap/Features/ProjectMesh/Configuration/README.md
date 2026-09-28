# Project configuration

Project restrictions and environment values are edited as fields of the
canonical Project policy and use its acknowledged delivery path. Saving sends
KEY=VALUE pairs to the computers bound to that Project at the time of the edit.
The variables become process environment for new agent launches after local
application. A computer added later does not inherit an old secret by merely
joining the Project; reapplication and an explicit endpoint receipt are needed.

The optional repository export writes non-secret values to a managed
`.granttap/env` file in each bound checkout. It does not commit or push that
file. Turning export off removes only the managed file; a foreign file or
symlink is preserved and reported as a failure. A secret Environment value
remains accessible to an agent process that receives it. This surface does
not implement use-only credentials, sharing secrets with member devices, or a
financial budget.
