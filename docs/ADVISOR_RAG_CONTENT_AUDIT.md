# Advisor RAG content and source audit

Audit updated: 2026-09-30. This is an engineering and citation review, not a Philippine crop-protection approval. No qualified reviewer has approved WormWise's actionable guidance. `reviewedOn` and `reviewDueOn` therefore remain unset, and all articles have `isPublishable == false` for actionable local advice.

## Answer boundaries

| Request | Allowed response | Boundary |
| --- | --- | --- |
| FAW education and scouting | Explain relevant attributed reference passages and WormWise procedures | State uncertainty and distinguish signs from confirmed identity |
| App help | Explain implemented screens and routes | Do not claim an action was performed |
| Saved assessment | Repeat recorded facts, denominators, stage, and status before interpretation | Do not infer a whole-field diagnosis or turn a model suggestion into a confirmed observation |
| Treatment, pesticide, or food/feed safety | Explain why the evidence is insufficient and where to check current local advice | No product, dose, mixture, spray interval, or unvalidated threshold as a recommendation |

These constraints live in `lib/services/advisor/advisor_faw_answer_policy.dart`. Guideline articles use reader-facing wording. Retrieval still uses those articles as factual context, while the separate policy governs what Gemini may conclude.

## Source checks

`verifiedOn` means the cited item was opened and its identity or relevant section checked. It does not mean every claim derived from that item was validated for Piat.

| Source ID | Check | Limitation |
| --- | --- | --- |
| CABI-HANDBOOK | Opened 2019 FAO/CABI handbook; identification and monitoring sections located | International general guidance |
| FAO-SCOUT | Opened Guidance Note 2; recurring scouting, field distribution, and old-damage exclusion found | International general guidance |
| FAO-SAFETY | Opened Guidance Note 1; pesticide risk reduction found | Does not verify Philippine product registration |
| DA-MO26-2021 | Opened DA order; LGU and regional monitoring, reporting, and technical roles found | Does not validate a field-specific diagnosis |
| ATI-10 | Opened ATI regional trifold; monitoring and reporting content found | Cebuano regional material, not a Piat treatment protocol |
| FPA | Opened authority website | Home page does not establish a specific registration or current label |
| CIMMYT-THRESHOLDS-2021 | Repository download blocked during this audit | Numeric thresholds remain unverified and non-actionable |
| CIMMYT-ASIA | Repository item identified, full text not inspected during this audit | Regional guidance requires Philippine adaptation |
| DA-BPI-FAW-LEAFLET | Existing six photographed pages described by project reference | Publication date, edition, and public URL remain unverified |
| ACCESS-SCOUT | [Producer page](https://www.accessagriculture.org/scouting-fall-armyworms) opened; scouting schedule found in English summary | International education; no Philippine treatment approval |
| FAO-IPM | [2018 FAO FFS guide](https://assets.accessagriculture.org/s3fs-public/FAO_FFS_guide_for_FAW_control.pdf) opened; natural-enemy discussion located at PDF pages 58 and 94–95 | Africa-focused guidance; operational practices require local adaptation |
| FAO-TRAPS | [FAO Kenya project report](https://www.fao.org/transboundary-plant-pests-diseases/news/detail/fao-and-kenyan-farmers-deploy-natural-allies-against-fall-armyworm-through-fao-china-south-south-cooperation-project/en) opened; pheromone monitoring and early-warning role found | Kenya project report is not Philippine product or biological-control authorization |
| PHILRICE-WEEDS | Official publication identified; full PDF exceeds browser extraction limit | Exact paper pages and individual claims remain pending |
| WORMWISE-PROTOCOL | Local draft protocol | Operational source, not external scientific validation |

## Article inventory and disposition

All 29 article IDs are retained as educational or operational references. The first column groups them for audit; none is designated approved Piat treatment guidance.

| Area | Article IDs | Disposition |
| --- | --- | --- |
| Identification | `identify-overview`, `identify-larva`, `identify-eggs`, `look-alikes`, `life-cycle`, `field-ecology` | Explain compatible signs and uncertainty; verify remaining lifecycle and ecology claims against exact pages |
| Symptoms and evidence | `evidence-frass`, `evidence-leaf`, `evidence-ear` | Keep signs separate from species confirmation and current infestation |
| Scouting | `scout-plant`, `scout-schedule`, `scout-field`, `scout-growth-stage`, `scout-traps`, `scout-boundary` | WormWise steps are operational rules; attributed external schedules are not universal Piat requirements |
| Management | `management-after-finding-faw`, `management-reference-thresholds`, `management-ipm`, `management-bpi-prevention`, `management-bpi-response`, `management-natural-enemies`, `management-weather-follow-up`, `management-decision-frame`, `management-threshold` | Descriptive reference only where applicability, source passage, or local validation is pending; numeric thresholds are non-actionable |
| Safety | `safety-pesticide`, `safety-ear-grain` | Safety cautions remain visible; no product registration or grain-safety determination is inferred |
| Expert help | `expert-escalation`, `expert-photo-evidence`, `expert-field-report` | Keep reporting and photo guidance educational; source links do not constitute expert case adjudication |

## Corrections and open checks

1. The Guidelines page previously called all articles “reviewed.” It now states that technical review is pending.
2. The prompt previously called the corpus “approved” and contradicted itself about displaying source IDs. The reference context is now labeled curated and unreviewed; source IDs remain internal.
3. App-directed wording in pesticide, weather follow-up, and threshold articles was changed to reader-facing wording. Equivalent AI constraints are explicit in the separate answer policy.
4. The life-cycle entry previously attributed both time ranges to CABI. The egg range now follows the FAO/CABI handbook and the larval range is explicitly attributed to the ATI regional brochure. Neither is local diagnosis or treatment timing.
5. The full source review remains incomplete for the sources marked unverified above. Until completed, the app must not advertise the collection as technically approved.

## AI use disposition and permitted use

Every article has a recorded engineering disposition in
`ADVISOR_GROUNDING_EVALUATION.md`. Unverified source dependencies,
validation-required articles, and overdue articles are excluded from AI
grounding. Guidelines browsing retains the complete library and its pending
review labels. Checked sources permit descriptive reference use in the app's
answer policy; this does not establish local efficacy, safety, or scientific
approval of every derived sentence.

The app keeps attributed editorial summaries and links, rather than republishing
source PDFs. Publisher permission for reproduction of complete PDFs, photos,
tables, translations, or commercial reuse has not been established. Such reuse
requires checking each publisher's actual license. Current eligibility is an
engineering evidence gate, not a license or agronomic sign-off.

Remaining gaps are explicit: both CIMMYT entries remain blocked/uninspected,
the PhilRice full paper has not been extracted, and the DA-BPI photographed
leaflet still lacks a verified publication date/edition/public URL. No review
date, expert name, or approval is invented to close these gaps.
