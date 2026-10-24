# WormWise current assessment protocol

This document describes the protocol implemented by the current application.
The executable sources remain authoritative when implementation details change:

- `lib/services/scouting_sampling_protocol.dart`
- `lib/services/scouting_route_generator.dart`
- `lib/providers/scouting_workflow_provider.dart`
- `lib/data/services/scouting_completion_service.dart`
- `lib/data/local/app_database.dart`

## Protocol identity

- Version: `wormwise-da-scattered-20-v1`
- Saved pattern: `da_scattered_20`
- Location-generation algorithm: `da_manual_scattered_points_walk_v2`
- Sample size: 20 plant locations per confirmed sampling block
- Plants per location: one
- Suggested edge margin: 3 metres from the confirmed block outline

## Field and block preparation

An assessment requires a selected maize field, crop cycle, evaluator, definite
growth-stage group, confirmed approximate field outline, sampling-block
definitions, and a completed treatment/re-entry safety check. An outline is a
scouting aid and is not a legal or survey-grade boundary.

Blocks are no larger than the current area policy permits. Every confirmed
block receives its own 20-plant sample. The application shows the saved block
area and the exact number of required plants.

## Plant-location generation

The application generates 20 dispersed suggestions inside each block. It:

- measures the edge margin against the saved polygon;
- avoids saved obstacles;
- uses separation heuristics to reduce clustering;
- refuses unusable geometry instead of reducing the required sample;
- preserves completed or manually adjusted points during recalculation; and
- does not claim that the numbered order is a globally shortest or physically
  traversable path.

Evaluators select a safe route between locations. An unreachable unsaved
suggestion may be adjusted inside the block with a reason while retaining the
geometry constraints.

## Plant assessment and evidence

At each numbered location, the evaluator selects a nearby actual plant and
records the applicable stage-specific observation. Phone location is recorded
when available, but a documented manual arrival remains possible. A sampled
plant may have up to three photographs representing views of the same plant.

Evidence is orientation-normalized, checksummed, thumbnailed, and stored in the
application's private files. Evidence records use staged and ready states so
interrupted filesystem and database work can be reconciled.

On-device models produce screening suggestions and provenance. They do not
overwrite evaluator facts, establish pest identity, assign a Davis score, or
authorize treatment. Expert review remains a separate, explicit workflow.

## Completion

A block is complete only when all 20 required plant locations have valid saved
records and the applicable review, evidence, fallback, safety, and
stage-specific requirements pass. Assessment completion revalidates every
required block in the same transaction that saves final metrics and status.

Multiple photographs never increase the plant count. Missing or unavailable
observations are not converted to negative observations. Zero or missing
denominators are displayed as unavailable.

## Results

Results preserve exact numerators, denominators, units, calculation time,
formula version, and warnings. The following remain distinct:

- automatic damage screening;
- current sampled infestation based on the applicable reviewed evidence;
- expert-reviewed FAW damage incidence;
- expert Davis leaf-damage severity; and
- insufficient or unavailable evidence.

Results describe the sampled plants at the assessment date. They do not prove
the condition of every plant or location in the field and do not constitute a
pesticide recommendation.

## Sharing and expert review

Local records remain authoritative for field operation. Cloud synchronization
and account backup are optional. Sending a case to an expert is explicit and
uses the saved consent and sharing rules. Expert findings, messages, plant
ratings, and evidence notes remain separate from automatic screening and local
evaluator observations.
