# Unit NN: [Feature Name]

## Goal

One or two sentences describing the concrete output of this unit.

## Assumptions

<!-- Optional — include ONLY when the spec resolved an ambiguity or made a
     judgment call the request didn't dictate. Each line is a veto point for
     the user before any code exists. Omit the section when there are none.
     Genuinely design-changing ambiguity is still returned as a question,
     never assumed (see forge-architect ground rules). -->

- [assumption made] — [why this reading was chosen]

## Design

Visual and structural decisions specific to this unit.
Reference ui-context.md tokens where relevant.

## Implementation

### [Component or Sub-section Name]

Detailed description of what to build.

### [Next sub-section]

Description.

## Dependencies

- package-name (reason)

## Tests

<!-- The automated tests THIS unit must ship with (written during implementation,
     not after). Name what is tested and at what level; "none — [reason]" is
     allowed for pure-visual/config units, but say so explicitly. -->

- [test level: unit/integration/e2e] [behavior it must prove]
- ...

## Verify when done

- [ ] Condition one
- [ ] Condition two
- [ ] This unit's tests (above) written and green
- [ ] Full test suite green (no regressions in earlier units)
- [ ] No TypeScript errors
- [ ] No console errors
- [ ] Responsive at mobile and desktop
- [ ] Build passes
