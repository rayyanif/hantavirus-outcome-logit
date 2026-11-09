# Analisis Rayyan Ilyas Fadani dan Gregorius Adiyatma Pradana.
# Rscript hantavirus_outcome.R hantavirus_clinical.xlsx [hantavirus_plots.pdf]

numeric_vars <- c(
  "age", "number_of_symptoms", "incubation_days",
  "length_of_stay_days", "days_to_diagnosis"
)

numeric_labels <- setNames(
  c("Usia (tahun)", "Jumlah gejala", "Masa inkubasi (hari)",
    "Lama rawat (hari)", "Waktu ke diagnosis (hari)"),
  numeric_vars
)

category_labels <- c(
  country = "Negara",
  syndrome = "Sindrom",
  sex = "Jenis kelamin",
  severity = "Tingkat keparahan",
  hospitalized = "Rawat inap",
  icu_admission = "Masuk ICU",
  mechanical_ventilation = "Ventilasi mekanik",
  ecmo_used = "Penggunaan ECMO",
  dialysis = "Dialisis",
  comorbidity = "Komorbiditas",
  exposure_type = "Jenis paparan",
  blood_type = "Golongan darah",
  viral_load_category = "Kategori viral load",
  treatment_protocol = "Protokol pengobatan",
  geographic_setting = "Lokasi geografis",
  outcome_label = "Status akhir pasien"
)

rare_vars <- c("country", "comorbidity", "exposure_type", "treatment_protocol")
outcome_levels <- c("Meninggal/Buruk", "Sembuh")
outcome_colors <- setNames(c("#e76f51", "#2a9d8f"), outcome_levels)
split_colors <- c(Training = "#0077b6", Testing = "#e76f51")

show_table <- function(title, data) {
  cat("\n", title, "\n", sep = "")
  print(data, digits = 4)
}

read_hantavirus <- function(path) {
  raw <- as.data.frame(readxl::read_excel(path, col_types = "text", na = c("", "NA")))
  show_table("Ukuran data sumber", data.frame(Observasi = nrow(raw), Kolom = ncol(raw)))

  categorical <- setdiff(names(category_labels), "outcome_label")
  required <- c(categorical, numeric_vars, "outcome_biner")
  missing_columns <- setdiff(required, names(raw))
  if (length(missing_columns)) {
    stop("Kolom yang diperlukan: ", paste(missing_columns, collapse = ", "), call. = FALSE)
  }

  data <- raw[required]
  for (var in c(numeric_vars, "outcome_biner")) {
    value <- suppressWarnings(as.numeric(data[[var]]))
    if (any(!is.na(data[[var]]) & !is.finite(value))) {
      stop("Nilai nonnumerik atau tak hingga pada kolom ", var, call. = FALSE)
    }
    data[[var]] <- value
  }

  outcome <- data$outcome_biner
  if (any(!is.na(outcome) & !outcome %in% c(0, 1))) {
    stop("outcome_biner harus 0 (Meninggal/Buruk) atau 1 (Sembuh).", call. = FALSE)
  }
  if (anyNA(outcome)) {
    message(sum(is.na(outcome)), " baris tanpa outcome dikeluarkan sebelum split.")
  }
  if ("patient_id" %in% names(raw)) {
    patient_id <- raw$patient_id[!is.na(outcome)]
    if (anyNA(patient_id) || anyDuplicated(patient_id)) {
      stop("patient_id pada baris berlabel harus terisi dan unik untuk split per pasien.", call. = FALSE)
    }
  }
  data$row_id <- seq_len(nrow(data))
  data <- data[!is.na(outcome), , drop = FALSE]
  data$outcome_biner <- as.integer(data$outcome_biner)
  data$outcome_label <- factor(outcome_levels[data$outcome_biner + 1L], levels = outcome_levels)
  data
}

stratified_split <- function(data, proportion = 0.8) {
  by_class <- split(seq_len(nrow(data)), data$outcome_label)
  if (any(lengths(by_class) < 2L)) {
    stop("Setiap kelas outcome perlu minimal dua observasi untuk split.", call. = FALSE)
  }

  train_index <- unlist(lapply(by_class, function(index) {
    size <- floor(length(index) * proportion)
    index[sample.int(length(index), size)]
  }), use.names = FALSE)
  list(
    train = data[train_index, , drop = FALSE],
    test = data[-train_index, , drop = FALSE]
  )
}

fit_preprocessor <- function(train, min_count = 25L) {
  categorical <- setdiff(names(category_labels), "outcome_label")
  rules <- list()

  for (var in c(numeric_vars, categorical)) {
    observed <- train[[var]][!is.na(train[[var]])]
    if (!length(observed)) next

    if (var %in% numeric_vars) {
      rules[[var]] <- list(median = stats::median(observed))
    } else {
      counts <- table(observed)
      known <- names(counts)
      pooled <- if (var %in% rare_vars) known[counts < min_count] else character()
      mapped <- observed
      mapped[mapped %in% pooled] <- "Kategori lain/jarang"
      mode <- names(which.max(table(mapped)))

      rules[[var]] <- list(
        known = known,
        pooled = pooled,
        levels = sort(unique(mapped)),
        mode = mode,
        fallback = if (length(pooled)) "Kategori lain/jarang" else mode
      )
    }
  }

  unavailable <- setdiff(c(numeric_vars, categorical), names(rules))
  if (length(unavailable)) {
    message("Prediktor tanpa nilai di training: ", paste(unavailable, collapse = ", "))
  }
  rules
}

