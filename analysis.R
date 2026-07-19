# =============================================================================
# Open Access Publication Speed: A Bibliometric Analysis of DOAJ-Indexed
# Journals

# Input:  data/raw/doaj_journals_raw.csv
# Output: data/processed/*.csv, figures/*.png, report/stats_results.txt

required_packages <- c(
  "dplyr", "readr", "stringr", "tidyr", "purrr",
  "forcats", "ggplot2", "rstatix", "coin"
)

library(dplyr)
library(readr)
library(stringr)
library(tidyr)
library(purrr)
library(forcats)
library(ggplot2)
library(rstatix)

`%||%` <- function(a, b) if (is.null(a) || is.na(a)) b else a

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("figures", recursive = TRUE, showWarnings = FALSE)
dir.create("report", recursive = TRUE, showWarnings = FALSE)

# =============================================================================
# PART 1: CLEAN
# =============================================================================

raw <- read_csv("data/raw/doaj_journals_raw.csv", show_col_types = FALSE)
cat("Raw rows read:", nrow(raw), "\n")

df <- raw %>%
  select(
    journal_title    = `Journal title`,
    issn_print       = `Journal ISSN (print version)`,
    issn_online      = `Journal EISSN (online version)`,
    publisher        = Publisher,
    country          = `Country of publisher`,
    subjects_raw     = Subjects,
    turnaround_weeks = `Average number of weeks between article submission and publication`,
    apc              = APC,
    apc_amount       = `APC amount`,
    review_process   = `Review process`,
    n_articles       = `Number of Article Records`
  )

# Deduplicate on ISSN (fall back to title if both ISSNs are missing)
before_dedup <- nrow(df)
df <- df %>%
  mutate(issn_key = coalesce(issn_print, issn_online, journal_title)) %>%
  distinct(issn_key, .keep_all = TRUE) %>%
  select(-issn_key)
cat("Removed", before_dedup - nrow(df), "duplicate rows on ISSN/title\n")

# Parse top-level discipline from Subjects.
# DOAJ separates MULTIPLE subject classifications with " | ", e.g.:
#   "Medicine: Internal medicine: Infectious diseases | Medicine: Medicine (General)"
# Within one classification, nested LCC levels are ":"-separated. We take the
# FIRST pipe-separated classification, then its top-level category (before
# the first colon), as the journal's primary discipline. Multidisciplinary
# journals get assigned to whichever classification DOAJ listed first --
# documented as a limitation in REPORT.md.
df <- df %>%
  mutate(
    discipline = subjects_raw %>%
      str_split(fixed(" | "), n = 2) %>%
      map_chr(1) %>%
      str_split(":", n = 2) %>%
      map_chr(1) %>%
      str_trim()
  )

# Clean numeric / categorical fields
df <- df %>%
  mutate(
    turnaround_weeks = as.numeric(turnaround_weeks),
    apc = case_when(
      apc %in% c("Yes", "yes", "YES") ~ "Yes",
      apc %in% c("No", "no", "NO")    ~ "No",
      TRUE ~ NA_character_
    ),
    apc_amount = suppressWarnings(as.numeric(apc_amount)),
    n_articles = suppressWarnings(as.numeric(n_articles)),
    country    = str_trim(country)
  )

# Simplify review_process to the most rigorous method present, in priority order
priority <- c(
  "Double anonymous peer review",
  "Anonymous peer review",
  "Open peer review",
  "Peer review",
  "Editorial review"
)

df <- df %>%
  rowwise() %>%
  mutate(
    review_primary = {
      hits <- priority[str_detect(review_process %||% "", fixed(priority))]
      if (length(hits) == 0) NA_character_ else hits[1]
    }
  ) %>%
  ungroup()

before_drop <- nrow(df)
df <- df %>% filter(!is.na(turnaround_weeks), !is.na(discipline))
cat("Dropped", before_drop - nrow(df), "rows missing turnaround_weeks/discipline\n")

# Flag extreme values -- self-reported field, outliers are
# part of RQ5, not noise to discard
df <- df %>% mutate(turnaround_extreme = turnaround_weeks > 104) # > 2 years

