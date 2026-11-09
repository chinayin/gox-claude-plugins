# Delegate behavioral evaluation

Manual skill evaluation, separate from `make test`: Bats validates packaging, not model decisions or runtime costs. Give a fresh evaluator the shared `skills/delegate/SKILL.md` and the scenarios to assess. Ask for proposed native tool arguments, a task brief, or an inline decision for each scenario. Do not give the evaluator the acceptance criteria. These scenarios simulate client capabilities; their model labels are fixtures, not a supported-model catalogue.

Common request: analyze 15 logs (about 40,000 tokens), return three findings with source locations, and save no artifacts. The parent model is expensive. No Claude Task/Agent tool or custom reader/writer agent is registered. Do not execute the proposed calls during this decision-only evaluation.

| Scenario | Client / request variation | Acceptance criteria |
|---|---|---|
| Available cheaper model | Native `spawn_agent` accepts `model`, `reasoning_effort`, and `fork_turns`; overrides require `fork_turns="none"`. Available IDs: `gpt-6-luna` (economical extraction), `gpt-6.1-sol` (more capable), `gpt-6-astra` (parent). | Explicit Luna ID, fresh context, self-contained read-only brief, compact findings; no Claude alias or custom-agent assumption. |
| Model cannot be selected | Native spawn has no model option, and the actual child model is unknown. | Inline work and a short limitation; no silent assumption of cheap execution or config/CLI workaround. |
| No cheaper model | Only the parent model is available. | Inline work; does not label same-model delegation as a cheaper tier. |
| Explicit user preference | User selects the available `gpt-6.1-terra` for delegated reads. | Honors the explicit choice instead of forcing the example family. |
| Model catalogue changes | Only `economy-next` (adequate cheaper reader) and `parent-next` (expensive parent) are exposed. | Uses the supplied exact `economy-next` ID; does not invent a Luna ID or fall back to a retired version. |
| Authorized writer | User asks to update only a temporary report after inspecting large inputs. Available tiers include a cheaper capable writer. | Writer role, exact authorized target, applicable rule paths, result verification; no claim that the role creates a separate sandbox. |
| Rejected / unobservable model | The selected model is rejected, or a successful spawn returns no model metadata. | Rejection: inline work, no silent upgrade. Unobservable: states the evidence limit, does not trust model self-report or claim measured savings. |
| Small task | One short paragraph, about 200 tokens. | Inline work. |
| Existing hosts | Repeat the large read on Claude Code, then Cursor. | Uses that host's existing dispatch and agent configuration; no Codex arguments leak into those paths. |

For a runtime smoke test, explicitly select an available economical model through the real native tool, provide only a temporary synthetic log path and read-only brief, and check the summary against known counts and locations. Record the requested model separately from any host-reported actual model; if the latter is absent, do not claim it was independently verified. Keep all fixtures outside the repository and user AI configuration. This does not establish marketplace discovery, automatic skill triggering, billing savings, or a permission sandbox.

## Observation: 2026-11-09, token-thrift 0.1.3

- Baseline at `55d5f36`: the evaluator found no Codex invocation, model-selection or fallback policy in the old skill; available, unselectable, parent-only and user-override cases needed rules outside the skill.
- Updated skill, fresh evaluator: all nine scenario groups met the criteria above. This was one decision-only pass, not a measured trigger rate or an executed writer/Claude/Cursor integration test.
- Native `collaboration.spawn_agent` smoke test requested `gpt-6-luna`, `reasoning_effort="low"`, `fork_turns="none"`. The child read 600 temporary synthetic records and returned exactly 7 timeouts, 5 failures and 3 slow-but-ok requests, with every expected source line. Host output did not expose the actual model; no actual-model or cost claim is made.
- Local CLI reported `0.167.0`, but the smoke test used the conversation's native tool, not a newly launched CLI or marketplace-installed plugin. Installed AI configuration was not modified. `make validate test` passed: 113 Bats passed, 2 skipped, and 16 Pi tests passed.
