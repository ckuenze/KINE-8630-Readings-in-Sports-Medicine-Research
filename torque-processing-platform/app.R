# =============================================================================
# Dynamometer Strength Processing App
#
# Isometric and isokinetic knee torque files -> contraction detection, peak
# torque, RTD, work, angle at peak, H:Q, and limb symmetry, organized by
# participant through a key file.
#
# Run: open this file in RStudio and click "Run App", or in the R console:
#   shiny::runApp("C:/path/to/dynamometer_app")
#
# Filtering and onset defaults follow White et al. (2024) Sensors 24:4250
# (doi:10.3390/s24134250): zero-lag 4th-order Butterworth low-pass at 150 Hz,
# baseline offset removed, torque onset at 1 Nm, RTD 40-160 ms reported as the
# window least sensitive to processing choices.
# =============================================================================

## ---- Packages ---------------------------------------------------------------
pkgs <- c("shiny", "bslib", "DT", "plotly", "signal", "dplyr", "tidyr",
          "readxl", "openxlsx", "zip")
missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing_pkgs)) {
  install.packages(missing_pkgs, repos = "https://cloud.r-project.org")
}

suppressPackageStartupMessages({
  library(shiny)
  library(bslib)
  library(DT)
  library(plotly)
  library(dplyr)
  library(tidyr)
})
# signal, readxl, openxlsx, zip are called with :: (signal::filter clashes with dplyr)

options(shiny.maxRequestSize = 500 * 1024^2)

## ---- Constants and defaults -------------------------------------------------
MIN_FS <- 250  # files sampled below this are rejected
STD_SPEEDS <- c(30, 45, 60, 90, 120, 150, 180, 210, 240, 270, 300, 360, 400, 450, 500)

DEFAULTS <- list(
  cutoff_hz          = 150,   # White et al. 2024 gold standard
  filt_order         = 2,     # per pass; dual-pass -> 4th-order zero-lag
  onset_nm           = 1,     # White et al. 2024 gold standard
  baseline_win_ms    = 250,
  detect_nm          = 10,    # contraction detection: max(detect_nm, detect_frac * file max)
  detect_frac        = 0.20,
  min_contraction_s  = 0.3,
  rtd_windows_ms     = c(50, 100, 150, 200),
  rtd_epoch_ms       = c(40, 160),
  vel_cutoff_hz      = 20,    # angle filter before differentiating
  isovel_tol         = 0.10,  # isovelocity window: within +/-10% of target speed
  min_rom_deg        = 20,
  iso_peak_only      = TRUE,
  exclude_rep1       = TRUE,  # from averages
  exclude_rep1_all   = FALSE, # also from peak and total work
  ext_angle_decreasing = TRUE,
  flip_torque        = FALSE,
  flag_baseline_sd   = 1,
  flag_cm_nm         = 2,
  flag_pretension_nm = 2,
  col_time           = 1,     # column positions for files without column names
  col_torque         = 2,
  col_angle          = 3      # NA = no angle column
)

## ---- File reading -----------------------------------------------------------
# Files either have a column-name row containing "Time" and "Torque" (any
# header block above it is skipped), or have no names at all, in which case
# reading starts at the first all-numeric row and columns are taken by
# position (cols = list(time, torque, angle); angle may be NA).
read_torque_file <- function(path, cols = list(time = 1, torque = 2, angle = 3)) {
  lines <- readLines(path, n = 300, warn = FALSE)
  detect_sep <- function(l) {
    seps <- c(",", "\t", ";")
    counts <- vapply(seps, function(s) lengths(regmatches(l, gregexpr(s, l, fixed = TRUE))), numeric(1))
    if (max(counts) == 0) "" else seps[which.max(counts)]  # "" = any whitespace
  }
  hdr <- which(grepl("time", lines, ignore.case = TRUE) &
               grepl("torque", lines, ignore.case = TRUE) & !grepl("^\\s*#", lines))[1]
  num <- function(x) suppressWarnings(as.numeric(x))
  # record number written into the header block by "Download labeled files"
  rec_line <- grep("^\\W*Record\\s*[:=]\\s*[0-9]+", lines, ignore.case = TRUE, value = TRUE)[1]
  rec <- if (is.na(rec_line)) NA_integer_ else as.integer(sub("^\\W*Record\\s*[:=]\\s*([0-9]+).*", "\\1", rec_line, ignore.case = TRUE))

  if (is.na(hdr)) {
    split_line <- function(l) {
      s <- detect_sep(l)
      f <- if (s == "") strsplit(trimws(l), "\\s+")[[1]] else strsplit(l, s, fixed = TRUE)[[1]]
      trimws(f)
    }
    is_data <- vapply(lines, function(l) {
      f <- split_line(l)
      length(f) >= 2 && all(!is.na(num(f[f != ""])))
    }, logical(1))
    # first row that starts a run of >= 20 numeric rows (so stray numbers in the header block are skipped)
    run <- min(20, length(lines))
    starts <- which(vapply(seq_along(is_data), function(i) {
      i + run - 1 <= length(is_data) && all(is_data[i:(i + run - 1)])
    }, logical(1)))
    first <- starts[1]
    if (is.na(first)) stop("no 'Time'/'Torque' header and no all-numeric data rows found")
    raw <- utils::read.table(path, sep = detect_sep(lines[first]), header = FALSE, skip = first - 1,
                             fill = TRUE, strip.white = TRUE, stringsAsFactors = FALSE, comment.char = "")
    need <- c(cols$time, cols$torque)
    if (max(need) > ncol(raw)) stop(sprintf("file has %d columns; time/torque mapping expects column %d", ncol(raw), max(need)))
    ti <- cols$time
    tq <- cols$torque
    an <- if (!is.na(cols$angle) && cols$angle <= ncol(raw)) cols$angle else NA
  } else {
    raw <- utils::read.table(path, sep = detect_sep(lines[hdr]), header = TRUE, skip = hdr - 1, fill = TRUE,
                             strip.white = TRUE, check.names = FALSE,
                             stringsAsFactors = FALSE, comment.char = "")
    nm <- tolower(names(raw))
    ti <- grep("time", nm)[1]
    tq <- grep("torque", nm)[1]
    an <- grep("angle|position|^pos", nm)[1]
  }
  d <- data.frame(time = num(raw[[ti]]), torque = num(raw[[tq]]))
  if (!is.na(an)) d$angle <- num(raw[[an]])
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 10) stop("fewer than 10 numeric rows")
  attr(d, "record") <- rec
  d
}

sampling_rate <- function(time) {
  dt <- diff(time)
  dt <- dt[dt > 0]
  med <- stats::median(dt)
  unit <- "s"
  if (med >= 0.5) {  # a 1 Hz recording is implausible, so treat as milliseconds
    med <- med / 1000
    unit <- "ms"
  }
  list(fs = 1 / med, unit = unit, irregular = stats::sd(dt) / stats::median(dt) > 0.05)
}

# Key file: one row per record, read by column position:
#   1 record number (files are named with it), 2 participant ID, 3 group
#   (ACLR / Healthy), 4 injured or nondominant limb, 5 limb tested,
#   6 body mass (kg), 7 trial number (optional; defaults to 1)
KEY_COLS <- c("record", "participant_id", "group", "index_limb", "limb_tested", "body_mass_kg", "trial")

empty_key <- function() {
  data.frame(record = integer(), participant_id = character(), group = character(),
             index_limb = character(), limb_tested = character(), body_mass_kg = numeric(),
             trial = integer(), stringsAsFactors = FALSE)
}

