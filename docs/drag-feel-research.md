# Drag Feel — Survey + Recommendation

**Date:** 2026-08-03
**Question:** how do well-regarded products make card/object dragging feel physical, without hurting drop accuracy or perceived latency?
**Scope:** research only, no code changes. Targets `SpatialCanvas`'s existing per-card drag path (`_buildEntity` → `Positioned` → `Transform.rotate` → `RepaintBoundary` → `GestureDetector`, `lib/src/spatial_canvas.dart`).

---

## 1. Survey

**Material Design** — elevation is the whole mechanism. A card is 1dp at rest and jumps to 8dp while dragged (desktop: 0dp → 4dp on hover); levels +4/+5 in the elevation scale are reserved specifically for "user-interacted" states like drag. No scale or tilt in the spec — shadow depth alone carries the "lifted" read. [Elevation & shadows (M1)](https://m1.material.io/material-design/elevation-shadows.html), [Elevation (M3)](https://m3.material.io/styles/elevation/applying-elevation).

**Apple / WWDC "Designing Fluid Interfaces"** — the core rule is continuity: an animation must always start from the object's *current* on-screen value and inherit the gesture's velocity, so the object can be grabbed, reversed, or re-thrown at any instant with no reset-to-start pop. Springs are specified as `damping` (bounciness) + `response` (speed in seconds), not duration+curve. House style: `damping ≈ 1.0` (critically damped, no bounce) for most repositioning; drop to `damping ≈ 0.8` only for momentum-carrying releases (a flick, a thrown card). [WWDC18 Session 803](https://developer.apple.com/videos/play/wwdc2018/803/), [Building Fluid Interfaces (Gitter)](https://medium.com/@nathangitter/building-fluid-interfaces-ios-swift-9732bb934bf5).

**iOS HIG (Drag and Drop)** — content "rises and adheres to the finger" on touch-and-hold (the lift), then haptics confirm pickup and drop. The lift is presented as a qualitative affordance; Apple doesn't publish a scale number. [HIG: Drag and drop](https://developers.apple.com/design/human-interface-guidelines/ios/user-interaction/drag-and-drop/).

**Figma / FigJam, Miro** — both are cited in UX writeups as using the same three-cue combo for a "grabbed" object: slight scale-up, deeper shadow, small tilt, applied together rather than any single cue alone. Neither publishes exact numbers. [LogRocket, Designing drag-and-drop UIs](https://blog.logrocket.com/ux-design/drag-and-drop-ui-examples/).

**Trello** — the drag image gets a small rotation on pickup (a few degrees) plus a standard box-shadow, and — importantly — a placeholder is left at the origin and a drop-target placeholder shown at the destination, so the user never loses track of "before" and "after" state while the card itself is mid-air. [Trello-style drag write-up](https://medium.com/swlh/trello-style-drag-and-drop-using-vue-smooth-dnd-5daa0a7b4e7f).

**Milanote / Apple Freeform** — both use a plain drop-shadow-appears-on-pickup pattern to sell "you lifted this off the desk"; no tilt or scale reported for either. Freeform's shadow is literally a per-object style property, always visible for sticky notes, so drag doesn't need to *introduce* it, only deepen it. [Milanote deep dive](https://medium.com/@alitapwrites/a-deep-dive-of-the-drag-and-drop-organizational-tool-milanote-8a38b3b16148), [Freeform shadow support](https://support.apple.com/guide/freeform/move-items-frfm220e044a/mac).

**Counter-example — Atlassian's react-beautiful-dnd** — explicitly *rejected* drop shadows. Their reasoning: a shadow raises unanswerable questions (where does it render between list items? how does it behave crossing lists?) that usually get "solved" by snapping the dragged item, which breaks the physical metaphor they were going for instead of reinforcing it. They lean entirely on animated *movement* (other items glide out of the way, the dropped item glides into its final slot) rather than depth cues. Also deliberately avoided axis-locking/drag rails as "breaking the physical metaphor." [design-principles.md](https://github.com/atlassian/react-beautiful-dnd/blob/master/docs/about/design-principles.md).

**Game-feel / "juice"** — the relevant transferable idea is squash-and-stretch read as mass: a dragged object that visibly "settles" (slight overshoot then rest) on drop reads as having weight; overdone, it reads as slow or gimmicky. The genre's own caution: juice is a *garnish* applied after the core interaction already feels responsive, never a fix for an interaction that feels laggy. [Game feel on the web](https://valdemird.com/blog/game-feel-on-the-web/).

### Cross-cutting pattern
Every source that publishes a mechanism uses **shadow/elevation** as the primary "lifted" signal, adds **scale and/or tilt** as secondary reinforcement, and — critically — **every single one tracks the cursor/finger 1:1 during the drag itself.** Nobody makes the object visually lag behind the pointer while moving; the "physics" is reserved for the pickup transition and the release/settle, never for live tracking. That's the accuracy guardrail: lag reads as latency and desyncs the visual drop point from the actual one.

### What they deliberately don't do, and why
- **No position lag/spring during the move.** Confirmed by Apple's continuity rule (start from current value, don't animate the tracked position itself) and implicit in every other product surveyed — direct manipulation requires the object to *be* where the finger is, not chase it.
- **react-beautiful-dnd: no shadow at all**, to avoid the multi-list edge cases and the temptation to snap.
- **LogRocket's drag-and-drop UX guidance:** don't use drag-and-drop at all when pixel-perfect placement matters — offer a numeric fallback. (Not applicable here since desk placement is inherently spatial/approximate, but worth knowing the line exists.)
- **Nobody uses elastic/bounce overshoot on *pickup*** — only optionally on *release*, and only for momentum-carrying throws, per Apple's damping guidance (0.8 reserved for gesture-driven momentum, 1.0 elsewhere).

---

## 2. Recommendation for this app

Architecture constraint: `_buildEntity` already tracks `isDraggingThis` (bool) and swaps in `_dragPreviewPosition` during a drag (`spatial_canvas.dart:316-317`). The card visuals themselves are drawn by the *consumer's* `entityBuilder` (currently receives only `(entity, isSelected)` — no drag flag), inside `Transform.rotate(angle: entity.rotation)` → `RepaintBoundary`. Any lift affordance that lives *outside* `entityBuilder` (a wrapping shadow/scale) can ship without touching the `entityBuilder` contract; anything that needs `entityBuilder` to know it's being dragged (e.g. the renderer itself painting a shadow) requires a breaking signature change across two packages (`pin_and_paper_canvas` + `pin_and_paper_card_renderer`). Rotation is already a live field (`entity.rotation`, degrees) feeding `Transform.rotate` — any drag-tilt has to be layered as a delta on top of it, not a replacement.

All three candidates below keep the card's *position* tracking the cursor 1:1, unclamped, every frame — no spring/lag is ever applied to the tracked coordinate. Physics is confined to the pickup and release transitions.

### Candidate 1 — Lift only: scale + shadow (try this first)
- **Scale:** 1.0 → **1.03** on pickup.
- **Shadow:** grow blur/offset to roughly Material's dragged-card delta (their 1dp→8dp jump) — concretely, blur `2px → 10px`, `y-offset 1px → 6px`, opacity ~0.15 → ~0.25.
- **Duration/curve:** **120ms**, `Curves.easeOut` in, **150ms** `Curves.easeIn` back out on drop.
- **Where it lives:** a `DecoratedBox`/`PhysicalModel` + `AnimatedScale` wrapping the existing `Transform.rotate` child, driven off `isDraggingThis` — **no `entityBuilder` signature change needed.**
- **Cost/risk:** lowest. No accuracy impact (position untouched). Perceived-latency risk near zero — 120ms is well under the ~200-300ms threshold where users register a lag. Implementation is a single wrap in `_buildEntity`.

### Candidate 2 — Lift + directional tilt
- Everything in Candidate 1, plus a small rotation **delta** (not replacing `entity.rotation`) driven by drag velocity: clamp to **±5°**, proportional to horizontal pan speed, springing back to 0° over **~180ms** on release (`Curves.easeOutBack` gives a faint overshoot-then-settle without being cartoonish).
- **Tunable knobs:** max tilt angle (start 5°, try 3-8°), velocity-to-angle sensitivity, return curve.
- **Cost/risk:** moderate. Needs velocity tracking in `_handlePanUpdate` (delta between frames) that doesn't currently exist. Risk to *feel*, not accuracy: too much tilt on a small card can read as "wobbly" rather than "physical" — this is the knob most worth tuning by eye first, in isolation, before combining with Candidate 1's shadow.

### Candidate 3 — Lift + tilt + release settle
- Everything in Candidate 2, plus a brief **overshoot-and-settle** on drop: scale briefly dips to **0.99** then eases back to 1.0, shadow collapses over **180-220ms**, `Curves.easeOutBack` or a real spring (`SpringDescription` approximating Apple's `damping 0.8 / response 0.3` for a momentum-driven release, `damping 1.0` for a deliberate slow-release).
- **Cost/risk:** highest of the three, and the one most likely to read as "trying too hard" if the durations creep up. No accuracy risk (still resolves position identically to 1 and 2), but it's the candidate most likely to feel like added latency if the settle duration is tuned too long — keep total release animation under ~250ms. Also the most implementation work (needs a distinct post-release animation controller, not just an `AnimatedScale`/`AnimatedContainer` toggle).

### Try this first
**Candidate 1.** It's the one every well-documented source agrees on (Material's whole spec *is* this), it's cheap to build against the current architecture without touching the `entityBuilder` contract, and it's the safest against your two stated fears: zero position/accuracy impact, and short enough (120-150ms) that it won't read as lag. Ship it, sit with it for a few days of actual use, then layer Candidate 2's tilt only if the lift alone still feels inert — tilt is a taste call, not a correctness one, so it's the right thing to tune by eye rather than get right on paper.
