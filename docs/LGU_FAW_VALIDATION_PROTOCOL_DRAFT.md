# WormWise LGU Fall Armyworm Case Validation Protocol

## Document control

| Item | Value |
|---|---|
| Document status | Draft for LGU technical review and approval |
| Version | 0.1 |
| Intended pilot area | Piat, Cagayan, Philippines |
| System | WormWise mobile application and expert web dashboard |
| Protocol owner | To be assigned by the approving LGU agriculture office |
| Effective date | Not effective until formally approved |
| Review date | To be assigned |

> **Important:** This document is a proposed operating protocol. It does not
> represent LGU, Department of Agriculture, Bureau of Plant Industry, Regional
> Crop Protection Center, or Fertilizer and Pesticide Authority approval. The
> approving office must review, amend, sign, train users on, and periodically
> review this protocol before WormWise describes an assessment as
> "LGU-validated."

## 1. Purpose

This protocol defines a consistent process for an authorized LGU agricultural
reviewer to evaluate a farmer-submitted WormWise assessment of suspected fall
armyworm (FAW) in maize. It covers the review of:

- the submitted field and assessment information;
- field observations and calculated infestation metrics;
- photographs associated with the correct station and plant;
- WormWise model outputs;
- the field location or boundary, when the farmer consented to share it; and
- follow-up information exchanged through the expert conversation.

The protocol is intended to make reviews traceable, repeatable, understandable
to farmers, and suitable for supervised pilot testing.

## 2. Scope and limitations

This protocol applies only to WormWise assessments of suspected FAW in maize
that were completed using the assessment version recorded in the submitted
case.

It does **not**:

- make WormWise an official pest-certification system;
- replace physical field inspection, laboratory identification, or an official
  surveillance procedure when one is required;
- establish land ownership or a cadastral boundary;
- authorize a pesticide, product, dose, mixture, application method, or use;
- turn an AI classification into expert confirmation; or
- allow the reviewer to infer missing observations, consent, or evidence.

An official FAW certification feature may be considered only after the LGU has
validated the assessment, AI-screening, expert-review, and GIS workflows and
has separately approved a certification policy.

## 3. Minimal operating roles

The pilot uses a deliberately simple role structure.

### 3.1 Submitter

The farmer, farm representative, technician, or enumerator who completes the
mobile assessment and submits it for review. The submitter is responsible for
providing truthful observations, assigning photographs to the correct station
and plant, and identifying the field and barangay.

### 3.2 Authorized LGU reviewer

An agricultural professional designated in writing by the participating LGU
agriculture office. The reviewer examines the case, asks for missing
information, records the validation finding and rationale, and communicates the
result to the submitter.

### 3.3 LGU protocol owner or supervisor

The person designated by the LGU to approve reviewer access, resolve uncertain
or disputed cases, maintain this protocol, and coordinate referrals. This role
may be performed by the same office and does not require a separate software
account during the pilot.

Only approved reviewer accounts may access submitted cases. WormWise developers
must not make an agricultural validation decision unless they are separately
authorized and qualified by the participating LGU.

## 4. Meaning of validation

Within this protocol, **validation** means that an authorized reviewer has
examined the available WormWise record and selected one of the findings in
Section 10, with a written rationale.

Validation is not automatically equivalent to laboratory confirmation,
municipal outbreak declaration, treatment authorization, or LGU certification.
The farmer-facing result must state the evidence level and any remaining
uncertainty.

## 5. Preconditions for accepting a case

A case may enter the review queue only when:

1. the assessment is marked complete;
2. the assessment date, field name, barangay, crop growth stage, sampling
   pattern, and protocol version are present;
3. the calculated metrics and warnings are stored as a result snapshot;
4. the farmer or representative name is provided for follow-up;
5. the record identifies the submitting WormWise account or guest identity;
6. consent choices for photographs and location are explicitly recorded; and
7. the submission has a unique case and assessment identifier.

Photograph and location sharing are optional. A submission without either may
still be reviewed, but the reviewer must not claim to have verified evidence
that was not supplied. The reviewer may request additional information or
require a field visit when the available record is insufficient.

## 6. Review priority and target time

The LGU must define the normal review time before pilot deployment:

- normal case target: **[LGU to define]** working days;
- urgent case target: **[LGU to define]** working hours or days; and
- operating hours and contact method: **[LGU to define]**.

Suggested reasons for priority review include a suspected new-area occurrence,
rapidly increasing fresh injury, extensive contiguous damage, uncertainty that
could affect many farms, or a possible safety issue. The dashboard priority
must not be interpreted as confirmation of FAW or severity.

## 7. Case status workflow

The dashboard status describes workflow progress, not the scientific finding.

| Case status | Required meaning |
|---|---|
| Pending | Submitted and waiting for review |
| Under review / claimed | An authorized reviewer has begun the review |
| Needs information | The reviewer asked for specific missing or clearer information |
| Advice sent | The reviewer sent a completed response or next-step guidance |
| Closed | Review is complete, withdrawn, duplicated, or outside scope; the reason must be recorded |

The dashboard and mobile app should display status changes and messages in
chronological order. A case must not be closed merely to remove it from the
queue.

## 8. Required review sequence

The reviewer shall complete the following checks in order.

### 8.1 Confirm identity, scope, and consent

- Confirm that the crop is maize and the case is within the participating
  office's geographic and operational scope.
- Confirm the field, barangay, assessment date, recorded growth stage, and
  submitter.
- View photographs only when evidence consent is recorded.
- View the boundary or approximate location only when location consent is
  recorded.
- Do not request or record unnecessary personal information.

### 8.2 Check protocol integrity

- Confirm the assessment is complete and identify its protocol version.
- Review the sampling pattern, number of stations, number of plants or planting
  positions assessed, and any incomplete or overridden steps.
- Check safety warnings, quality warnings, and unusual denominators.
- Do not compare a metric to a threshold unless both use compatible growth
  stages, observations, denominators, and assessment definitions.
- If the protocol is incomplete or incompatible, select **Needs information**
  or **Cannot validate from submitted record**.

### 8.3 Review field observations and metrics

- Inspect the underlying counts before relying on percentages.
- Confirm that the denominator represents the intended assessed plants or
  planting positions.
- Distinguish current direct evidence, current supporting evidence, old or
  ambiguous damage, contradictory evidence, and missing evidence.
- Treat WormWise metrics as descriptive outputs unless the LGU has approved a
  specific action threshold for the exact protocol and growth stage.
- Record contradictions between counts, photographs, crop stage, and the
  generated result.

### 8.4 Review photographic evidence

Photographs must be reviewed by station and plant. The reviewer should check:

- that the image is associated with the stated station and plant;
- focus, lighting, scale, framing, and whether the relevant plant part is
  visible;
- whether evidence appears fresh, old, ambiguous, or unrelated;
- whether multiple diagnostic features are visible rather than relying on a
  single sign; and
- whether the image contradicts the submitted observation.

Fresh feeding, windowpaning, holes, frass, whorl injury, cutting, or ear injury
may be compatible with FAW, but damage appearance alone does not confirm the
species. A larva image should show enough detail for an expert to evaluate
multiple FAW-compatible features. Unclear or cropped images must be labelled
insufficient rather than assumed positive.

The reviewer shall not treat an absent photograph as negative evidence. Images
that appear mismatched, duplicated, materially edited, or assigned to the wrong
plant require clarification.

### 8.5 Review AI/model outputs

WormWise model outputs are screening aids only.

- **Model 1** screens whether the image appears to show FAW-compatible damage
  versus not-FAW-compatible damage.
- **Model 2** may run only after a positive Model 1 screen and evaluates the
  approved secondary FAW evidence task configured in the application.
- A model confidence score is not a probability that the official diagnosis is
  correct.
- The reviewer must examine the source image and field observations, not only
  the model label.
- A model result must not override clear contradictory evidence.
- Low-quality, out-of-scope, or uncertain images must be rejected or referred
  for more evidence.

WormWise must preserve the model version, label, confidence or score, date, and
source image association for audit. Model thresholds remain engineering
settings until the LGU approves them through documented local validation.

### 8.6 Review the GIS information

When location consent exists, confirm that:

- the displayed boundary belongs to the submitted field record;
- the case map uses the stored coordinates for that assessment and not a
  default, device-current, or unrelated field location;
- the boundary shape is displayed in geographic alignment with the basemap;
- the map distinguishes field boundary, assessment stations, and device
  position; and