read_key <- function(path, name) {
  ext <- tolower(tools::file_ext(name))
  rd <- function(header) {
    if (ext %in% c("xlsx", "xls")) {
      as.data.frame(readxl::read_excel(path, col_names = header))
    } else {
      utils::read.csv(path, header = header, check.names = FALSE, stringsAsFactors = FALSE,
                      strip.white = TRUE)
    }
  }
  k <- rd(TRUE)
  # no header row: the first "name" is a record number
  if (!is.na(suppressWarnings(as.integer(names(k)[1])))) k <- rd(FALSE)
  if (ncol(k) < 6) {
    stop("Key file needs at least 6 columns in this order: record, participant ID, group, ",
         "injured/nondominant limb, limb tested, body mass (trial number optional)")
  }
  k <- k[, seq_len(min(7, ncol(k))), drop = FALSE]
  if (ncol(k) == 6) k$trial <- 1
  names(k) <- KEY_COLS

  side <- function(x) {
    l <- toupper(substr(trimws(as.character(x)), 1, 1))
    l[!l %in% c("L", "R")] <- NA
    l
  }
  g <- toupper(trimws(as.character(k$group)))
  g <- ifelse(grepl("ACL|INJ", g) & !grepl("UNINJ", g), "ACLR",
              ifelse(grepl("HEAL|CON|CTRL|^HC|UNINJ", g), "Healthy", NA))
  out <- data.frame(record = suppressWarnings(as.integer(k$record)),
                    participant_id = trimws(as.character(k$participant_id)),
                    group = g, index_limb = side(k$index_limb), limb_tested = side(k$limb_tested),
                    body_mass_kg = suppressWarnings(as.numeric(k$body_mass_kg)),
                    trial = suppressWarnings(as.integer(k$trial)), stringsAsFactors = FALSE)
  out <- out[!is.na(out$record), , drop = FALSE]
  out$trial[is.na(out$trial)] <- 1L
  out$participant_id[out$participant_id == ""] <- NA
  if (anyDuplicated(out$record)) {
    stop("Duplicate record numbers in key file: ", paste(unique(out$record[duplicated(out$record)]), collapse = ", "))
  }
  bad <- out$record[is.na(out$participant_id) | is.na(out$group) | is.na(out$index_limb) |
                      is.na(out$limb_tested) | is.na(out$body_mass_kg)]
  if (length(bad)) {
    warning("Key records with missing or unrecognized values: ", paste(bad, collapse = ", "))
  }
  incons <- out %>% filter(!is.na(participant_id)) %>% group_by(participant_id) %>%
    summarise(n = n_distinct(index_limb, group), .groups = "drop") %>% filter(n > 1)
  if (nrow(incons)) {
    warning("Participants with different group or injured/nondominant limb across records: ",
            paste(incons$participant_id, collapse = ", "))
  }
  out
}

# Record number from a filename: the leading number ("12.csv", "12_isok60.csv",
# "rec12.txt")
parse_record <- function(name) {
  b <- tools::file_path_sans_ext(basename(name))
  m <- regmatches(b, regexec("^(?:[Rr][Ee][Cc](?:[Oo][Rr][Dd])?)?[ _#-]*([0-9]+)", b, perl = TRUE))[[1]]
  if (length(m) == 2) as.integer(m[2]) else NA_integer_
}

filename_speed <- function(name) {
  m <- regmatches(toupper(name), regexpr("[0-9]{2,3}(?=\\s*(DEG|DPS|D/S|D_S))", toupper(name), perl = TRUE))
  if (length(m)) as.numeric(m) else NA_real_
}

## ---- Signal processing ------------------------------------------------------
# Zero-lag Butterworth low-pass (forward-backward) with reflection padding
lowpass <- function(x, fs, cutoff, order = 2) {
  n <- length(x)
  bf <- signal::butter(order, cutoff / (fs / 2), type = "low")
  p <- min(n - 1, max(12, round(0.2 * fs)))
  xp <- c(2 * x[1] - x[(p + 1):2], x, 2 * x[n] - x[(n - 1):(n - p)])
  x0 <- xp[1]
  y <- as.numeric(signal::filter(bf, xp - x0))
  y <- rev(as.numeric(signal::filter(bf, rev(y - y[length(y)])))) + y[length(y)]
  y[(p + 1):(p + n)] + x0
}

effective_cutoff <- function(fs, cutoff) min(cutoff, 0.8 * fs / 2)

deriv1 <- function(x, fs) {
  n <- length(x)
  c(x[2] - x[1], (x[3:n] - x[1:(n - 2)]) / 2, x[n] - x[n - 1]) * fs
}

detect_task <- function(d, fs, p) {
  out <- list(task = "isometric", speed = NA_real_, speed_est = NA_real_)
  if (is.null(d$angle) || all(is.na(d$angle)) ||
      diff(range(d$angle, na.rm = TRUE)) < p$min_rom_deg) return(out)
  ang <- lowpass(d$angle, fs, min(p$vel_cutoff_hz, 0.4 * fs))
  v <- abs(deriv1(ang, fs))
  est <- stats::median(v[v > 0.5 * stats::quantile(v, 0.995)])
  out$task <- "isokinetic"
  out$speed_est <- est
  out$speed <- STD_SPEEDS[which.min(abs(STD_SPEEDS - est))]
  out
}

inspect_file <- function(path, name, p) {
  out <- list(name = name, status = "OK", note = "", fs = NA_real_,
              task = NA_character_, speed = NA_real_, record = parse_record(name))
  cols <- list(time = p$col_time, torque = p$col_torque, angle = p$col_angle)
  d <- tryCatch(read_torque_file(path, cols), error = function(e) e)
  if (inherits(d, "error")) {
    out$status <- "Rejected"
    out$note <- paste("Could not read:", conditionMessage(d))
    return(out)
  }
  notes <- character()
  rec <- attr(d, "record")
  if (!is.na(rec)) {
    if (!is.na(out$record) && out$record != rec) {
      notes <- c(notes, sprintf("filename says record %d, file header says %d (header used)", out$record, rec))
    }
    out$record <- rec
  }
  sr <- sampling_rate(d$time)
  if (sr$unit == "ms") d$time <- d$time / 1000
  out$data <- d
  out$fs <- round(sr$fs, 1)
  if (sr$unit == "ms") notes <- c(notes, "time column read as ms")
  if (sr$irregular) notes <- c(notes, "irregular time steps")
  if (out$fs < MIN_FS) {
    out$status <- "Rejected"
    notes <- c(notes, sprintf("sampling rate %.0f Hz is below the %d Hz minimum", out$fs, MIN_FS))
  }
  tk <- detect_task(d, out$fs, p)
  out$task <- tk$task
  out$speed <- tk$speed
  if (!is.na(tk$speed_est) && abs(tk$speed_est - tk$speed) / tk$speed > 0.15) {
    notes <- c(notes, sprintf("measured speed %.0f deg/s is >15%% from nominal", tk$speed_est))
  }
  fsp <- filename_speed(name)
  if (!is.na(fsp) && !is.na(tk$speed) && fsp != tk$speed) {
    notes <- c(notes, sprintf("filename says %g deg/s, data say %g deg/s", fsp, tk$speed))
  }
  if (!is.na(fsp) && tk$task == "isometric") notes <- c(notes, "filename has a speed but no movement was found")
  out$note <- paste(notes, collapse = "; ")
  out
}

## ---- Contraction detection and metrics --------------------------------------
add_flag <- function(old, new) ifelse(old == "" | is.na(old), new, paste(old, new, sep = "; "))

find_segments <- function(mask, fs, min_s, gap_s = 0.25) {
  r <- rle(mask)
  e <- cumsum(r$lengths)
  s <- e - r$lengths + 1
  seg <- data.frame(start = s[r$values], end = e[r$values])
  if (!nrow(seg)) return(seg)
  out <- seg[1, ]
  for (i in seq_len(nrow(seg))[-1]) {
    if ((seg$start[i] - out$end[nrow(out)]) / fs < gap_s) {
      out$end[nrow(out)] <- seg$end[i]
    } else {
      out <- rbind(out, seg[i, ])
    }
  }
  out[(out$end - out$start + 1) / fs >= min_s, , drop = FALSE]
}

# Baseline = latest window (closest to onset) whose SD is within 1.5x of the
# quietest window in the search region
quiet_baseline <- function(y, lo, hi, wn) {
  if (hi - lo + 1 < max(3, wn)) {
    seg <- y[lo:max(lo, hi)]
    return(list(mean = mean(seg), sd = if (length(seg) > 1) stats::sd(seg) else NA_real_, short = TRUE))
  }
  x <- y[lo:hi]
  cs <- cumsum(c(0, x))
  cs2 <- cumsum(c(0, x^2))
  i <- 1:(length(x) - wn + 1)
  m <- (cs[i + wn] - cs[i]) / wn
  v <- pmax((cs2[i + wn] - cs2[i]) / wn - m^2, 0)
  j <- max(which(v <= 2.25 * min(v)))
  list(mean = m[j], sd = sqrt(v[j] * wn / (wn - 1)), short = FALSE)
}