apply_preprocessor <- function(data, rules) {
  adjustments <- data.frame(
    Prediktor = names(rules),
    Diimputasi = integer(length(rules)),
    Level_baru = integer(length(rules)),
    Level_langka = integer(length(rules))
  )

  for (i in seq_along(rules)) {
    var <- names(rules)[i]
    rule <- rules[[i]]
    value <- data[[var]]
    missing <- is.na(value)
    adjustments$Diimputasi[i] <- sum(missing)

    if (!is.null(rule$median)) {
      value[missing] <- rule$median
    } else {
      unseen <- !missing & !value %in% rule$known
      pooled <- !missing & value %in% rule$pooled
      adjustments$Level_baru[i] <- sum(unseen)
      adjustments$Level_langka[i] <- sum(pooled)
      value[pooled] <- "Kategori lain/jarang"
      value[unseen] <- rule$fallback
      value[missing] <- rule$mode
      value <- factor(value, levels = rule$levels)
    }
    data[[var]] <- value
  }

  changed <- rowSums(adjustments[-1L]) > 0L
  list(data = data, adjustments = adjustments[changed, , drop = FALSE])
}

describe_training <- function(raw_train, train, save_plot) {
  show_table("Contoh data training", head(data.frame(
    "Status akhir" = raw_train$outcome_label,
    Negara = raw_train$country,
    Sindrom = raw_train$syndrome,
    Usia = raw_train$age,
    "Jenis kelamin" = raw_train$sex,
    "Jumlah gejala" = raw_train$number_of_symptoms,
    "Masa inkubasi" = raw_train$incubation_days,
    Keparahan = raw_train$severity,
    "Rawat inap" = raw_train$hospitalized,
    check.names = FALSE
  ), 8L))

  for (var in names(category_labels)) {
    label <- category_labels[[var]]
    value <- as.character(train[[var]])
    value[is.na(raw_train[[var]])] <- "(Kosong)"
    counts <- table(value, useNA = "ifany")
    summary <- data.frame(
      Kategori = names(counts),
      Jumlah = as.integer(counts),
      Proporsi = scales::percent(as.integer(counts) / sum(counts), accuracy = 0.1)
    )
    show_table(paste("Distribusi training:", label), summary)

    palette <- grDevices::colorRampPalette(c("#2a9d8f", "#457b9d", "#e76f51"))
    colors <- if (var == "outcome_label") outcome_colors else palette(nrow(summary))
    graph <- ggplot2::ggplot(summary, ggplot2::aes(Kategori, Jumlah, fill = Kategori)) +
      ggplot2::geom_col(width = 0.65) +
      ggplot2::geom_text(ggplot2::aes(label = Jumlah), hjust = -0.15, size = 3) +
      ggplot2::scale_fill_manual(values = colors, guide = "none") +
      ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.18))) +
      ggplot2::coord_flip() +
      ggplot2::labs(title = paste("Distribusi training:", label), x = NULL, y = "Jumlah pasien") +
      ggplot2::theme_minimal()
    save_plot(paste0("training_distribusi_", var), graph)
  }

  numeric_summary <- do.call(rbind, lapply(split(raw_train, raw_train$outcome_label), function(group) {
    data.frame(
      Jumlah = nrow(group),
      Rerata_usia = mean(group$age, na.rm = TRUE),
      Median_lama_rawat = stats::median(group$length_of_stay_days, na.rm = TRUE),
      Rerata_inkubasi = mean(group$incubation_days, na.rm = TRUE),
      Rerata_jumlah_gejala = mean(group$number_of_symptoms, na.rm = TRUE)
    )
  }))
  show_table("Ringkasan numerik training menurut outcome", numeric_summary)

  save_plot("training_inkubasi_dan_lama_rawat",
    ggplot2::ggplot(raw_train, ggplot2::aes(incubation_days, length_of_stay_days, color = outcome_label)) +
      ggplot2::geom_point(alpha = 0.65, na.rm = TRUE) +
      ggplot2::scale_color_manual(values = outcome_colors) +
      ggplot2::labs(
        title = "Masa inkubasi dan lama rawat pada training",
        x = "Masa inkubasi (hari)", y = "Lama rawat (hari)", color = "Outcome"
      ) +
      ggplot2::theme_minimal()
  )

  numeric_data <- do.call(rbind, lapply(numeric_vars, function(var) {
    data.frame(Variabel = numeric_labels[[var]], Nilai = raw_train[[var]],
               Outcome = raw_train$outcome_label)
  }))
  numeric_data$Variabel <- factor(numeric_data$Variabel, levels = unname(numeric_labels))
  save_plot("training_boxplot_numerik",
    ggplot2::ggplot(numeric_data, ggplot2::aes(Outcome, Nilai, fill = Outcome)) +
      ggplot2::geom_boxplot(width = 0.58, outlier.alpha = 0.2, na.rm = TRUE) +
      ggplot2::facet_wrap(~Variabel, scales = "free_y", ncol = 3) +
      ggplot2::scale_fill_manual(values = outcome_colors, guide = "none") +
      ggplot2::labs(title = "Sebaran variabel numerik menurut outcome pada training",
                    x = NULL, y = NULL) +
      ggplot2::theme_minimal()
  )
}

