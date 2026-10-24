# WormWise Advisor Agent

## Product decision

Advisor is an in-app FAW domain agent, not a generic chatbot. It combines reviewed fall armyworm guidance, read-only local app context, optional online reasoning, and a closed registry of WormWise actions. A generated answer can propose an action, but only Flutter code resolves it and the farmer must tap it.

## Design basis

The design follows established agent patterns:

- Microsoft Copilot Studio separates planning from knowledge and tools, and recommends explicit confirmation for consequential actions.
- Google Gemini function calling and structured output constrain model responses to application-defined schemas and tools.
- Intercom Fin separates governed knowledge sources from the AI agent that reasons over them.
- Salesforce Agentforce uses a trust layer around model access, grounding, and actions.

References:

- https://learn.microsoft.com/en-us/microsoft-copilot-studio/guidance/generative-orchestration
- https://ai.google.dev/gemini-api/docs/function-calling
- https://ai.google.dev/gemini-api/docs/structured-output
- https://www.intercom.com/help/en/articles/9440354-knowledge-sources-to-power-ai-agents-and-self-serve-support
- https://developer.salesforce.com/docs/ai/agentforce/guide/trust.html

## Runtime

```text
Farmer question or photo
        |
        v
Local Advisor orchestrator
   |          |                 |
   v          v                 v
Live app   Reviewed local    Optional Gemini
context    FAW RAG chunks    grounded planner
   \\          |                 /
    \\         v                /
     +-- structured answer ----+
                 |
                 v
       validated action IDs
                 |
                 v
       farmer taps an action
                 |
                 v
       deterministic Flutter route
```

The local orchestrator handles app navigation, safety-sensitive questions, current-field status, assessment explanations, and known FAW guidance before any remote request. Gemini is a fallback for open-ended reasoning and receives only the context categories the farmer enabled.

## Knowledge and context

- Reviewed offline FAW chunks with source, jurisdiction, review date, and content version metadata.
- The WormWise assessment protocol and calculation explanations.
- A capability registry describing routes that actually exist in the application.
- Read-only local field, crop-cycle, assessment, evidence-count, and metric projections.
- On-device image-model findings, clearly separated from evaluator-confirmed observations.

The current offline retriever uses deterministic lexical scoring. A later production backend can add embeddings and reranking, but must retain chunk metadata, citations, publication status, content versions, and offline fallback behavior.

## Tool and safety policy

- Read-only retrieval and reasoning may run automatically.
- Navigation is always shown as a button and executed only after a tap.
- The model can return only registered action IDs; unknown IDs are discarded.
- Advisor never silently edits an assessment, confirms a diagnosis, or changes a field record.
- Any future write tool must show a preview, require confirmation, use a database transaction, and append an audit record.
- Treatment questions stay on deterministic safety guidance. Advisor does not prescribe pesticide products, rates, or timing.
- Location, assessment details, and other local records are not sent online unless the corresponding sharing setting is enabled.

## Version 1 capabilities

- Switch to Home, Assess, or Map.
- Add/select fields and manage the approximate field outline.
- Start, continue, review, or view results for the current assessment.
- Open reviewed guidelines, field conditions, expert-review messages, account/sync, and Advisor settings.
- Run on-device maize-photo analysis and explain its findings.
- Explain the current field and assessment using live local records.

## Delivery roadmap

1. **Current:** local orchestration, reviewed RAG, read-only context, validated navigation actions, optional Gemini fallback, and persisted conversations/actions.
2. **Retrieval depth:** granular read tools for all fields and assessments, exact workflow-location awareness, hybrid retrieval, reranking, and richer citation views.
3. **Confirmed writes:** narrowly scoped actions such as drafting a note or updating a field attribute, each with preview, confirmation, transaction, rollback behavior, and audit logging.
4. **Production platform:** backend model proxy, server-managed keys, indexed knowledge publication, telemetry with privacy controls, regression evaluations, and content governance.

## Acceptance checks

- A known route request works offline and produces a valid action button.
- The recommended next step changes correctly for no field, missing boundary, no assessment, active assessment, and completed assessment.
- Unknown model action IDs never execute.
- Remote reasoning still returns a useful grounded answer when no action is appropriate.
- Source/version information is visible on every Advisor response.
- Clearing or restoring a conversation also clears or restores its registered actions.
- No Advisor operation mutates assessment data without a separately designed confirmation flow.
