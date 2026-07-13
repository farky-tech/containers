# Fallbacks

Fallbacks are system signals. Normal quiet work does not belong here.

Format:

```txt
## YYYY-MM-DD — Short name
Expected mechanism:
Actual mechanism:
Cause:
Impact:
Temporary handling:
Learning signal: skill | tool | hook | subagent | test | rule | none
Status: open | accepted-once | converted | closed | blocked   (open = loop-gate debt; blocked = waiting on a human, listed but not blocking; flip via fallback_log.sh --resolve)
```

Rules:
- Record only meaningful fallback, not normal silence.
- Repeated fallback should become a skill/tool/hook/subagent/test/rule proposal.
- Do not store secrets or raw logs here.
