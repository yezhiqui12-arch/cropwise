# Advisor reply presentation

AdvisorReplyContent renders reply Markdown through flutter_markdown_plus 1.0.12.
It supports headings, emphasis, lists, numbered steps, quotes and GFM tables.
Table columns have bounded widths, wrap text and scroll horizontally rather
than overflowing the message. A swipe hint is shown for tables wider than the
available space. System text scaling is retained, replies are selectable and
reduced-motion preferences show completed replies immediately. Uploaded evidence
photos continue through the existing gallery; Markdown does not load images.

The AI answer instructions request a short takeaway, descriptive sections,
compact tables for summaries/comparisons and numbered practical steps. Short
answers stay simple. Source passages and navigation buttons remain separate.
Suggestions and action labels stay plain text. Existing plain prose is reflowed
into paragraphs without adding claims or reconstructing tables from its values.

New replies use one progressive typing clock across the title, summary, details
and final next step. Completion is reported by the reveal widget rather than
the former fixed 2.6-second timer. The reveal is proportional to length and
capped at nine seconds, uses grapheme boundaries and keeps partial figure
markers out of the text. Markdown tables reveal complete rows. New reference
images appear in reading order after their matching explanation; future images
and gallery/footer links are not mounted ahead of the text.

Suggested questions, source panels, copy/reply tools, full-guide links and app
action cards are mounted only after the entire reply is visible, then fade in
over 280 ms. Suggested questions and app action cards cannot be tapped while
typing or during their fade. Existing chat text is shown without replaying;
rebuilding a completed reply does not restart its typing clock. The active
reveal stays alive when scrolled off screen. Reduced motion bypasses both typing
and fades while retaining the same completion signal.

Three focused checks verify phone layout, horizontal table scrolling at large
text sizes, and preservation of legacy content. The app's live AI responses
have not been evaluated; the preview uses an example answer, not live records.
Three additional focused widget checks cover progressive text and completion,
delayed follow-up fade, reduced motion, rebuilding, and sequential guide images.

Renderer documentation: https://pub.dev/packages/flutter_markdown_plus
