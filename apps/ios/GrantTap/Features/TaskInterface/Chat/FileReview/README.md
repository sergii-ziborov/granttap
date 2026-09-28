# File review

`ChatFileReviewSheet` opens a recorded edit from the completed-reply file list.
The full path and recorded added/removed counts stay above the diff. Mac uses
the shared compact page header; phone and tablet retain native sheet navigation.

`ChatFileDiffViewport` separates vertical history movement from horizontal code
scrolling. Short diffs start at the top left; long lines retain their complete
unwrapped width. A fresh file starts at the leading edge. The existing bounded
preview warning remains visible when the runtime truncated the diff.

The review displays recorded successful edits, not a fabricated final Git diff.
Tests live in `GrantTapTests/Features/TaskInterface/Chat/FileReview` and the
changed-file scenario in `GrantTapUITests/TranscriptHistoryUITests.swift`.
