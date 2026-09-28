# Attachment preview

`AttachmentPreviewSheet` is the shared Mac/iPhone/iPad draft and sent-file inspector.
Source and text files use a selectable native text view; PDF, images, media and
other supported formats use system Quick Look. Unsupported binary formats remain
attachable and show filename and size without pretending to have a preview.
`AttachmentPreviewFile` owns a private temporary copy and removes it on release.
The original selected file remains untouched. The normal attachment byte/count
budgets apply to every format. Tests are in the corresponding TaskInterface
AttachmentPreview test folder and `GrantTapUITests/AttachmentPreviewUITests.swift`.

Draft thumbnails and sent attachments remain in one horizontal scrolling row.
More files do not add rows or increase the composer or message attachment height;
each file keeps its independent preview and each draft keeps its removal control.

Parent: [Task interface](../../README.md).