outcome_formula <- function(predictors) {
  stats::reformulate(if (length(predictors)) predictors else "1", response = "outcome_biner")
}

estimable_terms <- function(train, candidates, label) {
  terms <- candidates[vapply(train[candidates], function(x) {
    length(unique(x[!is.na(x)])) >= 2L
  }, logical(1))]

  repeat {
    matrix <- stats::model.matrix(outcome_formula(terms), data = train)
    decomposition <- qr(matrix)
    if (decomposition$rank == ncol(matrix)) break
    dependent <- decomposition$pivot[seq.int(decomposition$rank + 1L, ncol(matrix))]
    term_index <- max(attr(matrix, "assign")[dependent])
    terms <- terms[-term_index]
  }

  removed <- setdiff(candidates, terms)
  if (length(removed)) {
    message(label, " dikeluarkan karena konstan atau kolinear: ", paste(removed, collapse = ", "))
  }
  terms
}

training_diagnostics <- function(train, available) {
  vif_candidates <- setdiff(available, "country")
  vif_terms <- estimable_terms(train, vif_candidates, "VIF/GVIF")
  if (length(vif_terms) > 1L) {
    vif_model <- stats::glm(outcome_formula(vif_terms), data = train, family = stats::binomial())
    if (vif_model$converged && all(is.finite(stats::coef(vif_model)))) {
      vif <- car::vif(vif_model)
      if (is.matrix(vif)) {
        vif_table <- as.data.frame(vif)
        adjusted <- vif[, 3L]
      } else {
        vif_table <- data.frame(VIF = vif)
        adjusted <- sqrt(vif)
      }
      vif_table$Interpretasi <- ifelse(
        adjusted < sqrt(5), "Rendah",
        ifelse(adjusted < sqrt(10), "Moderat", "Tinggi")
      )
      show_table("VIF/GVIF pada training", vif_table)
    } else {
      message("VIF/GVIF dilewati karena model diagnostik tidak konvergen atau koefisien tidak terestimasi.")
    }
  }

  numeric_terms <- intersect(numeric_vars, available)
  bt_data <- train
  transformed <- character()
  for (var in numeric_terms) {
    value <- bt_data[[var]]
    if (length(unique(value)) < 3L) next
    offset <- if (min(value) <= 0) 1 - min(value) else 0
    if (offset > 0) message("Box-Tidwell: ", var, " digeser sebesar ", offset, ".")
    term <- paste0(var, "_xlogx")
    shifted <- value + offset
    bt_data[[term]] <- shifted * log(shifted)
    transformed <- c(transformed, term)
  }

  bt_terms <- estimable_terms(bt_data, c(numeric_terms, transformed), "Box-Tidwell")
  tested <- intersect(transformed, bt_terms)
  if (length(tested)) {
    bt_model <- stats::glm(outcome_formula(bt_terms), data = bt_data, family = stats::binomial())
    if (bt_model$converged) {
      result <- as.data.frame(summary(bt_model)$coefficients[tested, , drop = FALSE])
      row.names(result) <- sub("_xlogx$", "", tested)
      result$Interpretasi <- ifelse(
        result[["Pr(>|z|)"]] < 0.05, "Indikasi nonlinear", "Bukti nonlinear belum cukup"
      )
      show_table("Box-Tidwell pada training", result)
    } else {
      message("Box-Tidwell dilewati karena model diagnostik tidak konvergen.")
    }
  }
}