- any obvious location mismatch is resolved with the submitter.

Phone GPS and user-drawn boundaries are approximate. They may support field
identification and follow-up but are not proof of ownership, legal boundary, or
survey-grade position. If location consent is absent, the reviewer shall rely
only on the text location supplied for the case.

### 8.7 Reconcile the complete record

Before deciding, the reviewer shall compare the submitted observations,
metrics, photographs, model outputs, location context, warnings, and follow-up
answers. A strong result in one source does not erase contradictions in another.
Unresolved contradictions require more information, a field visit, or an
uncertain finding.

## 9. When to request more information or a field visit

Request specific information rather than sending a generic rejection. Examples
include:

- a clear close-up and whole-plant context image from a named station and plant;
- confirmation of crop growth stage or assessment date;
- clarification of fresh versus old damage;
- missing counts or an invalid denominator;
- evidence from additional affected and unaffected plants;
- correction of a field/location mismatch; or
- recent treatment history when it affects safety or interpretation.

A field visit should be considered when the record remains contradictory,
species identification affects an important decision, the event may have wider
surveillance significance, submitted evidence cannot represent field
conditions, or safe remote guidance is not possible.

## 10. Validation findings

The reviewer shall record one primary finding. These findings should be stored
separately from the workflow status.

| Finding | Use when |
|---|---|
| FAW confirmed by authorized reviewer | The reviewer has sufficient direct diagnostic evidence under the LGU-approved identification standard; state whether confirmation was remote, field-based, or laboratory-supported |
| Evidence consistent with FAW | Current observations support suspected FAW, but the evidence does not justify species confirmation |
| Possible non-FAW cause | Evidence is more compatible with another pest, disease, nutrient, weather, herbicide, planting, animal, or mechanical cause |
| Mixed or uncertain evidence | Evidence conflicts or cannot distinguish FAW from alternatives |
| Cannot validate from submitted record | Required observations, image quality, traceability, or protocol completeness are insufficient |
| Outside scope | The crop, location, case type, or requested decision is outside this protocol |

For every finding, the reviewer shall record:

1. the evidence relied upon;
2. important contradictory or missing evidence;
3. the confidence or uncertainty in plain language;
4. whether field verification is required;
5. the safe next step; and
6. reviewer name, office, date, and time.

The term **FAW confirmed** must remain disabled until the approving LGU defines
and signs the minimum diagnostic evidence standard.

## 11. Farmer response standard

The final response should be concise and understandable. It must contain:

- **Finding:** what the evidence supports;
- **Basis:** the most important observations or photographs;
- **Uncertainty:** what could not be confirmed;
- **Next step:** monitoring, additional evidence, field visit, or referral; and
- **Safety:** any relevant non-product-specific safety instruction.

Suggested structure:

> **Finding:** [validation finding].  
> **Basis:** [brief evidence summary].  
> **Uncertainty:** [missing or conflicting evidence].  
> **Next step:** [specific safe action and timeframe].  
> **Reviewed by:** [name/office/date].

The reviewer must not recommend a pesticide solely from a model result, damage
percentage, or photograph. Any chemical-control discussion must follow current
Philippine registration, the product label, applicable LGU/DA guidance, crop and
growth stage, safety requirements, and the reviewer's authorization.

## 12. Escalation and referral

The LGU protocol owner must define local contacts for:

- uncertain identification or suspected new-area occurrence;
- severe, rapidly changing, or multi-field reports;
- failed treatment or suspected resistance;
- possible grain/feed safety or contamination concerns;
- pesticide registration, restriction, poisoning, or label questions; and
- system, privacy, or data-quality incidents.

| Referral type | Office/contact | Contact method | Availability |
|---|---|---|---|
| LGU field verification | [LGU to complete] | [LGU to complete] | [LGU to complete] |
| Regional crop-protection support | [LGU to complete] | [LGU to complete] | [LGU to complete] |
| Regulatory/safety question | [LGU to complete] | [LGU to complete] | [LGU to complete] |
| Emergency/poisoning | [LGU to complete from an authoritative source] | [LGU to complete] | [LGU to complete] |

WormWise must not invent a contact or show an unverified emergency number.

## 13. Privacy, consent, and access

