# Fase 2 · Chuva média diária na bacia (MERGE/CPTEC) de 1998 até a véspera
# do início da série operacional (data/chuva_bacia_merge.csv, desde 2026-07-01).
#
# Baixa um ano por vez em paralelo para uma pasta temporária, calcula a média
# ponderada no polígono da bacia e apaga os arquivos. Retomável: anos já
# presentes no CSV de saída são pulados.
#
# Uso: Rscript fase2/01_chuva_merge_historico.R [ano_inicial] [ano_final]

suppressPackageStartupMessages({
  library(dplyr)
})
source("R/fontes_bacia.R")

SAIDA <- "data/historico/chuva_bacia_merge_historico.csv"
FIM_HISTORICO <- as.Date("2026-06-30")

args <- commandArgs(trailingOnly = TRUE)
ano_ini <- if (length(args) >= 1) as.integer(args[1]) else 1998L
ano_fim <- if (length(args) >= 2) as.integer(args[2]) else 2026L

bacia <- terra::vect(BACIA_GEOJSON)
pasta <- file.path(tempdir(), "merge_hist")
dir.create(pasta, showWarnings = FALSE)

feitos <- if (file.exists(SAIDA)) read.csv(SAIDA) |> mutate(data = as.Date(data)) else NULL

media_bacia <- function(arq, d) {
  r <- terra::rast(arq)[[1]]
  r <- terra::crop(r, bacia, snap = "out")
  ex <- suppressWarnings(terra::extract(r, bacia, exact = TRUE))
  tibble(data = d,
         chuva_media = round(stats::weighted.mean(ex[[2]], ex$fraction, na.rm = TRUE), 2),
         chuva_max = round(max(ex[[2]], na.rm = TRUE), 1))
}

for (ano in ano_ini:ano_fim) {
  dias <- seq(as.Date(sprintf("%d-01-01", ano)), min(as.Date(sprintf("%d-12-31", ano)), FIM_HISTORICO), by = 1)
  if (!is.null(feitos)) dias <- dias[!dias %in% feitos$data]
  if (length(dias) == 0) { message(ano, ": já feito"); next }

  t0 <- Sys.time()
  arqs <- file.path(pasta, basename(url_merge(dias)))
  reqs <- lapply(dias, \(d) httr2::request(url_merge(d)) |> httr2::req_timeout(120) |> httr2::req_retry(max_tries = 3))
  resps <- httr2::req_perform_parallel(reqs, paths = arqs, on_error = "continue", max_active = 8, progress = FALSE)
  ok <- vapply(resps, \(r) inherits(r, "httr2_response") && httr2::resp_status(r) == 200, logical(1))

  res <- bind_rows(lapply(which(ok), \(i) tryCatch(media_bacia(arqs[i], dias[i]), error = \(e) NULL)))
  unlink(arqs)

  if (nrow(res) > 0) {
    write.table(res, SAIDA, sep = ",", row.names = FALSE,
                col.names = !file.exists(SAIDA), append = file.exists(SAIDA))
  }
  message(sprintf("%d: %d/%d dias (%.0f s)", ano, nrow(res), length(dias),
                  as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}

# ordena e remove duplicatas no final
if (file.exists(SAIDA)) {
  read.csv(SAIDA) |> distinct(data, .keep_all = TRUE) |> arrange(data) |> write.csv(SAIDA, row.names = FALSE)
}