iso_metrics <- function(t, y, onset, end, baseline, p) {
  z <- y - baseline
  idx <- onset:end
  pk <- idx[which.max(z[idx])]
  t0 <- t[onset]
  at <- function(ms) {
    tt <- t0 + ms / 1000
    if (tt > t[end]) NA_real_ else stats::approx(t[idx], z[idx], tt)$y
  }
  T0 <- z[onset]
  out <- list(peak_idx = pk, peak_nm = z[pk], time_to_peak_ms = (t[pk] - t0) * 1000)
  for (w in p$rtd_windows_ms) out[[paste0("rtd_0_", w)]] <- (at(w) - T0) / (w / 1000)
  e <- p$rtd_epoch_ms
  out[[paste0("rtd_", e[1], "_", e[2])]] <- (at(e[2]) - at(e[1])) / ((e[2] - e[1]) / 1000)
  out
}

process_isometric <- function(t, tq, fs, p) {
  dsign <- if (abs(min(tq)) > max(tq)) -1 else 1
  y <- dsign * tq
  thr <- max(p$detect_nm, p$detect_frac * max(y))
  segs <- find_segments(y > thr, fs, p$min_contraction_s)
  if (!nrow(segs)) return(list(dsign = dsign, events = NULL))
  rest <- stats::median(y[y < 0.25 * thr])
  wn <- max(5, round(p$baseline_win_ms / 1000 * fs))
  prev_end <- 1
  rows <- vector("list", nrow(segs))
  for (k in seq_len(nrow(segs))) {
    s <- segs$start[k]
    lo <- max(prev_end, s - round(3 * fs))
    bl <- quiet_baseline(y, lo, s - 1, wn)
    z <- y - bl$mean
    on <- s
    while (on > lo && z[on - 1] >= p$onset_nm) on <- on - 1
    en <- segs$end[k]
    while (en < length(y) && z[en + 1] > p$onset_nm) en <- en + 1
    m <- iso_metrics(t, y, on, en, bl$mean, p)

    flags <- character()
    if (bl$short) flags <- c(flags, "short baseline")
    if (!is.na(bl$sd) && bl$sd > p$flag_baseline_sd) flags <- c(flags, "noisy baseline")
    pre <- max(lo, on - round(0.3 * fs)):on
    if (min(z[pre]) < -p$flag_cm_nm) flags <- c(flags, "countermovement")
    if (bl$mean - rest > p$flag_pretension_nm) flags <- c(flags, "pre-tension")
    if (t[en] - t[on] < max(p$rtd_windows_ms, p$rtd_epoch_ms) / 1000) {
      flags <- c(flags, "contraction shorter than RTD window")
    }
    rows[[k]] <- data.frame(direction = if (dsign == 1) "Extension" else "Flexion", rep = k,
                            onset_idx = on, end_idx = en, onset_s = t[on], end_s = t[en],
                            baseline_nm = bl$mean, baseline_sd = bl$sd,
                            flags = paste(flags, collapse = "; "),
                            as.data.frame(m, check.names = FALSE), check.names = FALSE)
    prev_end <- en
  }
  ev <- bind_rows(rows)
  ev$flags[ev$peak_nm < 0.5 * max(ev$peak_nm)] <- add_flag(ev$flags[ev$peak_nm < 0.5 * max(ev$peak_nm)], "peak <50% of best trial")
  list(dsign = dsign, events = ev)
}

process_isokinetic <- function(t, tq, ang, vel, fs, speed, p) {
  target <- if (is.na(speed)) stats::median(abs(vel)[abs(vel) > 10]) else speed
  moving <- abs(vel) > max(5, 0.2 * target)
  dirv <- sign(vel) * moving
  r <- rle(dirv)
  e <- cumsum(r$lengths)
  s <- e - r$lengths + 1
  keep <- r$values != 0
  seg <- data.frame(start = s[keep], end = e[keep], dv = r$values[keep])
  if (!nrow(seg)) return(NULL)
  # extend each rep outward to where the limb is essentially stopped
  for (k in seq_len(nrow(seg))) {
    while (seg$start[k] > 1 && sign(vel[seg$start[k] - 1]) == seg$dv[k] && abs(vel[seg$start[k] - 1]) > 2) {
      seg$start[k] <- seg$start[k] - 1
    }
    while (seg$end[k] < length(vel) && sign(vel[seg$end[k] + 1]) == seg$dv[k] && abs(vel[seg$end[k] + 1]) > 2) {
      seg$end[k] <- seg$end[k] + 1
    }
  }
  seg <- seg[abs(ang[seg$end] - ang[seg$start]) >= p$min_rom_deg, , drop = FALSE]
  if (!nrow(seg)) return(NULL)
  ext_dv <- if (p$ext_angle_decreasing) -1 else 1
  seg$direction <- ifelse(seg$dv == ext_dv, "Extension", "Flexion")
  seg$rep <- stats::ave(seq_len(nrow(seg)), seg$direction, FUN = seq_along)

  rows <- lapply(seq_len(nrow(seg)), function(k) {
    idx <- seg$start[k]:seg$end[k]
    y <- if (seg$direction[k] == "Extension") tq[idx] else -tq[idx]
    iso <- which(abs(abs(vel[idx]) - target) <= p$isovel_tol * target)
    flags <- character()
    use <- if (p$iso_peak_only) iso else seq_along(idx)
    if (length(use) < max(3, round(0.01 * fs))) {
      use <- seq_along(idx)
      flags <- c(flags, "no isovelocity window (peak from full rep)")
    }
    pk <- use[which.max(y[use])]
    dth <- abs(diff(ang[idx])) * pi / 180
    data.frame(direction = seg$direction[k], rep = seg$rep[k],
               onset_idx = idx[1], end_idx = idx[length(idx)], peak_idx = idx[pk],
               onset_s = t[idx[1]], end_s = t[idx[length(idx)]],
               peak_nm = y[pk], angle_at_peak = ang[idx[pk]],
               work_j = sum((y[-1] + y[-length(y)]) / 2 * dth),
               rom_deg = abs(ang[idx[length(idx)]] - ang[idx[1]]),
               iso_start_s = if (length(iso)) t[idx[min(iso)]] else NA_real_,
               iso_end_s = if (length(iso)) t[idx[max(iso)]] else NA_real_,
               iso_pct_of_rep = 100 * length(iso) / length(idx),
               mean_iso_vel = if (length(iso)) mean(abs(vel[idx[iso]])) else NA_real_,
               flags = paste(flags, collapse = "; "))
  })
  ev <- bind_rows(rows)
  for (dn in unique(ev$direction)) {
    i <- ev$direction == dn & ev$peak_nm < 0.5 * max(ev$peak_nm[ev$direction == dn])
    ev$flags[i] <- add_flag(ev$flags[i], "peak <50% of best rep")
  }
  ev
}

process_file <- function(f, task, speed, p) {
  d <- f$data
  fs <- f$fs
  t <- d$time
  fc <- effective_cutoff(fs, p$cutoff_hz)
  sgn <- if (p$flip_torque) -1 else 1
  tq <- sgn * lowpass(d$torque, fs, fc, p$filt_order)
  out <- list(file = f$name, t = t, raw = sgn * d$torque, tq = tq, fs = fs, task = task,
              speed = speed, cutoff = fc, dsign = 1, angle = NULL)
  if (task == "isometric") {
    r <- process_isometric(t, tq, fs, p)
    out$dsign <- r$dsign
    ev <- r$events
  } else {
    if (is.null(d$angle)) stop("isokinetic file has no angle column")
    ang <- lowpass(d$angle, fs, min(p$vel_cutoff_hz, 0.4 * fs))
    vel <- deriv1(ang, fs)
    out$angle <- ang
    ev <- process_isokinetic(t, tq, ang, vel, fs, speed, p)
  }
  if (is.null(ev) || !nrow(ev)) {
    out$events <- NULL
    return(out)
  }
  ev$peak_s <- t[ev$peak_idx]
  ev$file <- f$name
  ev$task <- task
  ev$speed <- if (task == "isometric") NA_real_ else speed
  ev$fs_hz <- fs
  ev$cutoff_hz <- fc
  ev$onset_manual <- FALSE
  ev$event_id <- paste(f$name, ev$direction, ev$rep, sep = " | ")
  if (fc < p$cutoff_hz) ev$flags <- add_flag(ev$flags, sprintf("cutoff reduced to %.0f Hz", fc))
  out$events <- ev
  out
}

