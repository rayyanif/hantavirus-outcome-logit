# Hantavirus outcome prediction with logistic regression

[Read in Bahasa Indonesia](README.id.md)

This analysis uses logistic regression to estimate recovery probability for a binary hantavirus outcome. It evaluates how the classification cutoff changes the number of missed deaths and false alerts.

[All 26 figures (PDF)](visualisasi_hantavirus.pdf) · [Individual figures (PNG ZIP)](visualisasi_hantavirus_png.zip)

## Data and preprocessing

The analysis uses [`hantavirus_clinical.xlsx`](hantavirus_clinical.xlsx). The data source is [Hantavirus (Andes Virus) — Global Epidemiology](https://www.kaggle.com/datasets/zkskhurram/hantavirus-andes-virus-global-epidemiology) on Kaggle, published by `zkskhurram`.

The workbook contains 10,000 unique patient IDs. In this workbook, `outcome_biner = 1` means Recovered and `0` means Deceased. The figures retain the original Indonesian labels `Sembuh` and `Meninggal/Buruk`.

| Split | Recovered | Deceased | Total |
| --- | ---: | ---: | ---: |
| Training | 7,150 | 849 | 7,999 |
| Holdout | 1,788 | 213 | 2,001 |

1. The script checks the required columns, parses five numeric predictors, and verifies the 0/1 outcome and patient IDs. All 10,000 rows passed the outcome and ID checks. A stratified split with seed 123 allocates approximately 80% of each class to training.
2. Training defines the factor levels, category pooling, and imputation rules. The script pools levels with fewer than 25 training observations in `country`, `comorbidity`, `exposure_type`, and `treatment_protocol`. Only `MV Hondius (International)` was pooled, covering 10 training rows and 3 holdout rows.
3. When a predictor is missing, the script uses the training median for numeric values and the training mode for categorical values. Unseen levels map to the training pool of rare categories when available, or to the training mode. This run recorded zero imputations and zero unseen holdout levels.
4. Screening on training removes constant and exactly collinear predictors. Each country category in training contained a single syndrome, so the script kept `syndrome` and removed `country` from the model candidates. Symptom count and length of stay enter the descriptive analysis and diagnostics. The Box-Tidwell check found evidence of nonlinearity for both. Its one-day shift of length of stay applies only to that diagnostic.

### What the training figures show

| Figures | Observations in training |
| --- | --- |
| Outcome, syndrome, severity | Recovery accounts for 89.4% of records. HFRS has 5,189 records and HPS has 2,810. Moderate is the largest severity group (2,592), followed by Severe (2,286), Mild (2,018), and Critical (1,103). |
| Country, sex, blood type, setting, exposure | South Korea is the largest country category (692). There are 4,903 male records. O+ (3,157), rural setting (3,961), and rural dwelling exposure (1,832) lead their respective distributions. |
| Comorbidity and viral load | None is the largest comorbidity category (3,154), and High is the largest viral load category (2,550). |
| Hospitalization, ICU, ventilation, ECMO, dialysis, treatment | The charts record 6,578 hospitalizations, 2,357 ICU admissions, 671 cases of mechanical ventilation, 278 uses of ECMO, and 654 uses of dialysis. IV fluids plus oxygen is the most frequent treatment protocol (2,630). These bars describe frequencies in the workbook. |
| Numeric boxplots and incubation versus length of stay | Age, incubation, and time to diagnosis overlap substantially between outcomes. Median length of stay was 11 days for patients who died and 8 for those who recovered. Repeated integer-day coordinates overlap in the scatter plot, so visible point counts understate the number of records. |

## Model selection and interpretation

All four logistic regression fits used the same 7,999 training rows. The Akaike information criterion (AIC) rewards fit and penalizes extra parameters.

| Training fit | Predictors | Parameters | AIC |
| --- | ---: | ---: | ---: |
| Full | 17 | 51 | 3978.95 |
| Forward | 2 | 5 | 3926.78 |
| Backward | 2 | 5 | 3926.78 |
| Stepwise | 2 | 5 | 3926.78 |

Forward, backward, and stepwise converged on `outcome_biner ~ severity + syndrome`. The script labels the tied result Stepwise according to its preset ordering. The selected fit lowered training deviance from 5413.16 to 3916.78 relative to the intercept-only model. McFadden's pseudo-R² was 0.2764.

| Adjusted comparison | Recovery odds ratio | 95% Wald interval |
| --- | ---: | ---: |
| Mild versus Critical | 28.89 | 19.87 to 42.00 |
| Moderate versus Critical | 24.94 | 18.59 to 33.47 |
| Severe versus Critical | 3.71 | 3.11 to 4.42 |
| HPS versus HFRS | 0.22 | 0.19 to 0.26 |

The odds ratio plot uses a log scale with 1 as its reference line. At the same recorded severity, the model estimates lower odds of recovery for HPS than for HFRS. At the same syndrome, Mild, Moderate, and Severe have higher estimated recovery odds than Critical. The intervals describe fitted associations and are exploratory after variable selection.

## Holdout performance with imbalanced classes

![Training and holdout ROC curves. The markers use the same training-derived Youden threshold.](figures/evaluasi_roc.png)

| Ranking metric on the holdout | Recovery as positive | Death as positive |
| --- | ---: | ---: |
| ROC AUC | 0.8654 | 0.8654 |
| PR-AUC (PRROC integral) | 0.9803 | 0.4361 |
| Average precision | 0.9764 | 0.4111 |
| Precision-recall baseline (prevalence) | 0.8936 | 0.1064 |

The ROC AUC was 0.8574 on training and 0.8654 on the holdout (95% CI 0.8421 to 0.8887). The supplied precision-recall plot uses recovery as its positive class, so its dashed baseline is already about 0.894. Recomputing precision-recall with `P(Death) = 1 - P(Recovery)` gives a direct view of minority-class ranking. Average precision and PR-AUC use different integration rules.

The predicted scores take eight values because the model combines four severity levels with two syndromes. The smoothed score distributions overlap near the Youden cutoff. The three populated calibration bins lie close to the diagonal, with 160, 358, and 1,483 holdout rows. The Brier score is 0.0711, compared with 0.0951 for predicting the training recovery rate for every holdout row.

## Choosing the classification threshold

The model classifies a case as Recovered when `P(Recovery) >= threshold`. Raising the threshold flags more cases as Death. The script maximizes Youden's J (sensitivity + specificity - 1) on the fitted training scores and applies the exact value, approximately 0.9321, to the holdout. In the original output, recovery is positive, so **specificity is the recall of deaths**.

![Holdout confusion matrices at the default and training-derived Youden thresholds. Percentages are within each actual class.](figures/testing_confusion_matrix.png)

| Holdout metric | Default 0.50 | Youden training |
| --- | ---: | ---: |
| Deaths detected / missed | 91 / 122 | 169 / 44 |
| Recovered patients flagged as deaths | 69 | 349 |
| Death precision | 56.9% | 32.6% |
| Death recall | 42.7% | 79.3% |
| Death F1 | 0.488 | 0.462 |
| Recovery precision | 93.4% | 97.0% |
| Recovery recall | 96.1% | 80.5% |
| Recovery F1 | 0.947 | 0.880 |
| Macro F1 | 0.718 | 0.671 |
| Weighted F1 | 0.898 | 0.835 |
| Balanced accuracy | 69.4% | 79.9% |
| Matthews correlation coefficient (MCC) | 0.442 | 0.421 |
| Accuracy | 90.5% | 80.4% |

F1 combines precision and recall. Macro F1 gives each class equal weight, weighted F1 weights by class size, and balanced accuracy averages the two recalls. MCC summarizes all four confusion-matrix cells. Predicting recovery for everyone would yield 89.4% accuracy, 50.0% balanced accuracy, and a death F1 of 0.

Of the two evaluated cutoffs, **Youden is the choice when catching more deaths is the priority**. It detects 78 additional deaths and flags 280 additional recovered patients. The default 0.50 cutoff yields the higher death F1, macro F1, and MCC in this comparison. A threshold of 1.00 misses zero deaths here by flagging all 2,001 holdout cases, including 1,788 recoveries. A patient who died received the highest model score for recovery, about 0.9907.

These estimates describe a random holdout from the same workbook. Assessing performance in a new setting would require a separate cohort and a defined prediction time at which severity is already available.

## Reproduce the analysis

The analysis ran on R 4.4.3. Install the packages in R, then run the script from the repository root with a local copy of the workbook.

```r
install.packages(c("readxl", "ggplot2", "scales", "car", "caret", "pROC", "PRROC"))
```

```powershell
Rscript .\hantavirus_outcome.R "C:\path\to\hantavirus_clinical.xlsx"
```

In RStudio, open [the R script](hantavirus_outcome.R), click **Source**, and run `result <- run_hantavirus(file.choose())`. Use `result$threshold_youden` for the full-precision cutoff. The script prints the holdout metrics and saves `hantavirus_plots.pdf` and `hantavirus_plots_png/` to the R working directory.

[Original RPubs report](https://rpubs.com/rayyanonrpubs/hantavirusoutcome) · [Technical audit (Bahasa Indonesia)](anti-slop/audit-001-2026-11-09.md)