fit_models <- function(train, available) {
  # Dua variabel ini digunakan untuk deskripsi dan diagnostik pada analisis asal.
  candidates <- setdiff(available, c("number_of_symptoms", "length_of_stay_days"))
  # Utamakan prediktor klinis jika kategori negara menyandikan informasi yang sama.
  candidates <- c(setdiff(candidates, "country"), intersect("country", candidates))
  predictors <- estimable_terms(train, candidates, "Model prediksi")
  full_formula <- outcome_formula(predictors)
  null_model <- stats::glm(outcome_biner ~ 1, data = train, family = stats::binomial(), na.action = stats::na.fail)
  full_model <- stats::glm(full_formula, data = train, family = stats::binomial(), na.action = stats::na.fail)

  scope <- list(lower = stats::formula(null_model), upper = full_formula)
  models <- list(
    Stepwise = stats::step(null_model, scope = scope, direction = "both", trace = 0),
    Backward = stats::step(full_model, direction = "backward", trace = 0),
    Forward = stats::step(null_model, scope = scope, direction = "forward", trace = 0),
    Full = full_model
  )
  stopifnot(all(vapply(models, stats::nobs, integer(1)) == nrow(train)))

  model_comparison <- data.frame(
    Prediktor = vapply(models, function(model) length(attr(stats::terms(model), "term.labels")), integer(1)),
    Parameter = vapply(models, function(model) model$rank, integer(1)),
    AIC = vapply(models, stats::AIC, numeric(1)),
    Deviance_residual = vapply(models, stats::deviance, numeric(1)),
    Konvergen = vapply(models, function(model) {
      model$converged && all(is.finite(stats::coef(model)))
    }, logical(1))
  )
  show_table("Perbandingan model pada training", model_comparison[c("Full", "Forward", "Backward", "Stepwise"), ])
  eligible <- with(model_comparison, Konvergen & is.finite(AIC))
  if (!any(eligible)) stop("Tidak ada model yang layak berdasarkan konvergensi dan AIC.", call. = FALSE)

  # Jika AIC setara secara numerik, utamakan model dengan lebih sedikit parameter.
  best_aic <- min(model_comparison$AIC[eligible])
  tied <- which(eligible & abs(model_comparison$AIC - best_aic) <= 1e-8)
  selected <- names(models)[tied[which.min(model_comparison$Parameter[tied])]]

  for (method in c("Forward", "Backward", "Stepwise")) {
    model <- models[[method]]
    if (!model_comparison[method, "Konvergen"]) next
    coef <- as.data.frame(summary(model)$coefficients)
    coef$Odds_ratio <- exp(coef$Estimate)
    coef$CI_Wald_95_bawah <- exp(coef$Estimate - stats::qnorm(0.975) * coef[["Std. Error"]])
    coef$CI_Wald_95_atas <- exp(coef$Estimate + stats::qnorm(0.975) * coef[["Std. Error"]])
    show_table(paste("Koefisien training:", method), coef)
  }

  cat("\nModel terpilih berdasarkan AIC training:", selected, "\n")
  print(summary(models[[selected]]))
  list(model = models[[selected]], null = null_model, comparison = model_comparison, selected = selected)
}

show_fit <- function(model, null) {
  ll <- as.numeric(stats::logLik(model))
  ll_null <- as.numeric(stats::logLik(null))
  n <- stats::nobs(model)
  k <- model$rank
  aic <- stats::AIC(model)
  aicc <- if (n > k + 1L) aic + 2 * k * (k + 1L) / (n - k - 1L) else NA_real_

  show_table("Kecocokan model pada training", data.frame(
    Observasi = n, Parameter = k,
    Null_deviance = model$null.deviance,
    Residual_deviance = model$deviance,
    df_residual = model$df.residual,
    AIC = aic, AICc = aicc, BIC = stats::BIC(model)
  ))
  if (model$rank > null$rank) {
    show_table("Likelihood Ratio Test pada training (eksploratif pascaseleksi)",
               stats::anova(null, model, test = "Chisq"))
  }

  cox_snell <- -expm1(2 * (ll_null - ll) / n)
  show_table("Pseudo R-squared pada training", data.frame(
    Cox_Snell = cox_snell,
    Nagelkerke = cox_snell / -expm1(2 * ll_null / n),
    McFadden = 1 - ll / ll_null
  ))
}

plot_odds_ratios <- function(model, save_plot) {
  coefficients <- summary(model)$coefficients
  coefficients <- coefficients[row.names(coefficients) != "(Intercept)", , drop = FALSE]
  estimate <- coefficients[, "Estimate"]
  margin <- stats::qnorm(0.975) * coefficients[, "Std. Error"]
  odds <- data.frame(Term = row.names(coefficients), OR = exp(estimate),
                     Lower = exp(estimate - margin), Upper = exp(estimate + margin))
  odds <- odds[is.finite(odds$Upper) & odds$Lower > 0, , drop = FALSE]

  if (!nrow(odds)) {
    graph <- ggplot2::ggplot() +
      ggplot2::annotate("text", x = 0, y = 0, label = "Tidak ada odds ratio prediktor dengan interval terbatas.") +
      ggplot2::labs(title = "Odds ratio model akhir pada training") +
      ggplot2::theme_void()
  } else {
    graph <- ggplot2::ggplot(odds, ggplot2::aes(stats::reorder(Term, OR), OR)) +
      ggplot2::geom_hline(yintercept = 1, linetype = "dashed", color = "grey55") +
      ggplot2::geom_pointrange(ggplot2::aes(ymin = Lower, ymax = Upper), color = "#0077b6") +
      ggplot2::scale_y_log10() +
      ggplot2::coord_flip() +
      ggplot2::labs(
        title = "Odds ratio model akhir pada training",
        subtitle = "Interval Wald 95% bersifat eksploratif setelah pemilihan model",
        x = NULL, y = "Odds ratio untuk Sembuh (skala log)"
      ) +
      ggplot2::theme_minimal()
  }
  save_plot("training_odds_ratio", graph)
}

predict_split <- function(model, data) {
  probability <- stats::predict(model, newdata = data, type = "response", na.action = stats::na.fail)
  stopifnot(
    length(probability) == nrow(data),
    identical(names(probability), row.names(data)),
    all(is.finite(probability)),
    all(probability >= 0 & probability <= 1)
  )
  data.frame(row_id = data$row_id, actual = data$outcome_biner, probability = unname(probability))
}