## ---- Summaries --------------------------------------------------------------
summarise_group <- function(g, key, p) {
  if (key$task == "isometric") {
    rtd <- grep("^rtd_", names(g), value = TRUE)
    rtd <- rtd[vapply(rtd, function(cc) any(!is.na(g[[cc]])), logical(1))]
    vals <- c(n_trials = nrow(g), peak_nm = max(g$peak_nm), mean_peak_nm = mean(g$peak_nm),
              time_to_peak_ms = mean(g$time_to_peak_ms),
              vapply(rtd, function(cc) mean(g[[cc]], na.rm = TRUE), numeric(1)))
  } else {
    inc_avg <- if (p$exclude_rep1) g$rep != 1 else rep(TRUE, nrow(g))
    if (!any(inc_avg)) inc_avg <- rep(TRUE, nrow(g))
    inc_pk <- if (p$exclude_rep1_all) inc_avg else rep(TRUE, nrow(g))
    b <- which(inc_pk)[which.max(g$peak_nm[inc_pk])]
    vals <- c(n_reps = nrow(g), n_reps_averaged = sum(inc_avg),
              peak_nm = g$peak_nm[b], angle_at_peak_deg = g$angle_at_peak[b],
              avg_peak_nm = mean(g$peak_nm[inc_avg]),
              avg_angle_at_peak_deg = mean(g$angle_at_peak[inc_avg]),
              avg_work_j = mean(g$work_j[inc_avg]),
              total_work_j = sum(g$work_j[inc_pk]))
  }
  vals[is.nan(vals)] <- NA
  tibble(variable = names(vals), value = unname(vals))
}

var_units <- function(v) {
  case_when(
    grepl("_per_kg$", v) & grepl("^rtd", v) ~ "Nm/s/kg",
    grepl("_per_kg$", v) & grepl("work", v) ~ "J/kg",
    grepl("_per_kg$", v) ~ "Nm/kg",
    grepl("^rtd", v) ~ "Nm/s",
    grepl("work", v) ~ "J",
    grepl("_nm$", v) ~ "Nm",
    grepl("deg$", v) ~ "deg",
    grepl("_ms$", v) ~ "ms",
    TRUE ~ "count"
  )
}

role_label <- function(group, role) {
  ifelse(group == "ACLR", ifelse(role == "Index", "ACLR", "Uninvolved"),
         ifelse(role == "Index", "Nondominant", "Dominant"))
}

task_label_of <- function(task, speed) {
  ifelse(task == "isometric", "Isometric", paste0("Isokinetic ", speed, " deg/s"))
}

# Record info from the key joined onto the Files table, so every file shows
# whose data it is
KEY_INFO <- c("participant_id", "group", "limb_tested", "limb", "index_limb", "trial", "body_mass_kg")

fill_from_key <- function(a, key) {
  if (is.null(a)) return(NULL)
  a <- a[, setdiff(names(a), KEY_INFO), drop = FALSE]
  if (is.null(key)) key <- empty_key()
  a <- left_join(a, key, by = "record")
  a$limb <- ifelse(is.na(a$limb_tested) | is.na(a$index_limb), NA,
                   role_label(a$group, ifelse(a$limb_tested == a$index_limb, "Index", "Contralateral")))
  a[, c("file", "record", KEY_INFO, "fs_hz", "task", "speed_dps", "status", "note")]
}

# ev: contraction table; a: Files table with key info filled in
summarise_results <- function(ev, a, p) {
  ev <- ev %>%
    filter(!excluded) %>%
    inner_join(a %>% select(file, record, participant_id, group, index_limb, side = limb_tested,
                            key_trial = trial, body_mass_kg), by = "file") %>%
    filter(!is.na(participant_id), !is.na(side), !is.na(index_limb), !is.na(group)) %>%
    mutate(limb_role = ifelse(side == index_limb, "Index", "Contralateral"),
           task_label = task_label_of(task, speed),
           trial = if (isTRUE(p$trial_as_session)) as.character(key_trial) else "all")
  if (!nrow(ev)) return(NULL)

  ids <- c("participant_id", "group", "trial")
  mass <- ev %>% group_by(participant_id, trial, side) %>%
    summarise(body_mass_kg = mean(body_mass_kg),
              records = paste(sort(unique(record)), collapse = ", "), .groups = "drop")
  long <- ev %>%
    group_by(participant_id, group, trial, side, limb_role, task, task_label, direction) %>%
    group_modify(~ summarise_group(.x, .y, p)) %>%
    ungroup() %>%
    left_join(mass, by = c("participant_id", "trial", "side"))
  kg <- grepl("(_nm|_j)$|^rtd_", long$variable)
  long <- bind_rows(long, long[kg, ] %>% mutate(variable = paste0(variable, "_per_kg"),
                                                value = value / body_mass_kg)) %>%
    mutate(units = var_units(variable), limb = role_label(group, limb_role)) %>%
    select(all_of(ids), records, body_mass_kg, side, limb_role, limb, task_label, direction,
           variable, value, units) %>%
    arrange(participant_id, trial, task_label, direction, variable, desc(limb_role))

  lsi <- long %>%
    filter(!grepl("^n_|angle|time_to_peak|_per_kg$", variable)) %>%
    select(all_of(ids), task_label, direction, variable, units, limb_role, value) %>%
    pivot_wider(names_from = limb_role, values_from = value)
  for (cc in c("Index", "Contralateral")) if (!cc %in% names(lsi)) lsi[[cc]] <- NA_real_
  lsi <- lsi %>%
    mutate(lsi_pct = 100 * Index / Contralateral,
           lsi_definition = ifelse(group == "ACLR", "ACLR / uninvolved", "nondominant / dominant")) %>%
    rename(index_limb_value = Index, contralateral_limb_value = Contralateral)

  hq <- long %>%
    filter(variable %in% c("peak_nm", "avg_peak_nm", "mean_peak_nm")) %>%
    select(all_of(ids), side, limb_role, limb, task_label, variable, direction, value) %>%
    pivot_wider(names_from = direction, values_from = value)
  if (all(c("Extension", "Flexion") %in% names(hq))) {
    hq <- hq %>% mutate(hq_ratio = Flexion / Extension) %>% filter(!is.na(hq_ratio)) %>%
      rename(basis = variable, flexion_nm = Flexion, extension_nm = Extension)
  } else {
    hq <- NULL
  }

  clean <- function(x) gsub("_+$", "", gsub("[^A-Za-z0-9]+", "_", x))
  wide <- long %>%
    transmute(participant_id, group, trial,
              col = clean(paste(task_label, direction, variable, limb_role)), value) %>%
    pivot_wider(names_from = col, values_from = value)
  wide <- mass %>% group_by(participant_id, trial) %>%
    summarise(body_mass_kg = mean(body_mass_kg),
              records = paste(sort(as.integer(unlist(strsplit(records, ", ")))), collapse = ", "),
              .groups = "drop") %>%
    right_join(wide, by = c("participant_id", "trial")) %>%
    relocate(participant_id, group, trial, records, body_mass_kg)
  if (nrow(lsi)) {
    wide <- wide %>% left_join(
      lsi %>% transmute(participant_id, trial, col = clean(paste(task_label, direction, variable, "LSI")), value = lsi_pct) %>%
        pivot_wider(names_from = col, values_from = value), by = c("participant_id", "trial"))
  }
  if (!is.null(hq) && nrow(hq)) {
    wide <- wide %>% left_join(
      hq %>% transmute(participant_id, trial, col = clean(paste(task_label, "HQ", basis, limb_role)), value = hq_ratio) %>%
        pivot_wider(names_from = col, values_from = value), by = c("participant_id", "trial"))
  }
  list(long = long, lsi = lsi, hq = hq, wide = wide)
}

