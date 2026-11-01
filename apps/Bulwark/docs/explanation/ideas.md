# Ideas list

*Understanding-oriented — evidence-tagged ideas that are not built. Nothing here
is in `assets/content/interventions.json` yet, and none of it is a promise.*

Each line gives the idea, its evidence tag as the schema spells it
([`rct` / `observational` / `mechanistic` / `traditional`](../reference/content-schema.md#evidence)),
the source as a note cited it, and the file it would go into. Every source is
**as cited in a source note; verify before use.** Tags are proposals; the
reviewer who builds the card assigns the final one.

Rules for anyone building from this list:

- Cards follow [ADR-0004](../adr/0004-de-personalization-law.md): general knowledge,
  generic wording, no brand names, and the denylist test must pass.
- Advice only advises ([ADR-0003](../adr/0003-advisory-pacing-never-blocking.md)).
- Health design laws are stated positively. A feature is justified by what it
  gives the person, never by a condition it hopes to prevent.
- Lines marked **clinician review** need wording checked by a clinician before
  they ship, because they touch pregnancy, surgery or symptoms.
- Safety notes stay calm cautions, as in [limitations.md](../limitations.md).

Paths below are relative to the repo root. "details" and "safety" mean the
fields of the same name on the named card.

## Strength and movement

| Idea | Tag | Source as cited | Target |
|---|---|---|---|
| Use safety catches or a spotter for any solo barbell squat or bench | mechanistic | none given | `assets/content/interventions.json`, `strength-training` safety |
| For distance, carry a ruck in a framed pack with a hip belt | traditional (low confidence; the note's source is hearsay) | none given | `assets/content/interventions.json`, `rucking` details |
| Double progression with dumbbells: add reps up to the top of a range, then add load | traditional | none given | `strength-training` details |
| Hard sets near the limit grow muscle across a wide range of loads | rct | Schoenfeld 2017 meta-analysis | `strength-training` details |
| Weekly set volume has a dose-response for growth | rct | Schoenfeld 2017 and 2019 meta-analyses | `strength-training` details |
| Enough protein alongside resistance training improves gains | rct | Morton 2018 meta-analysis | `strength-training` or `protein-breakfast` details |
| Deload: about half the volume for a week, every 4 to 6 weeks | mechanistic | none given | `strength-training` details |
| Unusual pain that radiates, numbness, or pain at night is a cue to pause and see a clinician (**clinician review**) | mechanistic | clinical guidance, unnamed | `strength-training` safety |
| Space hard leg days and hard endurance days apart | mechanistic | the interference literature, as cited in a source note | `zone-2-training` details |
| Zone 2 base plus a small dose of short hard intervals | rct | none given | `zone-2-training` details |
| A daily step target; benefit levels off near 8 to 10 thousand a day for adults under 60 | observational | Paluch 2022 meta-analysis | new card in `assets/content/interventions.json` |
| Postpartum pelvic-floor assessment by a physical therapist before returning to impact (**clinician review**) | observational | none given | `pelvic-floor-kegels` details; New Parent preset in `assets/content/presets.json` |

## Staying with it

| Idea | Tag | Source as cited | Target |
|---|---|---|---|
| "The floor holds": on a missed day, resume; never make it up. Design law, stated positively | traditional | none given | `docs/design-philosophy.md` |
| Prove a habit before prepaying for it; prepaid memberships did not raise attendance | observational | DellaVigna and Malmendier 2006 | `docs/explanation/personas.md` or a how-to |
| A named accountability partner helps. Support only; no stakes or penalties, in keeping with the no-guilt law | observational | none given | `docs/how-to/everyday-tasks.md` or a new card |
| Steer by a 7-day average, not one reading | traditional (coaching heuristic) | none given | a new card, or the weekly-pulse wording in `docs/reference/engine-rules.md` |

## Measurement and buying

| Idea | Tag | Source as cited | Target |
|---|---|---|---|
| Weekly home blood-pressure reading, read as a trend | observational | none given | new card in `assets/content/interventions.json` |
| Keep one dated list of results from the same lab; read the slope, not one value | mechanistic | none given | `annual-bloodwork` details |
| Decide before a test what you would do with a surprise result; looking and acting are separate steps (**clinician review**) | observational | a national screening example, unnamed | `annual-bloodwork` safety |
| Supplement buying criteria: the active form, a stated dose that matches studies, per-batch third-party testing; a paid seal alone is not enough | observational | a 2025 testing study of over-the-counter prenatal products | `shopping.criteria` text in `assets/content/interventions.json`; `docs/reference/content-schema.md` |
| Check levels before dosing iron, vitamin D or omega-3 | mechanistic | none given | `avoid-megadosing` details |

## Pregnancy (all need **clinician review** before any card)

| Idea | Tag | Source as cited | Target |
|---|---|---|---|
| Choline from eggs and fish while expecting or nursing | observational and rct mix | none given | new card; New Parent preset in `assets/content/presets.json` |
| Folate from three months before conception | rct (public health guidance) | none given | new card |

## Nose care (generic wording, no brands)

| Idea | Tag | Source as cited | Target |
|---|---|---|---|
| Blow gently, one side at a time, mouth open | observational | Gwaltney 2000 imaging study | new card in `assets/content/interventions.json` |
| Saline spray plus a thin bedtime emollient for dry-climate nosebleeds | traditional | none given | new card |
| After saline, wait 30 to 60 seconds before clearing | traditional (the note calls it a heuristic) | none given | the same new card, details |
| Heavy long-term use of thick petrolatum has rare case reports of a lung problem; prefer a water-based gel for daily use (**clinician review**) | observational (case reports) | case reports, unnamed | the same new card, safety |
| Nosebleed first aid: sit up, lean forward, pinch the soft part for 10 to 15 minutes (**clinician review**) | mechanistic (clinical guidance) | none given | the same new card, safety |
| Irrigation: ask a clinician first after nasal surgery; the existing water-safety text already matches the note | mechanistic | none given | `nasal-saline-irrigation` safety |
| An external nasal dilator strip for night breathing; effect size not stated, so a weak idea | mechanistic | none given | new card; generic wording only |

## Air, light and hydration (added November 2026)

| Idea | Tag | Source as cited | Target |
|---|---|---|---|
| Two-stage bedroom air: a particle filter for dust and a separate gas stage with a thick bed of activated carbon and an inline fan. Particle filters do nothing for gases, and the thin carbon sheet in many purifiers does little | mechanistic | a source note citing grow-tent practice; no study given | `air-filtration` details |
| Read a CO2 monitor as a proxy for ventilation, not as a poison meter: the cognitive studies at about 1,000 ppm have replicated poorly. Choose a monitor that states NDIR; low-cost "eCO2" units estimate | mechanistic | Satish 2012 and Allen 2016, as cited in a source note | `air-filtration` details |
| Water temperature does not matter; use what you will drink daily. Very hot drinks (above about 65 degrees C) are the one exception | observational | IARC monograph on very hot beverages, as cited in a source note | `hydrate-on-waking` details |
| Window light is a dose argument, not a wavelength argument: outdoor daylight is roughly 10,000 to 100,000 lux, indoors near a window a few hundred to a couple of thousand | mechanistic | none given | `morning-sunlight` details |

## Measurement (added November 2026)

| Idea | Tag | Source as cited | Target |
|---|---|---|---|
| Add ApoB to the lipid panel; test Lp(a) once, since it is largely genetic and does not change (**clinician review**) | observational | none given | `annual-bloodwork` details |

## Safety fields to fill (added November 2026)

The cards below have an empty `safety` field today. Wording stays calm and general.

| Idea | Tag | Source as cited | Target |
|---|---|---|---|
| Move the dog caution into `safety`: xylitol is toxic to dogs, so keep gum and mints out of their reach | mechanistic (veterinary guidance) | none given | `xylitol-gum` safety (the line now sits in details) |
| Phosphatidylserine: check with a clinician first if you take a blood thinner (**clinician review**) | mechanistic | none given | `phosphatidylserine` safety |
| Phosphatidylserine and creatine: there is too little human data on supplemental doses while breastfeeding, so ask a clinician first (**clinician review**) | mechanistic | a source note citing the NIH LactMed database | `phosphatidylserine` and `creatine` safety |
| Confirm that nasal breathing is easy before relying on mouth tape; a 2025 systematic review found weak evidence for taping (**clinician review**) | observational | a 2025 systematic review, unnamed | `nasal-breathing` safety |
| In pressurized nasal devices, fill only with distilled or previously boiled water. The existing irrigation text already says this; the idea is to carry the same line to any device that pushes water deep into the sinuses | mechanistic | none given | `nasal-saline-irrigation` safety |

## Numbers that need a ruling (added November 2026)

Two cards disagree with a newer source note. The reviewer who builds the card decides.

- **Ruck load.** The `rucking` card gives no starting number. The note suggests starting light, adding a little weight after every 4 to 6 comfortable weeks, and settling at about 20 to 25 percent of bodyweight, with injury risk rising faster than benefit above that. The note's own start weight is a fixed figure that does not scale with the person, so a percentage start is the likelier fit. Tag: traditional. Source: none given.
- **Static stretch before lifting.** The `avoid-static-stretch-preworkout` card says force drops 5 to 10 percent. The note says only holds of 60 seconds or longer measurably cut force, and only by a few percent; holds under 30 seconds make no meaningful difference. A dynamic warm-up first is right either way. Tag: rct. Source: meta-analyses, as cited in a source note.

## Timing and the New Parent preset (added November 2026)

| Idea | Tag | Source as cited | Target |
|---|---|---|---|
| Take phosphatidylserine with a meal that has some fat; if dinner runs late, take it with the last substantial meal and keep that meal light | mechanistic | none given | `phosphatidylserine` details |
| Finish the evening meal 2 to 3 hours before bed | mechanistic | none given | `phosphatidylserine` details or a dinner-timing card |
| Cyclic sighing for five minutes a day beat mindfulness meditation for mood in one randomized trial. Credit the sigh reflex to the lab that described it (Feldman), not to the trial's popularizer | rct | Balban and colleagues 2023, as cited in a source note | `physiological-sigh` details |
| A breastfeeding variant of the New Parent preset: keep vitamin D, omega-3 (DHA) and magnesium; leave out creatine, phosphatidylserine and supplemental glycine until a clinician approves (**clinician review**) | mechanistic | a source note citing LactMed; no study given | New Parent preset in `assets/content/presets.json`; see [open product questions](product-questions.md) |

Already covered by shipped cards (checked November 2026): the sauna, cold-finish and creatine calibrations, the 200 mg phosphatidylserine start, and the retinoid caution.
