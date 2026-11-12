# Local transcription review for successive chapters

The disputed handwritten article on PDF file page 5 (printed page 2) was confirmed present by direct inspection and a higher-resolution render from the unchanged supplied PDF. The source line, images and private comparison records are intentionally not included in this public repository. This resolves the reported difference only; it does not certify a full literal transcription of Chapter 1 or Chapters 2–10.

## Implemented local tool

`app/tools/transcript-review.mjs` is a Node-only review/export tool. It is outside `app/public`, is not imported by the application or Worker, makes no network calls and never writes to the PDF. The assistant operates it; the parent does not need terminal commands. Tests contain invented text only.

Each private manifest binds the original PDF SHA-256 and actual page count to numbered page images. File page numbers are mandatory; the printed page label is separately recorded as a string or explicit null (unnumbered). It is never computed by an assumed offset.

Every page must have an image hash and a checked region inventory. Regions identify body, headings, handwriting, captions, illustration lettering and printed page numbers. A region with no visible text needs an explicit reviewed reason. Describe drawings separately; do not insert descriptions or grammatical fixes into transcription text. Preserve original words, spelling, punctuation and line breaks. Capture continuing sentences on both pages without silently adding joining words.

For each region, transcribe once against the image, then compare/transcribe again against the same reference image. Record both times, image checks and uncertainty. An omitted/added word, punctuation or line difference between passes blocks export. Uncertain text blocks export; do not settle it using grammar, expected plot or an AI guess. Reopen the original/high-resolution render, resolve the literal reading, and preserve the prior discrepancy in a private review log. Any edit requires renewed image comparison.

The tool verifies review-record consistency: PDF/page/image binding, complete page inventory, region structure, exact agreement, second-pass ordering and explicit uncertainty clearance. It cannot itself prove that a human found every sentence or that a supplied image was rendered from the correct page. The operator must render from the fixed source and inspect every region. Checked boxes and two identical OCR outputs are not independent evidence of accuracy.

Only if all pages pass does the CLI export exact reviewed text for AI preparation. Printed page-number/no-text regions are recorded but omitted from the AI text body. CLI logs only page numbers/error codes, not text. Unresolved manifests exit nonzero and produce no output. Existing output is never overwritten. Use a fresh output path and the current audit status; an older file is not evidence that a failed new run succeeded.

Export is rejected anywhere inside this repository (including public assets); symlink outputs/paths into the repository are rejected and output files use owner-only mode. Keep working directories outside the repository with owner-only permissions and do not serve or sync them to public websites. No secret, original PDF/image, transcript, private manifest or answer key belongs in a PR, CI artifact or public path. Ignore patterns reduce accidental staging but are not a substitute for checking the staged diff.

## Relation to learning and approval

Verified text is a separate AI input aid; the student continues to read the existing immutable PDF. Parent answer keys/evidence stay in private review files and existing server authorization. A transcript review does not approve questions, publish materials, assign students or release feedback. Those existing parent review/approval and operating-change gates remain intact.

This is a local preparation feature, not a deployed parent web editor or automatic visual-comparison service. It does not prevent someone from manually pasting unverified text into the existing editor; the reviewed-export workflow is the prescribed preparation path. No operating endpoint, schema, account or deployment is changed by this tool.

## Current validation scope

Synthetic tests cover exact agreement, added/omitted words, changed source/image, missing page/printed label/second pass, unresolved handwriting, inventory and output restrictions, no-text regions, excluded editorial descriptions, unchanged line breaks and review ordering. A private Chapter 1 manifest records the resolved handwriting check while leaving the remaining literal-review work pending; whole-chapter verified export is intentionally blocked. Previous normalized OCR aids are not relabeled as literal verified source.

For each of Chapters 2–10, create a new private source/hash/page inventory and repeat both image passes; do not copy Chapter 1 approval flags or infer printed numbering. Those chapters have not been inspected or verified in this work.
