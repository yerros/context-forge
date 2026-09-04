# Code Standards

## General

### CS-003 · Important · enforced: tool
No `console.log` in `src/` — use the `log` module so output is structured and silenced in tests.
```
✗ console.log("saved", id)
✓ log.info("saved", { id })
```