params_df <- function(p) {
  if (is.null(p)) return(data.frame())
  data.frame(parameter = names(p),
             value = vapply(p, function(x) paste(x, collapse = ", "), character(1)),
             row.names = NULL)
}

methods_text <- function(p, fs) {
  if (is.null(p)) return("Process files to generate a methods paragraph.")
  fs_txt <- if (length(fs)) paste(sort(unique(round(fs))), collapse = ", ") else "?"
  rtd_txt <- paste0("0-", p$rtd_windows_ms, collapse = ", ")
  paste0(
    "Torque-time data (sampled at ", fs_txt, " Hz; files sampled below ", MIN_FS,
    " Hz were excluded) were low-pass filtered with a zero-lag (forward-backward) Butterworth filter (",
    p$filt_order, "nd-order per pass, ", 2 * p$filt_order, "th-order overall) at ", p$cutoff_hz,
    " Hz. For isometric trials, the baseline was the mean torque of the ", p$baseline_win_ms,
    "-ms window preceding each contraction and was subtracted from the signal. Torque onset was the first sample at which baseline-corrected torque reached ",
    p$onset_nm, " Nm (White et al., 2024). Peak torque was the maximum baseline-corrected torque. RTD was calculated as the change in torque divided by time over ",
    rtd_txt, " ms after onset and over the ", p$rtd_epoch_ms[1], "-", p$rtd_epoch_ms[2],
    " ms epoch. Isokinetic repetitions were identified from angular velocity (angle filtered at ",
    p$vel_cutoff_hz, " Hz). Peak torque and angle at peak torque were taken from ",
    if (p$iso_peak_only) paste0("the isovelocity portion of each repetition (within ", 100 * p$isovel_tol, "% of the target velocity)") else "the full repetition",
    ". Work was the integral of torque over angular displacement for each repetition, and total work was the sum across repetitions",
    if (p$exclude_rep1_all) " excluding the first repetition" else "",
    ". Average peak torque was the mean across repetitions",
    if (p$exclude_rep1) ", excluding the first repetition" else "",
    ". Torque values were normalized to body mass. The hamstrings-to-quadriceps ratio was flexion divided by extension torque (peak and average peak). LSI was calculated as ACLR / uninvolved limb x 100 for ACLR participants and nondominant / dominant limb x 100 for healthy participants.",
    "\n\nReference: White MS, Graham MC, Janatova T, Hawk GS, Thompson KL, Noehren B. Effect of sampling rate, filtering, and torque onset detection on quadriceps rate of torque development and torque steadiness. Sensors. 2024;24(13):4250. doi:10.3390/s24134250"
  )
}

build_assign <- function(files, key, old = NULL) {
  if (!length(files)) return(NULL)
  a <- bind_rows(lapply(files, function(f) {
    data.frame(file = f$name, record = f$record, fs_hz = f$fs, task = f$task, speed_dps = f$speed,
               status = f$status, note = f$note, stringsAsFactors = FALSE)
  }))
  if (!is.null(old)) {  # keep manual edits
    m <- match(a$file, old$file)
    k <- !is.na(m)
    cols <- c("record", "task", "speed_dps")
    a[k, cols] <- old[m[k], cols]
  }
  fill_from_key(a, key)
}

## ---- Labeled copies of the raw files ----------------------------------------
labeled_name <- function(r) {
  role <- c(ACLR = "inv", Uninvolved = "uninv", Nondominant = "nondom", Dominant = "dom")[r$limb]
  task <- if (is.na(r$task)) "task" else if (r$task == "isometric") "isom" else paste0("isok", r$speed_dps)
  parts <- c(r$participant_id, r$group, paste0(r$limb_tested, "-", role), paste0("T", r$trial), task,
             sprintf("rec%03d", r$record))
  gsub("[^A-Za-z0-9_.-]+", "-", paste(ifelse(is.na(parts), "NA", parts), collapse = "_"))
}

labeled_header <- function(r) {
  task <- if (is.na(r$task)) "unknown" else task_label_of(r$task, r$speed_dps)
  paste0("# ", c(
    paste("Record:", r$record),
    paste("Participant ID:", r$participant_id),
    paste("Group:", r$group),
    sprintf("Limb tested: %s (%s)", r$limb_tested, r$limb),
    paste("Injured/nondominant limb:", r$index_limb),
    paste("Trial:", r$trial),
    paste("Body mass (kg):", r$body_mass_kg),
    paste("Task (detected):", task),
    paste("Sampling rate (Hz):", r$fs_hz),
    paste("Original file:", r$file),
    paste("Labeled:", format(Sys.time(), "%Y-%m-%d %H:%M"))
  ))
}

write_labeled <- function(f, r, dir) {
  path <- file.path(dir, paste0(labeled_name(r), ".csv"))
  i <- 2
  while (file.exists(path)) {
    path <- file.path(dir, paste0(labeled_name(r), "_", i, ".csv"))
    i <- i + 1
  }
  d <- f$data
  names(d) <- c("Time", "Torque", if (!is.null(d$angle)) "Angle")
  writeLines(labeled_header(r), path)
  suppressWarnings(utils::write.table(d, path, sep = ",", row.names = FALSE, append = TRUE))
  path
}

dt_table <- function(df, digits = 2, selection = "none", page = 25, ...) {
  if (is.null(df) || !nrow(df)) return(datatable(data.frame(Message = "No data yet"), rownames = FALSE, options = list(dom = "t")))
  num <- names(df)[vapply(df, function(x) is.numeric(x) && !is.integer(x), logical(1))]
  num <- setdiff(num, c("rep", "fs_hz", "speed_dps", "speed"))
  out <- datatable(df, rownames = FALSE, selection = selection, filter = "top",
                   options = list(pageLength = page, scrollX = TRUE), ...)
  if (length(num)) out <- formatRound(out, num, digits)
  out
}

## ---- UI ---------------------------------------------------------------------
num_in <- function(id, label, value, step = NULL, min = NA) numericInput(id, label, value, step = step, min = min)