divide <- function(numerator, denominator) {
  ifelse(denominator == 0, NA_real_, numerator / denominator)
}

threshold_result <- function(predictions, threshold) {
  actual <- factor(predictions$actual, levels = 0:1, labels = outcome_levels)
  predicted <- factor(as.integer(predictions$probability >= threshold), levels = 0:1, labels = outcome_levels)
  counts <- table(Aktual = actual, Prediksi = predicted)
  tn <- as.double(counts[1L, 1L])
  fp <- as.double(counts[1L, 2L])
  fn <- as.double(counts[2L, 1L])
  tp <- as.double(counts[2L, 2L])
  sensitivity <- divide(tp, tp + fn)
  specificity <- divide(tn, tn + fp)
  accuracy <- divide(tp + tn, sum(counts))
  f1_recovery <- divide(2 * tp, 2 * tp + fp + fn)
  f1_death <- divide(2 * tn, 2 * tn + fp + fn)

  metrics <- data.frame(
    Threshold = threshold, Akurasi = accuracy, Error_rate = 1 - accuracy,
    Sensitivity = sensitivity, Specificity = specificity,
    Presisi = divide(tp, tp + fp), NPV = divide(tn, tn + fn),
    F1 = f1_recovery,
    Balanced_accuracy = (sensitivity + specificity) / 2,
    FPR = 1 - specificity, FNR = 1 - sensitivity
  )
  imbalance <- data.frame(
    Precision_meninggal = divide(tn, tn + fn), Recall_meninggal = specificity,
    F1_meninggal = f1_death, F1_sembuh = f1_recovery,
    Macro_F1 = (f1_death + f1_recovery) / 2,
    Weighted_F1 = (f1_death * (tn + fp) + f1_recovery * (tp + fn)) / sum(counts),
    MCC = divide(tp * tn - fp * fn, sqrt((tp + fp) * (tp + fn) * (tn + fp) * (tn + fn)))
  )
  list(counts = counts, metrics = metrics, imbalance = imbalance, actual = actual, predicted = predicted)
}

curve_points <- function(predictions) {
  index <- order(predictions$probability, decreasing = TRUE)
  groups <- rle(predictions$probability[index])
  ends <- cumsum(groups$lengths)
  tp <- cumsum(predictions$actual[index])[ends]
  fp <- ends - tp
  sensitivity <- tp / sum(predictions$actual == 1L)
  fpr <- fp / sum(predictions$actual == 0L)

  # Setiap skor yang sama menghasilkan satu titik untuk aturan >= threshold.
  data.frame(
    threshold = c(Inf, groups$values),
    sensitivity = c(0, sensitivity),
    fpr = c(0, fpr),
    youden = c(0, sensitivity - fpr),
    precision = c(NA_real_, tp / ends)
  )
}

curve_summary <- function(predictions, points) {
  roc <- pROC::roc(predictions$actual, predictions$probability,
                   levels = c(0, 1), direction = "<", quiet = TRUE)
  auc <- as.numeric(pROC::auc(roc))
  roc_auc_manual <- sum(diff(points$fpr) *
                          (head(points$sensitivity, -1L) + tail(points$sensitivity, -1L)) / 2)
  stopifnot(isTRUE(all.equal(roc_auc_manual, auc, tolerance = 1e-10)))
  interval <- pROC::ci.auc(roc)

  pr <- PRROC::pr.curve(
    scores.class0 = predictions$probability[predictions$actual == 1L],
    scores.class1 = predictions$probability[predictions$actual == 0L]
  )

  data.frame(
    AUC_manual = roc_auc_manual, AUC_pROC = auc,
    AUC_CI95_bawah = interval[1L], AUC_CI95_atas = interval[3L],
    AP_manual = sum(diff(points$sensitivity) * points$precision[-1L]),
    AUPRC_PRROC = pr$auc.integral,
    Prevalensi_sembuh = mean(predictions$actual == 1L)
  )
}

