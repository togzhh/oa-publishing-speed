# How Fast Is Open Access? A Bibliometric Analysis of Turnaround Times Across DOAJ-Indexed Journals

## Motivation

Scholarly publishing timelines are a persistent point of friction for researchers, yet
large-scale, cross-disciplinary data on how long open-access journals actually take is
rarely aggregated in one place. This project uses the Directory of Open Access Journals
(DOAJ) full registry export to ask: **does publication turnaround time vary systematically
by discipline, publisher country, APC status, or review process — and where are the
outliers?**

## Research Questions

1. Does turnaround time (submission → publication) differ by discipline?
2. Does it differ by publisher country?
3. Is charging an Article Processing Charge (APC) associated with faster turnaround?
4. Does review process type (single-anonymous / double-anonymous / open) correlate with speed?
5. Which publishers/disciplines sit in the slow tail (>90th percentile within their own
   discipline), and is there a pattern?

## Data

- **Source**: DOAJ journal metadata CSV export (`doaj_journalcsv_20260613_2320_utf8.csv`),
  publicly downloadable from https://doaj.org
- **Scope**: 23,054 journals, 52 fields; 23,053 remain after deduplication on ISSN
- **Key field**: `Average number of weeks between article submission and publication`
  (fully populated, no missing values)

### Known limitations

- The turnaround figure is **self-reported by the journal to DOAJ**, not independently
  measured from article-level timestamps — treat it as a claimed value, not ground truth.
- It's a **single combined metric** (submission→publication). It cannot be split into
  submission→acceptance and acceptance→publication without article-level data. Some
  publishers deposit `received`/`accepted` history dates into Crossref (via JATS `<history>`
  metadata), but coverage is inconsistent across publishers — a viable extension, not part
  of this analysis.
- Cross-sectional snapshot, not longitudinal.
- `discipline` is derived by taking the *first* pipe-separated subject classification DOAJ
  lists for a journal and its top-level LCC category. Multidisciplinary journals are
  therefore assigned to only one of their categories (whichever DOAJ lists first) — a
  simplification, not a validated classification.

## Methodology

1. **Clean** (`analysis.R`, Part 1): dedupe by ISSN, parse `Subjects` into a top-level
   discipline, standardize APC/country/review-process fields, flag (not remove) extreme
   turnaround values (>104 weeks).
2. **Explore** (Part 2): distributions and boxplots by discipline, country, APC, and review
   process.
3. **Test** (Part 3): turnaround is heavily right-skewed, so all group comparisons use
   non-parametric tests — Kruskal-Wallis across >2 groups, Wilcoxon rank-sum for the binary
   APC comparison — with effect sizes (epsilon-squared / rank-biserial r) reported alongside
   p-values. With n > 20,000, p-values alone are close to meaningless; effect size is what
   tells you whether a difference actually matters.
4. **Outliers** (Part 4): flagged within each discipline (a journal's 90th percentile is
   relative to its own field), since a global cutoff would just re-surface the discipline
   effect rather than genuine outliers.

## Results

**n = 23,053 journals after cleaning.** Overall turnaround: median 14 weeks, mean 17.3
weeks, range 1–100 weeks.

| RQ | Test | Effect size | 
|---|---|---|
| Discipline | Kruskal-Wallis, χ²=377, df=18, p=5.8×10⁻⁶⁹ | ε²=0.016 (small) | 
| Country | Kruskal-Wallis, χ²=2967, df=40, p<10⁻³⁰⁰ | ε²=0.139 (moderate) | 
| APC status | Wilcoxon, p=3.2×10⁻³³ | r=0.079 (small) | 
| Review type | Kruskal-Wallis, χ²=123, df=4, p=1.2×10⁻²⁵ | ε²=0.005 (small) | 

- **By discipline**: History-related fields (median 20 weeks) are slowest; Law and Military
  Science (median 12 weeks) are fastest. Differences are statistically significant but small
  in magnitude — most disciplines cluster within a few weeks of each other.
- **By country** (n≥100 journals): Norway (median 25 wks) and France (24 wks) are slowest
  among high-volume countries; this is the strongest predictor in the dataset.
- **By APC**: journals charging an APC report faster turnaround (median 13 vs. 15 weeks).
  This effect is *not* simply a discipline confound — checked directly in `analysis.R` Part
  3 (APC-by-discipline breakdown) — though it flips direction in a few disciplines (e.g.
  Medicine, Science, Technology, Agriculture: non-APC is *faster* there), so it isn't a
  uniform effect across fields.
- **By review process**: essentially negligible (ε²=0.005) — not a meaningful predictor on
  its own.
- **Outlier pattern (RQ5)**: 2,469 journals flagged as slow outliers (≥90th percentile
  within their own discipline). Countries **over-represented** in the slow tail relative to
  their overall share: France (2.8×), Belgium (2.7×), Norway (2.4×), Canada (2.4×), China
  (2.4×). Countries **under-represented**: Egypt (0.03×), Indonesia (0.09×), Bulgaria
  (0.09×), Malaysia (0.16×), Bosnia and Herzegovina (0.17×). This runs counter to a naive
  "higher-volume/lower-resource publishing regions are slower" prior — the opposite pattern
  holds here, and is worth building the discussion section around.

## Repository Structure

```
├── data/
│   ├── raw/                          # untouched original DOAJ export
│   └── processed/                    # cleaned + derived analysis outputs
├── figures/                          # 6 exported plots (PNG)
├── report/
│   └── stats_results.txt             # full printed output of all statistical tests
├── analysis.R                        # full pipeline: clean -> EDA -> stats -> outliers
├── oa-publishing-speed.Rproj         # open this in RStudio -- sets working dir automatically
├── README.md                         # this file
└── LICENSE
```