ui <- page_navbar(
  title = "Dynamometer Processing",
  theme = bs_theme(version = 5, bootswatch = "flatly"),
  nav_panel(
    "1. Upload and assign",
    layout_sidebar(
      sidebar = sidebar(
        width = 340,
        fileInput("key_file", "Key file (.csv or .xlsx)", accept = c(".csv", ".xlsx", ".xls")),
        downloadLink("key_template", "Download key file template"),
        helpText("Columns in order: record, participant ID, group, injured/nondominant limb, limb tested, body mass (kg), trial. Name each torque file with its record number (e.g. 12.csv or 12_isok60.csv)."),
        checkboxInput("trial_as_session", "Trial numbers are separate sessions (summarize each trial separately)", FALSE),
        tags$hr(),
        accordion(
          open = FALSE,
          accordion_panel(
            "Column positions (files without column names)",
            helpText("Used only when a file has no row naming Time and Torque. Header text above the data is skipped automatically. Set these before uploading."),
            num_in("col_time", "Time column", DEFAULTS$col_time, 1, 1),
            num_in("col_torque", "Torque column", DEFAULTS$col_torque, 1, 1),
            num_in("col_angle", "Angle column (blank = none)", DEFAULTS$col_angle, 1, 1)
          )
        ),
        fileInput("torque_files", "Torque files", multiple = TRUE, accept = c(".csv", ".txt", ".tsv", ".dat")),
        actionButton("clear_files", "Clear all files", class = "btn-sm btn-outline-secondary"),
        tags$hr(),
        accordion(
          open = FALSE,
          accordion_panel(
            "Filtering and onset",
            num_in("cutoff_hz", "Low-pass cutoff (Hz)", DEFAULTS$cutoff_hz, 10, 1),
            num_in("filt_order", "Butterworth order per pass (dual-pass doubles it)", DEFAULTS$filt_order, 1, 1),
            num_in("onset_nm", "Onset threshold above baseline (Nm)", DEFAULTS$onset_nm, 0.1, 0),
            num_in("baseline_win_ms", "Baseline window (ms)", DEFAULTS$baseline_win_ms, 50, 20)
          ),
          accordion_panel(
            "Contraction detection",
            num_in("detect_nm", "Detection floor (Nm)", DEFAULTS$detect_nm, 1, 1),
            num_in("detect_pct", "Detection threshold (% of file max)", 100 * DEFAULTS$detect_frac, 5, 1),
            num_in("min_contraction_s", "Minimum contraction length (s)", DEFAULTS$min_contraction_s, 0.1, 0.05)
          ),
          accordion_panel(
            "RTD windows",
            textInput("rtd_windows", "From onset (ms)", paste(DEFAULTS$rtd_windows_ms, collapse = ", ")),
            textInput("rtd_epoch", "Epoch (start, end ms)", paste(DEFAULTS$rtd_epoch_ms, collapse = ", "))
          ),
          accordion_panel(
            "Isokinetic",
            num_in("isovel_tol", "Isovelocity tolerance (% of target)", 100 * DEFAULTS$isovel_tol, 1, 1),
            checkboxInput("iso_peak_only", "Peak torque from isovelocity window only", DEFAULTS$iso_peak_only),
            checkboxInput("exclude_rep1", "Exclude rep 1 from averages", DEFAULTS$exclude_rep1),
            checkboxInput("exclude_rep1_all", "Also exclude rep 1 from peak and total work", DEFAULTS$exclude_rep1_all),
            num_in("vel_cutoff_hz", "Angle filter for velocity (Hz)", DEFAULTS$vel_cutoff_hz, 1, 1),
            num_in("min_rom_deg", "Minimum rep ROM (deg)", DEFAULTS$min_rom_deg, 5, 1),
            checkboxInput("ext_angle_decreasing", "Angle decreases during extension", DEFAULTS$ext_angle_decreasing),
            checkboxInput("flip_torque", "Flip torque sign (extension negative in files)", DEFAULTS$flip_torque)
          ),
          accordion_panel(
            "QC flags",
            num_in("flag_baseline_sd", "Noisy baseline: SD above (Nm)", DEFAULTS$flag_baseline_sd, 0.1, 0),
            num_in("flag_cm_nm", "Countermovement: dip below baseline (Nm)", DEFAULTS$flag_cm_nm, 0.5, 0),
            num_in("flag_pretension_nm", "Pre-tension: baseline above rest (Nm)", DEFAULTS$flag_pretension_nm, 0.5, 0)
          )
        ),
        actionButton("process", "Process files", class = "btn-primary w-100 mt-2")
      ),
      card(card_header("Key file"), DTOutput("key_tbl"), max_height = "380px"),
      card(card_header(div(class = "d-flex justify-content-between align-items-center",
                           span("Files: participant info comes from the key by record number. Double-click record, task, or speed_dps to fix, then click Process."),
                           downloadButton("dl_labeled", "Download labeled files (.zip)", class = "btn-sm btn-outline-primary"))),
           DTOutput("assign_tbl"))
    )
  ),
  nav_panel(
    "2. QC",
    layout_sidebar(
      sidebar = sidebar(
        width = 320,
        selectInput("qc_file", "File", choices = NULL),
        div(class = "d-flex gap-2",
            actionButton("prev_file", "< Prev", class = "btn-sm"),
            actionButton("next_file", "Next >", class = "btn-sm")),
        checkboxInput("show_raw", "Show unfiltered torque", FALSE),
        tags$hr(),
        textInput("qc_reason", "Reason (saved to QC log)"),
        div(class = "d-flex gap-2",
            actionButton("exclude_sel", "Exclude selected", class = "btn-sm btn-warning"),
            actionButton("include_sel", "Include selected", class = "btn-sm btn-outline-secondary")),
        tags$hr(),
        checkboxInput("click_onset", "Click the plot to set onset (select one isometric trial first)", FALSE),
        actionButton("reset_onset", "Reset selected onset to automatic", class = "btn-sm btn-outline-secondary")
      ),
      card(full_screen = TRUE, plotlyOutput("qc_plot", height = "430px")),
      card(card_header("Contractions in this file (click rows to select)"), DTOutput("qc_tbl")),
      card(card_header("QC log"), DTOutput("audit_tbl"))
    )
  ),
  nav_panel(
    "3. Results",
    div(class = "mb-2", downloadButton("dl_xlsx", "Download Excel workbook", class = "btn-success")),
    navset_card_tab(
      nav_panel("LSI", DTOutput("lsi_tbl")),
      nav_panel("H:Q", DTOutput("hq_tbl")),
      nav_panel("Limb summary", DTOutput("long_tbl")),
      nav_panel("Participant (wide)", DTOutput("wide_tbl")),
      nav_panel("All contractions", DTOutput("events_tbl"))
    )
  ),
  nav_panel("Methods", card(card_header("Methods paragraph (reflects the parameters used for the last processing run)"),
                            uiOutput("methods_txt")))
)

