# Corn growth stage guide and visual replies

Updated 2026-09-30, knowledge version faw-ph-2026.09-v9.

## Evidence and scope

Primary reference: Clemson Cooperative Extension, *Visual Guide to Corn Growth
Stages*, June 16, 2023, LGP 1170:
https://lgpress.clemson.edu/publication/visual-guide-to-corn-growth-stages/

The article was read directly. Its vegetative and reproductive sections support
the descriptive stage criteria. This is US field-corn morphology, not Philippine
treatment guidance. Source checking does not imply qualified local approval.
US calendar and moisture estimates are preserved in the complete original
reference, marked as source-specific rather than Philippine schedules. Current app groups do not cover V13–Vn;
the guide explicitly warns against forcing those stages into V7–V12.

Clemson's educational reprint permission applies to the entire publication.
The app now includes the complete source in a native offline reader: article
text, all 13 original figures, captions, numbered references, authors, citation
and the original disclaimer/reprint statement. Supplemental source figures in
Advisor and Guidelines link back to that complete educational reprint. This does
not assert an independent license for standalone commercial use or edited images.
The three original WormWise SVG schematics have been removed.

`docs/CLEMSON_GROWTH_IMAGE_PROVENANCE.json` records each figure's original creator
credit, source image URL, figure number, download date, byte count, dimensions and
SHA-256. All 13 files are bundled unchanged (about 1.43 MB total). Figure 9 uses
the full-resolution image linked by the original page. Original creator credits
are preserved as published, including the publisher's spelling of names.

## Integration

- Article `identify-corn-growth-stage` distinguishes identification from FAW
  inspection locations in `scout-growth-stage`.
- Six stage-specific retrieval articles cover VE, V1–Vn, VT, R1–R2, R3–R4 and
  R5–R6, with the original stage paragraphs and corresponding photographs.
  A seventh source section covers overall vegetative/reproductive development.
  Broad identification questions prioritize the compact complete overview,
  even with an active vegetative field stage. Specific stage and leaf-collar
  questions prioritize their focused source. The resolver preserves this scope.
- Knowledge chunks optionally carry visual assets, titles, captions, creator
  credits, image URLs and figure numbers. Retrieval
  exposes these descriptions and article IDs in bounded evidence context.
- The answer model selects `visual_article_ids` by the resolved conversational
  request. IDs must belong to retrieved articles with visuals. Unknown IDs are
  ignored; duplicate IDs are removed; at most two source articles are allowed.
  Supplied `[[guide:article-id:figure-number]]` markers place individual figures
  directly after their matching Markdown explanations. The model selects only
  retrieved figures; the renderer resolves paths and captions from the bundled
  catalog, and invalid or repeated figure markers are removed without blocking
  the answer. Broad lessons summarize VE, V1–Vn, VT and R1 through R6, with
  stage-specific reference images rather than a detached overview gallery.
  Short broad questions receive the regular substantial-answer budget so the
  reproductive stages are not cut off by the short-question token limit.
- Galleries work offline, support a figure selector, swiping, previous/next
  buttons and zoom, and can open the full Guidelines article and complete source.
  Credits stay visible; source URLs are selectable in expandable provenance.
  They do not depend on Show supporting
  sources. Normal replies may return an empty visual list.
- Conversation storage preserves selected article IDs. UI checks the current
  catalog before displaying restored visual references. Inline positions persist
  in the summary, while copy/reply previews omit the internal figure markers.
  Legacy saved replies retain their original gallery presentation.
- No new refusal or blocking answer validation was introduced. These source images
  do not give Gemini raw-photo vision or automated crop-stage detection.

## Verification

Focused Dart analysis and `tool/check_growth_stage_guide.dart` cover source
eligibility, four paraphrased retrieval queries, all six stage sections, all 13
credited offline assets and visual prompt context. All originals were decoded and
visually inspected in a contact sheet. No full test
suite or paid/live model calls were run. Additional offline checks cover broad
retrieval with an active V3 field, specific R3/V15 questions, figure marker
validation and clean copy text. One focused widget check covers reading order,
real bundled images, zoom and full-guide navigation. Live answer selection remains to be
confirmed in the rebuilt app.