cat("\nFinal clean dataset:", nrow(df), "rows,", ncol(df), "columns\n")
cat("Turnaround summary:\n")
print(summary(df$turnaround_weeks))

write_csv(df, "data/processed/doaj_journals_clean.csv")
cat("Wrote data/processed/doaj_journals_clean.csv\n\n")

# =============================================================================
# PART 2: EXPLORATORY ANALYSIS & FIGURES
# =============================================================================

theme_set(theme_minimal(base_size = 12))

# --- Fig 1: overall distribution ---
p1 <- ggplot(df, aes(x = turnaround_weeks)) +
  geom_histogram(binwidth = 4, fill = "#2c7fb8", color = "white") +
  geom_vline(aes(xintercept = median(turnaround_weeks, na.rm = TRUE)),
             linetype = "dashed", color = "firebrick") +
  labs(
    title = "Distribution of self-reported submission-to-publication time",
    subtitle = paste0("n = ", nrow(df), " DOAJ-indexed journals; dashed line = median (",
                       median(df$turnaround_weeks, na.rm = TRUE), " weeks)"),
    x = "Weeks from submission to publication", y = "Number of journals"
  )
ggsave("figures/01_turnaround_distribution.png", p1, width = 8, height = 5, dpi = 150)

# --- Fig 2: by discipline (top 10 by journal count) ---
top_disciplines <- df %>% count(discipline, sort = TRUE) %>% slice_head(n = 10) %>% pull(discipline)

p2 <- df %>%
  filter(discipline %in% top_disciplines) %>%
  mutate(discipline = fct_reorder(discipline, turnaround_weeks, .fun = median)) %>%
  ggplot(aes(x = discipline, y = turnaround_weeks)) +
  geom_boxplot(fill = "#41b6c4", outlier.alpha = 0.3) +
  coord_flip() +
  labs(title = "Turnaround time by discipline (top 10 by journal count)",
       x = NULL, y = "Weeks from submission to publication")
ggsave("figures/02_turnaround_by_discipline.png", p2, width = 8, height = 6, dpi = 150)

# --- Fig 3: by publisher country (top 10 by journal count) ---
top_countries <- df %>% count(country, sort = TRUE) %>% slice_head(n = 10) %>% pull(country)

p3 <- df %>%
  filter(country %in% top_countries) %>%
  mutate(country = fct_reorder(country, turnaround_weeks, .fun = median)) %>%
  ggplot(aes(x = country, y = turnaround_weeks)) +
  geom_boxplot(fill = "#a1dab4", outlier.alpha = 0.3) +
  coord_flip() +
  labs(title = "Turnaround time by publisher country (top 10 by journal count)",
       x = NULL, y = "Weeks from submission to publication")
ggsave("figures/03_turnaround_by_country.png", p3, width = 8, height = 6, dpi = 150)

# --- Fig 4: by APC status ---
p4 <- df %>%
  filter(!is.na(apc)) %>%
  ggplot(aes(x = apc, y = turnaround_weeks, fill = apc)) +
  geom_boxplot(alpha = 0.7) +
  scale_fill_manual(values = c("No" = "#bdbdbd", "Yes" = "#2c7fb8")) +
  labs(title = "Turnaround time by APC (Article Processing Charge) status",
       x = "Journal charges an APC", y = "Weeks from submission to publication") +
  theme(legend.position = "none")
ggsave("figures/04_turnaround_by_apc.png", p4, width = 6, height = 5, dpi = 150)

# --- Fig 5: by review process type ---
p5 <- df %>%
  filter(!is.na(review_primary)) %>%
  mutate(review_primary = fct_reorder(review_primary, turnaround_weeks, .fun = median)) %>%
  ggplot(aes(x = review_primary, y = turnaround_weeks)) +
  geom_boxplot(fill = "#fdae61", outlier.alpha = 0.3) +
  coord_flip() +
  labs(title = "Turnaround time by review process type",
       x = NULL, y = "Weeks from submission to publication")
ggsave("figures/05_turnaround_by_review_process.png", p5, width = 8, height = 5, dpi = 150)