plot_evaluation <- function(train_points, test_points, train_opt, test_opt, test_predictions,
                            discrimination, save_plot) {
  points <- rbind(
    transform(train_points, Data = "Training"),
    transform(test_points, Data = "Testing")
  )
  roc_markers <- data.frame(
    fpr = c(train_opt$FPR, test_opt$FPR),
    sensitivity = c(train_opt$Sensitivity, test_opt$Sensitivity),
    Data = c("Training", "Testing")
  )
  threshold <- test_opt$Threshold

  save_plot("evaluasi_roc",
    ggplot2::ggplot(points, ggplot2::aes(fpr, sensitivity, color = Data)) +
      ggplot2::geom_path(linewidth = 1) +
      ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey60") +
      ggplot2::geom_point(data = roc_markers, size = 3) +
      ggplot2::scale_color_manual(values = split_colors) +
      ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
      ggplot2::labs(
        title = "Kurva ROC untuk kelas Sembuh",
        subtitle = sprintf("Titik menandai ambang Youden training (%.3f)", threshold),
        x = "False positive rate", y = "Sensitivity"
      ) +
      ggplot2::theme_minimal()
  )

  probability_data <- transform(test_predictions, Outcome = factor(actual, levels = 0:1, labels = outcome_levels))
  distribution <- if (all(table(probability_data$Outcome) > 1L)) {
    ggplot2::geom_density(alpha = 0.55, linewidth = 0.6)
  } else {
    ggplot2::geom_histogram(binwidth = 0.05, boundary = 0, alpha = 0.55, position = "identity")
  }
  save_plot("testing_distribusi_peluang",
    ggplot2::ggplot(probability_data, ggplot2::aes(probability, fill = Outcome)) +
      distribution +
      ggplot2::geom_vline(xintercept = threshold, linetype = "dashed") +
      ggplot2::scale_fill_manual(values = outcome_colors) +
      ggplot2::coord_cartesian(xlim = c(0, 1)) +
      ggplot2::labs(
        title = "Distribusi peluang prediksi pada testing",
        x = "Peluang prediksi Sembuh", y = NULL
      ) +
      ggplot2::theme_minimal()
  )

  # Di recall nol, gunakan presisi pada skor tertinggi untuk menggambar titik awal.
  points$precision[is.na(points$precision)] <- c(train_points$precision[2L], test_points$precision[2L])
  baseline <- data.frame(Data = row.names(discrimination), Prevalensi = discrimination$Prevalensi_sembuh)
  save_plot("evaluasi_precision_recall",
    ggplot2::ggplot(points, ggplot2::aes(sensitivity, precision, color = Data)) +
      ggplot2::geom_step(direction = "vh", linewidth = 1) +
      ggplot2::geom_hline(data = baseline, ggplot2::aes(yintercept = Prevalensi, color = Data),
                          linetype = "dashed", alpha = 0.5, show.legend = FALSE) +
      ggplot2::scale_color_manual(values = split_colors) +
      ggplot2::coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
      ggplot2::labs(
        title = "Kurva precision-recall untuk kelas Sembuh",
        subtitle = "Garis putus-putus menunjukkan prevalensi Sembuh pada masing-masing split",
        x = "Recall", y = "Precision"
      ) +
      ggplot2::theme_minimal()
  )
}

