# Workshop v2 — outline and first two drafted sections

**Status: DRAFT for review.** Nothing here is final until it's agreed; once the
content is approved section by section, it becomes the new `docs/workshop.html`
(with real collapsible dropdowns) and this file is retired.

Ground rules agreed for the rebuild:

- **Self-contained fake data.** No Fort Severn, no project results — clean
  numbers chosen so every hand calculation works out in round figures.
- **kg C/m² everywhere.** (1 kg C/m² = 10 Mg C/ha, said once, then dropped.)
- **The honest-Bayes framing.** Neither cores nor models are 100% accurate;
  combining them, weighted by confidence, is the best available approximation
  of the truth. The prior makes limited sampling go further, and the mapped
  uncertainty tells you where to sample next year.
- **Frequentist first, briefly, in each analysis section.** With cores alone,
  classical statistics already gives an estimate and a precision — that is the
  baseline. Bayes is the different way of thinking that lets *other* information
  (prior maps, previous studies) join in: the true value lies underneath, and
  every dataset is a partial, imperfect view of it.
- **Every section follows the same pattern:**
  1. **Concept** — plain language, no formulas
  2. **The math** — the equations, symbols defined
  3. **▸ A. By hand** — dropdown: a handful of numbers and a calculator
  4. **▸ B. In R, from scratch** — dropdown: ~10 lines of base R reproducing
     the hand numbers exactly
  5. **Where the workflow does this** — file, function, runner script, output

---

## Proposed section list

| # | Section | Maps to code |
|---|---|---|
| 1 | What we're estimating, and why depths must match | — |
| 2 | Harmonizing cores to standard depths | `R/step02` |
| 3 | Extending a short core downward (extrapolation) | `R/step02` |
| 4 | What a prior map gives you: an estimate *and* a doubt | `R/step01`, step-0 tables |
| 5 | Cores alone: the frequentist estimate | (inside Tier 0) |
| 6 | The Bayesian update: combining two imperfect estimates | `R/step09`, `tier0_area_update()` |
| 7 | Does the map agree with your cores? (residuals, calibration) | `R/step04`, `tier1_calibration()` |
| 8 | From one number to strata to a map: the tier ladder | `R/step14_*` |
| 9 | The update at every pixel | `R/step10` |
| 10 | Is the map good enough to manage by? (CV, precision targets) | `R/step15` |
| 11 | Where to sample next year | `R/step16` |

---

# SECTION 2 (draft) — Harmonizing cores to standard depths

## Concept

Every survey slices its cores differently. One crew cuts at 0–10, 10–25,
25–40 cm; a national soil map reports 0–15, 15–30, 30–50; last decade's study
used 0–20. None of these are wrong — but none of them can be compared until
they're expressed on the *same* depth intervals. Harmonization is that
translation step, and it comes first because everything downstream — comparing
your cores to a prior map, to each other, to another community's cores —
assumes the depths line up.