- Collect only data needed to perform and audit the review.
- Keep evidence photographs private and available only to the submitter and
  authorized reviewers assigned access under approved security rules.
- Enforce location and evidence consent independently.
- Do not expose precise coordinates when location consent is false.
- Avoid including faces, identification cards, unrelated people, house details,
  or other unnecessary personal information in field evidence.
- Record reviewer access, status changes, decisions, and messages.
- Define retention, correction, export, and deletion rules before the official
  pilot: **[LGU and project team to complete]**.
- Report unauthorized access or disclosure to the designated protocol owner.

## 14. Audit record

Each review must retain, at minimum:

- case and assessment identifier;
- protocol and model versions;
- original result snapshot and calculated metrics;
- submitted evidence associations and checksums where available;
- consent state at submission;
- reviewer identity and timestamps;
- every status change and message in chronological order;
- requests for more information and the response;
- final validation finding, rationale, and escalation; and
- later correction or reopening, with reason.

The final finding must not silently overwrite the original farmer submission or
model output.

## 15. Quality assurance for the pilot

Before approval for routine use, the LGU and WormWise team should:

1. agree on the diagnostic and evidence definitions;
2. test the workflow on a labelled local case set that includes FAW, non-FAW,
   uncertain, poor-quality, and incomplete submissions;
3. compare remote WormWise review with field expert findings;
4. measure agreement, false-positive and false-negative outcomes, unusable-image
   rates, time to response, and cases requiring field visits;
5. have a second reviewer independently review a defined sample;
6. document disagreements and revise the protocol or application;
7. verify access control, consent enforcement, map-field matching, audit logs,
   message ordering, and notification delivery; and
8. approve the protocol version and model versions permitted for the pilot.

Suggested pilot acceptance values must be set by the LGU and technical adviser;
WormWise shall not invent passing percentages.

## 16. Reviewer checklist

Before sending a final response, confirm:

- [ ] I am authorized to review this case.
- [ ] The case is maize, in scope, and uses an identified protocol version.
- [ ] I checked assessment completeness, counts, denominators, warnings, and
      crop stage.
- [ ] I reviewed evidence by the correct station and plant.
- [ ] I treated AI output as screening support, not the final decision.
- [ ] I viewed photographs and location only with the corresponding consent.
- [ ] The displayed map belongs to this assessment field.
- [ ] I considered contradictory and non-FAW evidence.
- [ ] My finding uses one approved category and states uncertainty.
- [ ] My response gives a specific, safe next step.
- [ ] I did not give an unsupported pesticide recommendation.
- [ ] My name, office, rationale, date, and time are recorded.

## 17. LGU approval checklist

The approving office must complete these items before operational adoption:

- [ ] Name the authorized LGU office, protocol owner, and reviewers.
- [ ] Approve or revise the scope, terminology, and case findings.
- [ ] Define minimum evidence for “FAW confirmed.”
- [ ] Approve the WormWise assessment protocol and applicable growth stages.
- [ ] Decide whether any locally used thresholds are authorized and document
      their exact definitions and sources.
- [ ] Define response targets, escalation contacts, and field-visit rules.
- [ ] Approve consent, access, retention, correction, and deletion rules.
- [ ] Review model validation results and approve permitted model versions.
- [ ] Test the mobile-to-dashboard workflow and audit trail.
- [ ] Train reviewers and document completion.
- [ ] Sign and date the approved version.

## 18. Approval record

| Approval item | Details |
|---|---|
| LGU office | |
| Approved protocol version | |
| Approved pilot area and dates | |
| Conditions or exclusions | |
| Authorized reviewer(s) | |
| Protocol owner/supervisor | |
| Approving official name and position | |
| Signature | |
| Date | |

## 19. WormWise source documents

This draft must be read together with:

- `ASSESSMENT_PROTOCOL.md` — assessment definitions and field workflow;
- `docs/FAW_OFFLINE_REFERENCE.md` — governed FAW reference and safety limits;
- `docs/SUPABASE_SETUP.md` — cloud configuration and security deployment;
- the deployed Supabase migrations — case access, submission, messaging, and
  audit-related database behavior; and
- the model card and local validation report for every model version submitted
  for LGU review.

If an approved government protocol conflicts with this draft, the official
protocol takes precedence and WormWise must be updated and revalidated before
continued use.