## ---- Server -----------------------------------------------------------------
server <- function(input, output, session) {
  rv <- reactiveValues(
    files = list(), assign = NULL, key = NULL, proc = list(), params_used = NULL,
    excluded = character(), onset_override = list(),
    audit = data.frame(time = character(), file = character(), contraction = character(),
                       action = character(), detail = character(), reason = character())
  )

  log_action <- function(file, id, action, detail = "", reason = "") {
    rv$audit <- rbind(rv$audit, data.frame(time = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                                           file = file, contraction = id, action = action,
                                           detail = detail, reason = reason))
  }

  params <- reactive({
    nums <- function(x) {
      v <- suppressWarnings(as.numeric(strsplit(trimws(x), "[,; ]+")[[1]]))
      v[!is.na(v)]
    }
    list(cutoff_hz = input$cutoff_hz, filt_order = input$filt_order, onset_nm = input$onset_nm,
         baseline_win_ms = input$baseline_win_ms, detect_nm = input$detect_nm,
         detect_frac = input$detect_pct / 100, min_contraction_s = input$min_contraction_s,
         rtd_windows_ms = nums(input$rtd_windows), rtd_epoch_ms = nums(input$rtd_epoch),
         vel_cutoff_hz = input$vel_cutoff_hz, isovel_tol = input$isovel_tol / 100,
         min_rom_deg = input$min_rom_deg, iso_peak_only = input$iso_peak_only,
         exclude_rep1 = input$exclude_rep1, exclude_rep1_all = input$exclude_rep1_all,
         ext_angle_decreasing = input$ext_angle_decreasing, flip_torque = input$flip_torque,
         flag_baseline_sd = input$flag_baseline_sd, flag_cm_nm = input$flag_cm_nm,
         flag_pretension_nm = input$flag_pretension_nm,
         trial_as_session = input$trial_as_session,
         col_time = input$col_time, col_torque = input$col_torque,
         col_angle = if (is.null(input$col_angle) || is.na(input$col_angle)) NA else input$col_angle)
  })

  ## Key file
  output$key_template <- downloadHandler(
    filename = "dynamometer_key_template.csv",
    content = function(file) {
      utils::write.csv(data.frame(record = 1:4, participant_id = c("P001", "P001", "P002", "P002"),
                                  group = c("ACLR", "ACLR", "Healthy", "Healthy"),
                                  injured_or_nondom_limb = c("L", "L", "R", "R"),
                                  limb_tested = c("L", "R", "R", "L"),
                                  body_mass_kg = c(72.4, 72.4, 65.0, 65.0), trial = 1),
                       file, row.names = FALSE)
    }
  )

  observeEvent(input$key_file, {
    k <- withCallingHandlers(
      tryCatch(read_key(input$key_file$datapath, input$key_file$name),
               error = function(e) {
                 showNotification(conditionMessage(e), type = "error", duration = NULL)
                 NULL
               }),
      warning = function(w) {
        showNotification(conditionMessage(w), type = "warning", duration = NULL)
        invokeRestart("muffleWarning")
      })
    rv$key <- k
    if (!is.null(k)) rv$assign <- fill_from_key(rv$assign, k)
  })

  output$key_tbl <- renderDT(dt_table(rv$key, page = 10))

  ## Torque files
  observeEvent(input$torque_files, {
    f <- input$torque_files
    p <- params()
    fl <- rv$files
    withProgress(message = "Reading files", value = 0, {
      for (i in seq_len(nrow(f))) {
        incProgress(1 / nrow(f), detail = f$name[i])
        fl[[f$name[i]]] <- inspect_file(f$datapath[i], f$name[i], p)
      }
    })
    rv$files <- fl
    rv$assign <- build_assign(fl, rv$key, rv$assign)
    n_rej <- sum(rv$assign$status != "OK")
    if (n_rej) showNotification(sprintf("%d file(s) rejected; see the status column", n_rej), type = "warning")
  })

  observeEvent(input$clear_files, {
    rv$files <- list(); rv$assign <- NULL; rv$proc <- list(); rv$params_used <- NULL
    rv$excluded <- character(); rv$onset_override <- list()
  })

  output$assign_tbl <- renderDT({
    a <- rv$assign
    if (is.null(a)) return(dt_table(NULL))
    a$key_ok <- !is.na(a$participant_id)
    datatable(a, rownames = FALSE, selection = "none", filter = "top",
              editable = list(target = "cell",
                              disable = list(columns = which(!names(a) %in% c("record", "task", "speed_dps")) - 1)),
              options = list(pageLength = 50, scrollX = TRUE,
                             columnDefs = list(list(visible = FALSE, targets = ncol(a) - 1)))) %>%
      formatStyle("key_ok", target = "row", backgroundColor = styleEqual(FALSE, "#fff3cd")) %>%
      formatStyle("status", target = "row", backgroundColor = styleEqual("Rejected", "#f8d7da"))
  })

  observeEvent(input$assign_tbl_cell_edit, {
    a <- DT::editData(rv$assign, input$assign_tbl_cell_edit, rownames = FALSE)
    a$record <- suppressWarnings(as.integer(a$record))
    a$task <- tolower(trimws(a$task))
    a$task[!a$task %in% c("isometric", "isokinetic")] <- NA
    a <- fill_from_key(a, rv$key)
    if (!is.null(rv$key)) {
      unk <- !is.na(a$record) & !a$record %in% rv$key$record
      if (any(unk)) showNotification(paste("Record not in key file:", paste(unique(a$record[unk]), collapse = ", ")), type = "warning")
    }
    rv$assign <- a
  })

  output$dl_labeled <- downloadHandler(
    filename = function() paste0("labeled_files_", format(Sys.Date()), ".zip"),
    content = function(file) {
      a <- rv$assign
      req(a)
      a <- a[a$status == "OK" & !is.na(a$participant_id), , drop = FALSE]
      if (!nrow(a)) {
        showNotification("No readable files matched to a key record yet.", type = "warning")
        req(FALSE)
      }
      dir <- tempfile("labeled")
      dir.create(dir)
      paths <- vapply(seq_len(nrow(a)), function(i) write_labeled(rv$files[[a$file[i]]], a[i, ], dir), character(1))
      zip::zip(file, files = basename(paths), root = dir)
    }
  )

  ## Processing
  observeEvent(input$process, {
    a <- rv$assign
    req(a)
    p <- params()
    if (length(p$rtd_epoch_ms) != 2) {
      showNotification("RTD epoch needs two values, e.g. 40, 160", type = "error")
      return()
    }
    ok <- which(a$status == "OK" & !is.na(a$task))
    proc <- list()
    withProgress(message = "Processing", value = 0, {
      for (i in ok) {
        incProgress(1 / length(ok), detail = a$file[i])
        r <- tryCatch(process_file(rv$files[[a$file[i]]], a$task[i], a$speed_dps[i], p),
                      error = function(e) conditionMessage(e))
        if (is.character(r)) {
          a$note[i] <- add_flag(a$note[i], paste("processing failed:", r))
        } else {
          if (is.null(r$events)) a$note[i] <- add_flag(a$note[i], "no contractions detected")
          proc[[a$file[i]]] <- r
        }
      }
    })
    rv$assign <- a
    rv$proc <- proc
    rv$params_used <- p
    n_ev <- sum(vapply(proc, function(x) NROW(x$events), numeric(1)))
    showNotification(sprintf("Processed %d file(s): %d contractions", length(proc), n_ev), type = "message")
  })

  events <- reactive({
    if (!length(rv$proc)) return(NULL)
    p <- rv$params_used
    ev <- bind_rows(lapply(rv$proc, `[[`, "events"))
    if (!nrow(ev)) return(NULL)
    for (id in intersect(names(rv$onset_override), ev$event_id)) {
      i <- which(ev$event_id == id)
      pr <- rv$proc[[ev$file[i]]]
      on <- rv$onset_override[[id]]
      if (on >= ev$end_idx[i]) next
      m <- iso_metrics(pr$t, pr$dsign * pr$tq, on, ev$end_idx[i], ev$baseline_nm[i], p)
      for (nm in names(m)) ev[[nm]][i] <- m[[nm]]
      ev$onset_idx[i] <- on
      ev$onset_s[i] <- pr$t[on]
      ev$peak_s[i] <- pr$t[m$peak_idx]
      ev$onset_manual[i] <- TRUE
    }
    ev$excluded <- ev$event_id %in% rv$excluded
    ev
  })

  results <- reactive({
    ev <- events()
    validate(need(!is.null(ev), "Process files to see results."),
             need(!is.null(rv$key), "Upload a key file to see participant results."))
    # summary-only settings apply immediately, without reprocessing
    p <- modifyList(rv$params_used, list(trial_as_session = input$trial_as_session,
                                         exclude_rep1 = input$exclude_rep1,
                                         exclude_rep1_all = input$exclude_rep1_all))
    r <- summarise_results(ev, rv$assign, p)
    validate(need(!is.null(r), "No contractions matched a key record. Check the record column in the Files table."))
    r
  })

  ## QC
  observe({
    a <- rv$assign
    fs <- names(rv$proc)
    if (!length(fs)) {
      updateSelectInput(session, "qc_file", choices = character())
      return()
    }
    ev <- isolate(events())
    m <- match(fs, a$file)
    nflag <- vapply(fs, function(f) {
      e <- rv$proc[[f]]$events
      if (is.null(e)) 0 else sum(e$flags != "")
    }, numeric(1))
    lab <- paste0("#", a$record[m], " ", a$participant_id[m], " ", a$limb_tested[m], " (", a$limb[m], ") T",
                  a$trial[m], ", ", task_label_of(a$task[m], a$speed_dps[m]), "  [", fs, "]",
                  ifelse(nflag > 0, paste0("  flags: ", nflag), ""))
    sel <- isolate(input$qc_file)
    updateSelectInput(session, "qc_file", choices = setNames(fs, lab),
                      selected = if (!is.null(sel) && sel %in% fs) sel else fs[1])
  })

  step_file <- function(d) {
    fs <- names(rv$proc)
    req(length(fs))
    i <- match(input$qc_file, fs)
    i <- if (is.na(i)) 1 else ((i - 1 + d) %% length(fs)) + 1
    updateSelectInput(session, "qc_file", selected = fs[i])
  }
  observeEvent(input$prev_file, step_file(-1))
  observeEvent(input$next_file, step_file(1))

  qc_events <- reactive({
    ev <- events()
    req(ev, input$qc_file)
    ev[ev$file == input$qc_file, , drop = FALSE]
  })

  selected_ids <- reactive({
    e <- qc_events()
    s <- input$qc_tbl_rows_selected
    if (is.null(s)) character() else e$event_id[s]
  })

  output$qc_tbl <- renderDT({
    e <- qc_events()
    cols <- if (all(e$task == "isometric")) {
      c("direction", "rep", "onset_s", "peak_nm", "time_to_peak_ms", grep("^rtd_", names(e), value = TRUE),
        "baseline_nm", "baseline_sd", "onset_manual", "excluded", "flags")
    } else {
      c("direction", "rep", "onset_s", "end_s", "peak_nm", "angle_at_peak", "work_j", "rom_deg",
        "iso_pct_of_rep", "mean_iso_vel", "excluded", "flags")
    }
    cols <- intersect(cols, names(e))
    dt_table(e[, cols, drop = FALSE], selection = "multiple", page = 15) %>%
      formatStyle("excluded", target = "row", color = styleEqual(TRUE, "#999999"))
  })

  output$qc_plot <- renderPlotly({
    req(input$qc_file)
    pr <- rv$proc[[input$qc_file]]
    req(pr)
    e <- qc_events()
    step <- max(1, floor(length(pr$t) / 30000))
    ii <- seq(1, length(pr$t), by = step)
    plt <- plot_ly(source = "qc_plot")
    if (isTRUE(input$show_raw)) {
      plt <- add_trace(plt, x = pr$t[ii], y = pr$raw[ii], type = "scattergl", mode = "lines",
                       name = "Unfiltered", line = list(color = "rgba(150,150,150,0.6)", width = 1))
    }
    plt <- add_trace(plt, x = pr$t[ii], y = pr$tq[ii], type = "scattergl", mode = "lines",
                     name = sprintf("Torque (%.0f Hz low-pass)", pr$cutoff),
                     line = list(color = "#1f4e79", width = 1.5))
    shapes <- list()
    if (!is.null(pr$angle)) {
      plt <- add_trace(plt, x = pr$t[ii], y = pr$angle[ii], type = "scattergl", mode = "lines",
                       name = "Angle", yaxis = "y2", line = list(color = "#c9a227", width = 1, dash = "dot"))
    }
    if (nrow(e)) {
      inc <- !e$excluded
      plt <- add_trace(plt, x = e$onset_s, y = pr$tq[e$onset_idx], type = "scatter", mode = "markers",
                       name = ifelse(e$task[1] == "isometric", "Onset", "Rep start"),
                       marker = list(color = ifelse(inc, ifelse(e$onset_manual, "#e67e22", "#27ae60"), "#bbbbbb"), size = 9),
                       text = paste(e$direction, "rep", e$rep), hoverinfo = "text+x")
      plt <- add_trace(plt, x = e$peak_s, y = pr$tq[e$peak_idx], type = "scatter", mode = "markers",
                       name = "Peak", marker = list(color = ifelse(inc, "#c0392b", "#bbbbbb"), size = 9, symbol = "diamond"),
                       text = paste(e$direction, "rep", e$rep, sprintf("%.1f Nm", e$peak_nm)), hoverinfo = "text")
      for (k in seq_len(nrow(e))) {
        if (e$task[k] == "isometric") {
          x1 <- e$onset_s[k] + max(rv$params_used$rtd_windows_ms, rv$params_used$rtd_epoch_ms) / 1000
          shapes[[length(shapes) + 1]] <- list(type = "rect", xref = "x", yref = "paper", x0 = e$onset_s[k], x1 = x1,
                                               y0 = 0, y1 = 1, fillcolor = "rgba(39,174,96,0.12)", line = list(width = 0))
        } else if (!is.na(e$iso_start_s[k])) {
          col <- if (e$excluded[k]) "rgba(150,150,150,0.12)" else if (e$direction[k] == "Extension") "rgba(31,78,121,0.10)" else "rgba(192,57,43,0.10)"
          shapes[[length(shapes) + 1]] <- list(type = "rect", xref = "x", yref = "paper", x0 = e$iso_start_s[k], x1 = e$iso_end_s[k],
                                               y0 = 0, y1 = 1, fillcolor = col, line = list(width = 0))
        }
      }
    }
    r <- rv$assign[rv$assign$file == input$qc_file, ]
    ttl <- sprintf("Record %s | %s | %s | %s limb (%s) | Trial %s | %s", r$record, r$participant_id, r$group,
                   r$limb_tested, r$limb, r$trial, task_label_of(r$task, r$speed_dps))
    plt %>%
      layout(title = list(text = ttl, font = list(size = 14), x = 0.01),
             margin = list(t = 50),
             xaxis = list(title = "Time (s)"), yaxis = list(title = "Torque (Nm)"),
             yaxis2 = list(title = "Angle (deg)", overlaying = "y", side = "right", showgrid = FALSE),
             shapes = shapes, legend = list(orientation = "h", y = -0.2),
             uirevision = input$qc_file) %>%
      event_register("plotly_click")
  })

  observeEvent(suppressWarnings(event_data("plotly_click", source = "qc_plot")), {
    if (!isTRUE(input$click_onset)) return()
    cl <- suppressWarnings(event_data("plotly_click", source = "qc_plot"))
    ids <- selected_ids()
    e <- qc_events()
    if (length(ids) != 1 || e$task[e$event_id == ids] != "isometric") {
      showNotification("Select exactly one isometric trial in the table first.", type = "warning")
      return()
    }
    row <- e[e$event_id == ids, ]
    pr <- rv$proc[[row$file]]
    idx <- which.min(abs(pr$t - cl$x[1]))
    if (idx >= row$end_idx - round(0.05 * pr$fs)) {
      showNotification("Onset must be before the end of the contraction.", type = "warning")
      return()
    }
    ov <- rv$onset_override
    ov[[ids]] <- idx
    rv$onset_override <- ov
    log_action(row$file, ids, "manual onset", sprintf("%.4f s -> %.4f s", row$onset_s, pr$t[idx]), input$qc_reason)
  })

  observeEvent(input$reset_onset, {
    ids <- intersect(selected_ids(), names(rv$onset_override))
    if (!length(ids)) return()
    ov <- rv$onset_override
    ov[ids] <- NULL
    rv$onset_override <- ov
    for (id in ids) log_action(input$qc_file, id, "onset reset to automatic", "", input$qc_reason)
  })

  observeEvent(input$exclude_sel, {
    ids <- setdiff(selected_ids(), rv$excluded)
    if (!length(ids)) return()
    if (!nzchar(trimws(input$qc_reason))) showNotification("Tip: add a reason so the QC log is complete.", type = "warning")
    rv$excluded <- c(rv$excluded, ids)
    for (id in ids) log_action(input$qc_file, id, "excluded", "", input$qc_reason)
  })

  observeEvent(input$include_sel, {
    ids <- intersect(selected_ids(), rv$excluded)
    if (!length(ids)) return()
    rv$excluded <- setdiff(rv$excluded, ids)
    for (id in ids) log_action(input$qc_file, id, "re-included", "", input$qc_reason)
  })

  output$audit_tbl <- renderDT(dt_table(rv$audit, page = 10))

  ## Results
  output$lsi_tbl <- renderDT(dt_table(results()$lsi))
  output$hq_tbl <- renderDT(dt_table(results()$hq, digits = 3))
  output$long_tbl <- renderDT(dt_table(results()$long))
  output$wide_tbl <- renderDT(dt_table(results()$wide))

  events_export <- reactive({
    ev <- events()
    req(ev)
    ev %>%
      left_join(rv$assign %>% select(file, record, participant_id, group, limb_tested, limb, trial), by = "file") %>%
      select(record, participant_id, group, limb_tested, limb, trial, file, task, speed, direction, rep,
             excluded, onset_manual,
             onset_s, peak_s, end_s, peak_nm, any_of("time_to_peak_ms"), starts_with("rtd_"),
             any_of(c("angle_at_peak", "work_j", "rom_deg", "iso_start_s", "iso_end_s",
                      "iso_pct_of_rep", "mean_iso_vel", "baseline_nm", "baseline_sd")),
             fs_hz, cutoff_hz, flags)
  })
  output$events_tbl <- renderDT(dt_table(events_export()))

  output$dl_xlsx <- downloadHandler(
    filename = function() paste0("dynamometer_results_", format(Sys.Date()), ".xlsx"),
    content = function(file) {
      r <- results()
      sheets <- list(Participant_wide = r$wide, LSI = r$lsi, HQ = r$hq, Limb_summary = r$long,
                     Contractions = events_export(), Files = rv$assign, Key = rv$key,
                     Parameters = params_df(rv$params_used), QC_log = rv$audit,
                     Methods = data.frame(text = methods_text(rv$params_used, rv$assign$fs_hz[rv$assign$file %in% names(rv$proc)])))
      sheets <- Filter(function(x) !is.null(x), sheets)
      openxlsx::write.xlsx(sheets, file, overwrite = TRUE)
    }
  )

  output$methods_txt <- renderUI({
    fs <- rv$assign$fs_hz[rv$assign$file %in% names(rv$proc)]
    txt <- strsplit(methods_text(rv$params_used, fs), "\n\n")[[1]]
    tagList(lapply(txt, tags$p))
  })
}

if (!isTRUE(getOption("dyno.no_run"))) shinyApp(ui, server)
