# Prompt Router

Use this when a user prompt arrives.

```txt
Classify the task quietly:
- build / implement
- review / audit
- research
- planning
- debugging
- memory / learning
- close / handoff
- external write / risky action

Then check:
- Is this long-running or multi-phase work that needs TodoWrite?
- Is there a matching skill?
- Is a subagent useful and available?
- Is a hook/tool expected to handle part of this?
- Does this create durable learning?
- Does this require a gate/GO?

If a capability fits, use it quietly.
If you do not use a fitting or prompted capability, say why.
If TodoWrite continuity is required, keep the ledger visible.
```
