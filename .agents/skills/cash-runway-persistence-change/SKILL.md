---
name: cash-runway-persistence-change
description: "Plan, implement, or review Cash Runway persistence changes. Use for migrations, repository seams, schema compatibility, and backward-compatible data handling across app versions."
---

# Cash Runway Persistence Change

Use this skill for migrations, repository or protocol seam changes, backup/export/restore compatibility, and other persistence work in Cash Runway.

## Core Rules
- Check the partial-schema migration tests before adding or changing migrations.
- Guard optional legacy tables and columns in migrations and runtime schema access.
- Treat backup/export/restore compatibility as part of the change; do not break older exports or restores.
- Every new repository or protocol seam needs at least one direct behavioral test that exercises the public seam.
- Start with the smallest relevant validation gate, then widen only if the change crosses multiple layers.

## Common Failure Patterns
- Migration assumes a table or column always exists during partial-schema install or downgrade.
- Repository method added without a test that drives the real behavior through a public call site.
- Backup/export path writes a schema version that restore cannot read.
- Compatibility change passes unit tests but fails `just check-integration` or `just check`.

## Validation Gates
- Use targeted tests for the affected persistence or repository area first.
- Use `just check-integration` when schema or persistence behavior crosses database boundaries.
- Use `just check` when the change touches release gates, backup/export/restore flows, or broader integration behavior.
