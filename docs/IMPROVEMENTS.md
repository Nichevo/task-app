# Improvement plan

Running list of changes from Jeff's feedback. Status: ☐ planned · ◐ in progress · ☑ done

## 1. Use the unfolded Samsung Fold screen sensibly ◐

**Feedback:** On the Fold's inner screen the single full-width list wastes space.

**Approach (built on the `fold-layout` branch, awaiting Jeff's OK):** when the screen is wide (unfolded Fold, tablet, or a
wide Windows window) switch to two side-by-side panes:

- **Left:** the task list, exactly as now (colour blocks, drag to reorder, tick off).
- **Right:** the task you tapped, opened for editing in place (name, notes, created, due date),
  so there's no jumping to a separate page. With nothing selected, the right pane shows the archive.

Folded (cover screen) looks as it does today; "Edit / set due date" opens the task full screen,
and back/✕ returns to the list. Folding or unfolding keeps the open task. Two panes kick in at
600 dp wide, so the Fold's inner screen gets them in portrait and landscape.

![Unfolded layout](screenshots/fold.png)

Alternatives considered: a two-column grid of blocks (breaks the "blocks stretch across the
screen" design), or simply larger text/blocks (doesn't use the extra space for anything useful).