The rule that keeps it honest: **carbon is a mass, and translation must not
create or destroy it.** If a measured layer overlaps a target interval, it
hands over carbon *in proportion to how much of it falls inside* — nothing
more, nothing less. (An alternative you'll meet in the literature is fitting a
smooth curve through the profile; done casually, that can invent or lose mass.
The overlap rule can't.)

## The math

A measured layer holds stock $S$ (kg C/m²) spread over its thickness $t$ (cm).
The part of it lying inside a target interval contributes:

$$\text{contribution} = S \times \frac{\text{overlap}}{t}$$

and the target interval's stock is the sum of contributions from every layer
that touches it:

$$S_{\text{target}} = \sum_{\text{layers}} S_i \times \frac{\text{overlap}_i}{t_i}$$

where *overlap* is the depth range shared by layer and target (0 if they don't
touch). That's the whole method.

## ▸ A. By hand

<details><summary>One core, one target interval, a calculator</summary>

A core was cut into three layers. The lab work is done and each layer's stock
is known:

| Layer (cm) | Thickness | Stock (kg C/m²) |
|---|---|---|
| 0 – 10 | 10 | 2.4 |
| 10 – 25 | 15 | 3.0 |
| 25 – 40 | 15 | 1.8 |

**Target: 0–15 cm.**

- Layer 0–10 lies entirely inside → contributes all of itself: **2.4**
- Layer 10–25 overlaps from 10 to 15 → 5 of its 15 cm →
  3.0 × 5/15 = **1.0**
- Layer 25–40 doesn't touch 0–15 → **0**

$$S_{0\text{–}15} = 2.4 + 1.0 = \mathbf{3.4 \text{ kg C/m}^2}$$

**Target: 15–30 cm** (check yourself):

- Layer 10–25 overlaps 15–25 → 10/15 → 3.0 × 10/15 = 2.0
- Layer 25–40 overlaps 25–30 → 5/15 → 1.8 × 5/15 = 0.6

$$S_{15\text{–}30} = 2.0 + 0.6 = \mathbf{2.6 \text{ kg C/m}^2}$$

Sanity check: the whole core holds 2.4 + 3.0 + 1.8 = 7.2 kg C/m². Our two
targets took 3.4 + 2.6 = 6.0, and the untouched remainder (30–40 cm) holds
1.8 × 10/15 = 1.2. Total 7.2 — no carbon created, none lost.

</details>

## ▸ B. In R, from scratch

<details><summary>The same numbers in ~8 lines of base R</summary>

```r
layers <- data.frame(
  top    = c(0, 10, 25),
  bottom = c(10, 25, 40),
  stock  = c(2.4, 3.0, 1.8)      # kg C/m2 per layer
)

target <- c(0, 15)

# how many cm of each layer fall inside the target?
# pmin/pmax work element-wise: for each layer, the shared range is
# from max(layer top, target top) to min(layer bottom, target bottom)
overlap <- pmax(0, pmin(layers$bottom, target[2]) - pmax(layers$top, target[1]))

sum(layers$stock * overlap / (layers$bottom - layers$top))
#> 3.4
```

Change `target` to `c(15, 30)` and you get 2.6 — the same numbers as by hand.
Base R only: `pmin()`/`pmax()` are element-wise minimum/maximum, and the last
line is exactly the formula from the math section.

</details>

## Where the workflow does this

`harmonize_core_depths()` in **`R/step02_harmonize_depths.R`** is the loop
version of the eight lines above: same overlap rule, applied to every core and
every target interval (0–15, 15–30, 30–50, 50–100 by default), plus the
book-keeping a real dataset needs — `coverage_frac` records how much of each
target interval a core actually reached, and intensive properties
(concentration, bulk density) come back as overlap-weighted means rather than
sums.

Run it with **`scripts/run_02_harmonize_depths.R`** → output
`outputs/soil_cores_harmonized.csv`. The same arithmetic also lives in the
field workbook (sheet 3, bands 5), so the spreadsheet and R can be checked
against each other line by line — if they ever disagree, the spreadsheet wins
and the code has a bug.

---

# SECTION 6 (draft) — The Bayesian update: combining two imperfect estimates

## Concept

You now hold two answers to the same question — *how much carbon per square
metre, on average, across the area?*

- A **prior map** says 15 kg C/m², but it was built from samples far away and
  admits an uncertainty of ± 3.
- Your **cores** say 17 kg C/m², but there are only sixteen of them, and
  sixteen samples of a patchy landscape carry their own uncertainty: ± 2.

Neither is the truth. The truth is a single number lying underneath, and each
estimate is a partial, imperfect view of it. Throwing either away wastes
information; averaging them 50/50 ignores that one is more trustworthy than
the other. The Bayesian update does the only sensible third thing: **it
averages them weighted by confidence** — the more certain voice counts for
more — and, crucially, it also tells you how confident to be in the result.

That last part is the payoff. The combined estimate is *more precise than
either input*, because two independent lines of evidence corroborating each
other genuinely is stronger evidence. This is how a prior map makes a small
field campaign go further — and next season, this year's answer becomes the
prior you update with new cores.

## The math

Confidence is written as *precision* — one over the variance. An estimate
$\mu \pm \sigma$ has precision $1/\sigma^2$: small σ, big precision, loud
voice.

$$\frac{1}{\sigma_{\text{post}}^2} = \frac{1}{\sigma_{\text{prior}}^2} + \frac{1}{\sigma_{\text{cores}}^2} \qquad\text{(precisions add)}$$

$$\mu_{\text{post}} = \sigma_{\text{post}}^2 \left( \frac{\mu_{\text{prior}}}{\sigma_{\text{prior}}^2} + \frac{\mu_{\text{cores}}}{\sigma_{\text{cores}}^2} \right) \qquad\text{(precision-weighted average)}$$

Two things to notice before doing it by hand. Because precisions *add*, the
posterior is always more precise than either input. And whichever input has
the smaller σ pulls the answer toward itself — the update can't be bullied by
a loud but vague prior.

*(Where did "17 ± 2" come from? That is plain frequentist statistics: sixteen
cores with mean 17 and standard deviation 8 give a standard error of
$8/\sqrt{16} = 2$. Cores-alone-plus-standard-error IS the classical estimate —
if you stopped here you'd report 17 ± 2 and be done. The Bayesian step is what
lets the map join in.)*

## ▸ A. By hand

<details><summary>Five numbers and a calculator</summary>

$$\text{prior } 15 \pm 3 \qquad \text{cores } 17 \pm 2 \quad(\text{kg C/m}^2)$$

**1. Precisions:**
$$1/3^2 = 1/9 = 0.111 \qquad 1/2^2 = 1/4 = 0.250$$

**2. Add them, invert for the posterior variance:**
$$\sigma_{\text{post}}^2 = \frac{1}{0.111 + 0.250} = \frac{1}{0.361} = 2.77
\qquad \sigma_{\text{post}} = \sqrt{2.77} = 1.66$$

**3. Weighted mean:**
$$\mu_{\text{post}} = 2.77 \times (15 \times 0.111 + 17 \times 0.250)
= 2.77 \times 5.917 = 16.4$$

$$\boxed{\;16.4 \pm 1.7 \text{ kg C/m}^2\;}$$

Read it back: the answer sits closer to the cores (they were more precise —
weight 0.250 vs 0.111, i.e. 69% vs 31%), and the uncertainty (1.66) is smaller
than *both* inputs. Relative uncertainty: 1.66/16.4 ≈ **10%** — against 20%
for the prior alone and 12% for the cores alone.

**The efficiency line, made concrete:** to reach ± 1.66 with cores alone you'd
need $n = (8/1.66)^2 \approx 23$ cores. Sixteen cores plus the free map gave
the same precision as twenty-three cores without it.

</details>

## ▸ B. In R, from scratch

<details><summary>The same numbers in ~7 lines of base R</summary>

```r
prior_mean <- 15;  prior_sd <- 3     # the map's story
cores      <- 17;  cores_sd <- 2     # 16 cores: mean 17, SD 8 -> SE = 8/sqrt(16) = 2

prior_precision <- 1 / prior_sd^2                 # 0.111
cores_precision <- 1 / cores_sd^2                 # 0.250

post_var  <- 1 / (prior_precision + cores_precision)
post_mean <- post_var * (prior_mean * prior_precision + cores * cores_precision)

c(mean = post_mean, sd = sqrt(post_var))
#>      mean        sd
#> 16.384615  1.664101
```

No packages — the update is four arithmetic operations. Everything else in the
workflow is book-keeping around these lines.

</details>

## Where the workflow does this

- **`R/step09_bayesian_update.R` → `bayesian_update_normal()`** — exactly the
  seven lines above, plus one safeguard: where the prior map has no value
  (open water, a different ecosystem), its precision is set to 0 so it simply
  goes silent there rather than poisoning the result.
- **`R/step14_tier_ladder.R` → `tier0_area_update()`** — the "Tier 0" analysis:
  computes your cores' mean and standard error (the frequentist part), then
  calls `bayesian_update_normal()` (the Bayesian part), and reports the
  posterior alongside the weight the prior actually earned. Run via
  **`scripts/run_14_model_ladder.R`** → `outputs/tier0_area_update.rds`.
- **`R/step10_bayesian_update_raster.R`** — the same equations applied at
  every pixel of a map instead of once for the area (section 9).

---

*Next sections to draft once these two are approved: 4 (what a prior map gives
you), 5 (cores alone — expanded), 7 (calibration/residuals), 8 (tier ladder).*