plot_holdout <- function(split_counts, test_predictions, confusion, testing_metrics, save_plot) {
  split_data <- as.data.frame(as.table(split_counts), responseName = "Jumlah")
  names(split_data)[1:2] <- c("Split", "Outcome")
  split_data$Proporsi <- as.vector(prop.table(split_counts, margin = 1L))
  split_dodge <- ggplot2::position_dodge(width = 0.7)
  save_plot("split_distribusi_outcome",
    ggplot2::ggplot(split_data, ggplot2::aes(Split, Proporsi, fill = Outcome)) +
      ggplot2::geom_col(width = 0.6, position = split_dodge) +
      ggplot2::geom_text(ggplot2::aes(label = paste0(
        Jumlah, " (", scales::percent(Proporsi, accuracy = 0.1), ")"
      )), position = split_dodge, vjust = -0.4, size = 3.4) +
      ggplot2::scale_fill_manual(values = outcome_colors) +
      ggplot2::scale_y_continuous(labels = scales::label_percent(), breaks = seq(0, 1, 0.2)) +
      ggplot2::coord_cartesian(ylim = c(0, 1.08)) +
      ggplot2::labs(title = "Komposisi outcome menurut split", x = NULL, y = "Proporsi pasien") +
      ggplot2::theme_minimal() +
      ggplot2::theme(legend.position = "bottom")
  )

  threshold_labels <- c("Default (0.50)", sprintf("Youden training (%.3f)", testing_metrics$Threshold[2L]))
  cells <- do.call(rbind, lapply(seq_along(confusion), function(i) {
    counts <- confusion[[i]]
    cell <- as.data.frame(counts, responseName = "Jumlah")
    cell$Proporsi <- as.vector(prop.table(counts, margin = 1L))
    cell$Ambang <- factor(threshold_labels[i], levels = threshold_labels)
    cell
  }))
  save_plot("testing_confusion_matrix",
    ggplot2::ggplot(cells, ggplot2::aes(Prediksi, Aktual, fill = Proporsi)) +
      ggplot2::geom_tile(color = "white", linewidth = 1) +
      ggplot2::geom_text(ggplot2::aes(label = paste0(
        Jumlah, "\n", scales::percent(Proporsi, accuracy = 0.1)
      ), color = Proporsi > 0.66), size = 4.2) +
      ggplot2::scale_color_manual(values = c("FALSE" = "#0d2030", "TRUE" = "white"), guide = "none") +
      ggplot2::scale_fill_gradient(low = "#eef5fa", high = "#0a527f", limits = c(0, 1), guide = "none") +
      ggplot2::facet_wrap(~Ambang) +
      ggplot2::labs(title = "Confusion matrix pada testing",
                    subtitle = "Persentase dihitung dalam setiap kelas aktual") +
      ggplot2::theme_minimal() +
      ggplot2::theme(panel.grid = ggplot2::element_blank())
  )

  columns <- c("Akurasi", "Sensitivity", "Specificity", "Balanced_accuracy")
  labels <- c("Akurasi", "Sensitivity", "Specificity", "Balanced accuracy")
  comparison <- data.frame(
    Ambang = factor(rep(threshold_labels, times = length(columns)), levels = threshold_labels),
    Metrik = factor(rep(labels, each = length(threshold_labels)), levels = labels),
    Nilai = unlist(testing_metrics[columns], use.names = FALSE)
  )
  save_plot("testing_perbandingan_ambang",
    ggplot2::ggplot(comparison, ggplot2::aes(Metrik, Nilai, fill = Ambang)) +
      ggplot2::geom_col(position = ggplot2::position_dodge(width = 0.75), width = 0.65) +
      ggplot2::geom_text(ggplot2::aes(label = scales::percent(Nilai, accuracy = 0.1)),
                         position = ggplot2::position_dodge(width = 0.75), vjust = -0.45, size = 3.2) +
      ggplot2::scale_fill_manual(values = c("#0077b6", "#e76f51")) +
      ggplot2::scale_y_continuous(labels = scales::label_percent(), breaks = seq(0, 1, 0.2)) +
      ggplot2::coord_cartesian(ylim = c(0, 1.08)) +
      ggplot2::labs(title = "Perbandingan ambang klasifikasi pada testing",
                    subtitle = "Kelas positif adalah Sembuh", x = NULL, y = NULL) +
      ggplot2::theme_minimal() +
      ggplot2::theme(legend.position = "bottom")
  )

  bins <- cut(test_predictions$probability, breaks = seq(0, 1, 0.1), include.lowest = TRUE)
  calibration <- do.call(rbind, lapply(split(test_predictions, bins, drop = TRUE), function(group) {
    data.frame(Peluang = mean(group$probability), Proporsi = mean(group$actual), Jumlah = nrow(group))
  }))
  stopifnot(sum(calibration$Jumlah) == nrow(test_predictions))
  save_plot("testing_kalibrasi",
    ggplot2::ggplot(calibration, ggplot2::aes(Peluang, Proporsi)) +
      ggplot2::geom_abline(slope = 1, intercept = 0, linetype = "dashed", color = "grey55") +
      ggplot2::geom_point(ggplot2::aes(size = Jumlah), color = "#0077b6", alpha = 0.85) +
      ggplot2::scale_x_continuous(labels = scales::label_percent()) +
      ggplot2::scale_y_continuous(labels = scales::label_percent()) +
      ggplot2::coord_equal(xlim = c(0, 1), ylim = c(0, 1)) +
      ggplot2::labs(
        title = "Kalibrasi peluang Sembuh pada testing",
        subtitle = "Satu titik per interval peluang 10 poin persentase yang terisi",
        x = "Rerata peluang prediksi", y = "Proporsi aktual Sembuh", size = "Jumlah pasien"
      ) +
      ggplot2::theme_minimal()
  )
}

