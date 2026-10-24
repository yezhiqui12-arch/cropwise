# Advisor read-only app data access

The controller supplies the current active field ID and an AdvisorDataTools
interface independently of question keywords. Gemini plans reads using a
structured JSON schema; the app executes only allowed read operations.

Tools: list_fields, get_field, list_assessments, get_assessment, get_assessment_samples. Assessment
history spans all non-deleted crop cycles belonging to a field. Individual
assessment reads enforce field ownership and retain dates, completion status,
sample coverage, and saved CV result denominators. Archived/deleted
fields are excluded. Expert status comes from the existing cloud review cache
and is explicitly distinguished from local validation status.

Explicitly named fields take priority over the active field. Ambiguous scope
requires a field clarification. Latest created and latest completed are distinct;
the planner can list assessments before reading completed results. Comparisons
use the same tools, rather than separate question-specific handlers.

There are at most four planning rounds with four reads each. Catalogs contain
up to 100 fields/cycles and 50 assessments; plant detail pages contain up to 20
samples. Truncation is reported and accumulated record context is
bounded to 48,000 characters. Planning adds up to four model requests per record-dependent chat
turn. No live-model evaluation was performed as part of implementation.

Saved field-sharing opt-outs disable planning and reads. New unset preferences
enable record sharing. Location is separately gated and is absent from tool
results. Generated chat history is treated as potentially containing field data.
The tools cannot write records, switch fields, or send messages. Observation
access includes station and plant CV outputs and image metadata, not raw photographs.
Expert review cache may be stale; live weather and arbitrary app data are not
available through these tools.

## Assessment comparisons

The overview includes actual block coverage, station record and sampled
station counts, and automatic damage screening counts with eligible denominators.
An empty eligible set has a null percentage rather than zero. Model damage
positives must not be inferred from legacy manual plant-status totals.

The planner reads both requested assessments and fetches sample details when
needed. Responses compare partial saved data provisionally, explain different
coverage and eligibility, and avoid inferring whole-field changes from unequal
samples. Incomplete status does not prevent describing already saved findings.
These changes do not restore blocking answer validation. Static analysis was
performed; the user's on-device records and live AI response were not inspected.
## Supporting block results removed

The Assessment Results Supporting block results section was removed at the
user's request. AdvisorContextRepository no longer queries stored MetricResults:
its snapshot metrics are empty, and neither its data tool nor the controller
context sends those metric rows. Sample details no longer calculate the removed
infested-whorl percentage. Saved observations and plant CV findings remain
available. Finding summaries retain directly counted model damage positives and
eligible samples. Instructions prohibit relying on removed metrics from earlier
chat answers.

## Model result retrieval and manual data removal (2026-10-01)

AdvisorModelResultsReader supplies the same CV data to assessment overviews,
station counts, and paginated plant details. It reads both the automatic-screening
plant note and the workflow preference cache (`plant_model_<station>_<position>`).
Cache results require matching ready canonical evidence checksums and consistent
pipeline/result identifiers. New saved notes include an evidence signature;
existing unsigned automatic notes remain readable. Cache-only capture positions
are included for ongoing assessments before a plant observation is saved.

The controller refreshes its active assessment context before each question.
Model reruns now persist onto legacy plant records as well as the cache, while
retaining historical fields. Those fields are excluded from Advisor data:
manual infestation, old damage, possible non-FAW, and uncertain observation
categories are neither counted nor provided as evaluated findings.

Damage screening uses Model 1's classification label, probabilities and confidence.
Available detector boxes are included separately; neither a damage classification
nor consecutive positive sample numbers proves confirmed infestation or physical
adjacency. Results belong to the plant, not each individual photo.

Missing, stale, invalid, and unavailable results are reported separately. With
no eligible classification, the percentage is null and responses must describe
saved outputs as unavailable, rather than report "not assessed (0/0)" or assume
the model never ran. Deleted or replaced evidence cannot support a matching cache.

Verification: 11 focused repository/explanation tests passed, covering cache and
plant-note reads, stale evidence, cache-only ongoing samples, rerun persistence,
and context refresh. Changed Dart files passed static analysis. No full suite or
live model request was used; the user's phone database was not inspected.

## Finalized expert damage freshness (2026-10-01)

The main Advisor and assessment-scoped assistant now read the same cached
`ExpertReviewService.assessmentReviewFacts` data. Finalized reports supply
reviewed/scored/insufficient counts, Davis severity, damage incidence, explicit
fresh/old-only/uncertain/unrecorded counts, station summaries and the eligible
denominator for the current infestation indicator. Freshness comes exclusively
from the expert's new judgment, not the unused historical manual flags.
Legacy reviews retain their scores and show freshness unrecorded. Unknown
freshness and insufficient evidence never become negative observations. Both
assistants identify the assessment date, disclose the cached review source and
keep these results distinct from binary Model 1 screening. Ambiguous station
identity withholds the derived percentage. Activation requires the dashboard
database migration `202610010004_expert_damage_freshness.sql` and an app rebuild.