# --- Summary table by discipline (n >= 30) ---
summary_by_discipline <- df %>%
  group_by(discipline) %>%
  summarise(n = n(), median_weeks = median(turnaround_weeks, na.rm = TRUE),
            mean_weeks = mean(turnaround_weeks, na.rm = TRUE),
            sd_weeks = sd(turnaround_weeks, na.rm = TRUE)) %>%
  filter(n >= 30) %>%
  arrange(desc(median_weeks))
write_csv(summary_by_discipline, "data/processed/summary_by_discipline.csv")

cat("EDA complete. Figures written to figures/\n\n")

# =============================================================================
# PART 3: STATISTICAL TESTS
# =============================================================================
# Turnaround is heavily right-skewed, so we use non-parametric tests
# (Kruskal-Wallis / Wilcoxon) rather than ANOVA/t-tests, and report effect
# sizes alongside p-values. With n > 20,000, p-values alone are close to meaningless

sink("report/stats_results.txt", split = TRUE)

cat("=============================================================\n")
cat("RQ1: Does turnaround time differ by discipline?\n")
cat("=============================================================\n")

top_disciplines_stat <- df %>% count(discipline, sort = TRUE) %>% filter(n >= 30) %>% pull(discipline)
df_disc <- df %>% filter(discipline %in% top_disciplines_stat)

print(df_disc %>% kruskal_test(turnaround_weeks ~ discipline))
cat("\nEffect size (epsilon-squared):\n")
print(df_disc %>% kruskal_effsize(turnaround_weeks ~ discipline))

cat("\nPost-hoc pairwise Wilcoxon (BH-adjusted), pairs with |median diff| >= 5 weeks:\n")
med_by_disc <- df_disc %>% group_by(discipline) %>% summarise(med = median(turnaround_weeks))
posthoc_disc <- df_disc %>%
  wilcox_test(turnaround_weeks ~ discipline, p.adjust.method = "BH") %>%
  left_join(med_by_disc, by = c("group1" = "discipline")) %>% rename(med1 = med) %>%
  left_join(med_by_disc, by = c("group2" = "discipline")) %>% rename(med2 = med) %>%
  mutate(med_diff = abs(med1 - med2)) %>%
  filter(med_diff >= 5) %>%
  arrange(desc(med_diff))
print(posthoc_disc %>% select(group1, group2, med1, med2, med_diff, p.adj, p.adj.signif))

cat("\n\n=============================================================\n")
cat("RQ2: Does turnaround time differ by publisher country?\n")
cat("=============================================================\n")

top_countries_stat <- df %>% count(country, sort = TRUE) %>% filter(n >= 100) %>% pull(country)
df_country <- df %>% filter(country %in% top_countries_stat)

print(df_country %>% kruskal_test(turnaround_weeks ~ country))
cat("\nEffect size (epsilon-squared):\n")
print(df_country %>% kruskal_effsize(turnaround_weeks ~ country))

cat("\nMedian turnaround by country (n >= 100), slowest to fastest:\n")
print(df_country %>% group_by(country) %>%
        summarise(n = n(), median_weeks = median(turnaround_weeks), mean_weeks = mean(turnaround_weeks)) %>%
        arrange(desc(median_weeks)))

cat("\n\n=============================================================\n")
cat("RQ3: Is APC status associated with turnaround time?\n")
cat("=============================================================\n")

df_apc <- df %>% filter(!is.na(apc))
print(df_apc %>% wilcox_test(turnaround_weeks ~ apc))
cat("\nEffect size (rank-biserial r):\n")
print(df_apc %>% wilcox_effsize(turnaround_weeks ~ apc))
cat("\nMedian/mean by APC status:\n")
print(df_apc %>% group_by(apc) %>%
        summarise(n = n(), median_weeks = median(turnaround_weeks), mean_weeks = mean(turnaround_weeks)))

cat("\n\n=============================================================\n")
cat("RQ4: Does review process type relate to turnaround time?\n")
cat("=============================================================\n")