run_hantavirus <- function(path = "hantavirus_clinical.xlsx",
                           plot_file = "hantavirus_plots.pdf") {
  if (!file.exists(path)) stop("File data tidak ditemukan: ", path, call. = FALSE)
  if (!is.null(plot_file) && file.exists(plot_file) &&
      identical(normalizePath(path), normalizePath(plot_file))) {
    stop("Pilih file grafik yang berbeda dari workbook input.", call. = FALSE)
  }

  packages <- c("readxl", "ggplot2", "scales", "car", "caret", "pROC", "PRROC")
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) stop("Instal paket R: ", paste(missing, collapse = ", "), call. = FALSE)

  data <- read_hantavirus(path)
  set.seed(123)
  split <- stratified_split(data)
  stopifnot(
    !anyDuplicated(c(split$train$row_id, split$test$row_id)),
    setequal(c(split$train$row_id, split$test$row_id), data$row_id)
  )

  rules <- fit_preprocessor(split$train)
  prepared_train <- apply_preprocessor(split$train, rules)
  train <- prepared_train$data
  if (nrow(prepared_train$adjustments)) {
    show_table("Penyesuaian prediktor pada training", prepared_train$adjustments)
  }

  png_dir <- NULL
  save_plot <- function(name, plot) print(plot)
  if (!is.null(plot_file)) {
    png_dir <- paste0(tools::file_path_sans_ext(plot_file), "_png")
    dir.create(png_dir, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(png_dir)) stop("Folder grafik tidak dapat dibuat: ", png_dir, call. = FALSE)
    grDevices::pdf(plot_file, width = 9, height = 6, useDingbats = FALSE)
    device <- grDevices::dev.cur()
    on.exit(grDevices::dev.off(device), add = TRUE)
    save_plot <- function(name, plot) {
      print(plot)
      ggplot2::ggsave(file.path(png_dir, paste0(name, ".png")), plot = plot,
                      width = 9, height = 6, dpi = 220, bg = "white")
    }
  }

  describe_training(split$train, train, save_plot)
  training_diagnostics(train, names(rules))
  fitted <- fit_models(train, names(rules))
  show_fit(fitted$model, fitted$null)
  plot_odds_ratios(fitted$model, save_plot)

  train_predictions <- predict_split(fitted$model, train)
  train_points <- curve_points(train_predictions)
  eligible <- which(is.finite(train_points$threshold))
  best <- eligible[order(-train_points$youden[eligible], -train_points$sensitivity[eligible])[1L]]
  threshold_opt <- train_points$threshold[best]
  train_opt <- threshold_result(train_predictions, threshold_opt)$metrics
  cat("\nAmbang Youden dari probabilitas training:", format(threshold_opt, digits = 10), "\n")

  # Model dan ambang sudah ditetapkan saat data testing mulai diproses.
  prepared_test <- apply_preprocessor(split$test, rules)
  test <- prepared_test$data
  test_predictions <- predict_split(fitted$model, test)
  stopifnot(identical(test_predictions$row_id, split$test$row_id))
  split_counts <- rbind(Training = table(train$outcome_label), Testing = table(test$outcome_label))
  show_table("Jumlah observasi per split dan outcome", split_counts)
  show_table("Proporsi outcome dalam tiap split", prop.table(split_counts, margin = 1L))
  if (nrow(prepared_test$adjustments)) {
    show_table("Penyesuaian testing berdasarkan aturan training", prepared_test$adjustments)
  }

  default <- threshold_result(test_predictions, 0.5)
  optimal <- threshold_result(test_predictions, threshold_opt)
  stopifnot(sum(default$counts) == nrow(test), sum(optimal$counts) == nrow(test))
  caret_cm <- caret::confusionMatrix(default$predicted, default$actual, positive = "Sembuh")
  stopifnot(identical(unname(caret_cm$table), unname(t(default$counts))))
  show_table("Confusion matrix testing pada ambang 0.50", addmargins(default$counts))
  show_table("Confusion matrix testing pada ambang Youden training", addmargins(optimal$counts))
  show_table("Ringkasan caret pada testing (ambang 0.50)", c(
    caret_cm$overall[c("Accuracy", "Kappa")],
    caret_cm$byClass[c("Sensitivity", "Specificity", "Precision", "F1", "Prevalence",
                       "Detection Rate", "Balanced Accuracy")]
  ))
  testing_metrics <- rbind(Default = default$metrics, Youden_training = optimal$metrics)
  show_table("Metrik testing dengan kelas positif Sembuh", testing_metrics)
  testing_imbalance <- rbind(Default = default$imbalance, Youden_training = optimal$imbalance)
  show_table("Metrik testing per kelas dan untuk data tidak seimbang", testing_imbalance)

  test_points <- curve_points(test_predictions)
  discrimination <- rbind(
    Training = curve_summary(train_predictions, train_points),
    Testing = curve_summary(test_predictions, test_points)
  )
  show_table("ROC dan precision-recall (training in-sample, testing holdout)", discrimination)
  death_scores <- transform(test_predictions, actual = 1L - actual, probability = 1 - probability)
  death_pr <- curve_summary(death_scores, curve_points(death_scores))[
    c("AP_manual", "AUPRC_PRROC", "Prevalensi_sembuh")
  ]
  names(death_pr)[3L] <- "Prevalensi_meninggal"
  show_table("Precision-recall testing dengan kelas positif Meninggal/Buruk", death_pr)
  brier <- mean((test_predictions$probability - test_predictions$actual)^2)
  brier_baseline <- mean((mean(train_predictions$actual) - test_predictions$actual)^2)
  show_table("Brier score pada testing", data.frame(Model = brier, Baseline_prevalensi = brier_baseline))
  plot_evaluation(train_points, test_points, train_opt, optimal$metrics, test_predictions,
                  discrimination, save_plot)
  testing_confusion <- list(default = default$counts, youden = optimal$counts)
  plot_holdout(split_counts, test_predictions, testing_confusion, testing_metrics, save_plot)
  if (!is.null(plot_file)) {
    message("PDF visualisasi: ", normalizePath(plot_file))
    message("Folder PNG: ", normalizePath(png_dir))
  }

  invisible(list(
    model = fitted$model,
    model_comparison = fitted$comparison,
    selected = fitted$selected,
    preprocessing = rules,
    training_predictions = train_predictions,
    testing_predictions = test_predictions,
    threshold_youden = threshold_opt,
    testing_confusion = testing_confusion,
    testing_metrics = testing_metrics,
    testing_imbalance = testing_imbalance,
    testing_death_precision_recall = death_pr,
    testing_brier = c(model = brier, baseline = brier_baseline),
    discrimination = discrimination,
    visualizations = list(pdf = plot_file, png_directory = png_dir)
  ))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) > 2L) {
    stop("Gunakan: Rscript hantavirus_outcome.R [input.xlsx] [grafik.pdf]", call. = FALSE)
  }
  input <- if (length(args) >= 1L) args[1L] else "hantavirus_clinical.xlsx"
  plots <- if (length(args) >= 2L) args[2L] else "hantavirus_plots.pdf"
  run_hantavirus(input, plots)
}