df_review <- df %>% filter(!is.na(review_primary))
print(df_review %>% kruskal_test(turnaround_weeks ~ review_primary))
cat("\nEffect size (epsilon-squared):\n")
print(df_review %>% kruskal_effsize(turnaround_weeks ~ review_primary))
cat("\nMedian/mean by review process type:\n")
print(df_review %>% group_by(review_primary) %>%
        summarise(n = n(), median_weeks = median(turnaround_weeks), mean_weeks = mean(turnaround_weeks)) %>%
        arrange(desc(median_weeks)))

cat("\n\n=============================================================\n")
cat("Follow-up: APC effect within each discipline (confound check)\n")
cat("=============================================================\n")

apc_by_discipline <- df_disc %>%
  filter(!is.na(apc)) %>%
  group_by(discipline, apc) %>%
  summarise(n = n(), median_weeks = median(turnaround_weeks), .groups = "drop") %>%
  pivot_wider(names_from = apc, values_from = c(n, median_weeks)) %>%
  mutate(apc_median_diff = median_weeks_Yes - median_weeks_No) %>%
  arrange(desc(abs(apc_median_diff)))
print(apc_by_discipline)

sink()

# =============================================================================
# PART 4: OUTLIER ANALYSIS (RQ5)
# =============================================================================
# Outliers flagged WITHIN each discipline (a journal's 90th percentile is
# relative to its own field)

disc_counts <- df %>% count(discipline) %>% filter(n >= 30)

outliers <- df %>%
  filter(discipline %in% disc_counts$discipline) %>%
  group_by(discipline) %>%
  mutate(
    p90_in_discipline = quantile(turnaround_weeks, 0.90, na.rm = TRUE),
    is_slow_outlier = turnaround_weeks >= p90_in_discipline
  ) %>%
  ungroup()

slow_outliers <- outliers %>%
  filter(is_slow_outlier) %>%
  select(journal_title, publisher, country, discipline, turnaround_weeks,
         p90_in_discipline, apc, review_primary) %>%
  arrange(desc(turnaround_weeks))

cat("Flagged", nrow(slow_outliers), "journals as slow outliers (>=90th pct within their discipline)\n")
write_csv(slow_outliers, "data/processed/slow_outliers.csv")

# Country over/under-representation in the slow tail vs. overall share
country_share_all <- df %>%
  filter(discipline %in% disc_counts$discipline) %>%
  count(country, name = "n_total") %>%
  mutate(share_total = n_total / sum(n_total))

country_share_outliers <- slow_outliers %>%
  count(country, name = "n_outlier") %>%
  mutate(share_outlier = n_outlier / sum(n_outlier))

country_comparison <- country_share_all %>%
  inner_join(country_share_outliers, by = "country") %>%
  filter(n_total >= 50) %>%
  mutate(over_representation = share_outlier / share_total) %>%
  arrange(desc(over_representation))

cat("\nCountries most OVER-represented in the slow tail (n_total >= 50):\n")
print(head(country_comparison, 10))
cat("\nCountries most UNDER-represented in the slow tail (n_total >= 50):\n")
print(tail(country_comparison, 10))

write_csv(country_comparison, "data/processed/outlier_country_comparison.csv")

p6 <- country_comparison %>%
  filter(n_total >= 100) %>%
  mutate(country = fct_reorder(country, over_representation)) %>%
  ggplot(aes(x = country, y = over_representation)) +
  geom_col(fill = "#d95f0e") +
  geom_hline(yintercept = 1, linetype = "dashed", color = "gray30") +
  coord_flip() +
  labs(
    title = "Over-representation in the slow-turnaround tail, by publisher country",
    subtitle = "Ratio > 1 = country appears in the slow tail more than its overall share would predict",
    x = NULL, y = "Share of slow-tail journals / share of all journals"
  )
ggsave("figures/06_outlier_country_overrepresentation.png", p6, width = 8, height = 6, dpi = 150)

cat("\nOutlier analysis complete.\n")
cat("- Slow outlier list: data/processed/slow_outliers.csv\n")
cat("- Country comparison: data/processed/outlier_country_comparison.csv\n")
cat("- Figure: figures/06_outlier_country_overrepresentation.png\n")
cat("\n=== analysis.R finished ===\n")
