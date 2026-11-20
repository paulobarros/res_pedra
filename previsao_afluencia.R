# Previsão de afluência da UHE Pedra para os próximos 7 dias (fase 2).
#
# Roda depois de coleta_bacia.R. Só refaz a previsão quando há uma previsão de
# chuva nova (a cada ~6 h). Para cada um dos ~122 cenários de chuva, o modelo
# devolve uma faixa de quantis; juntando todos, saem a faixa final
# (P10/P50/P90) e a chance de a afluência passar de 300 m³/s, que combinam a
# incerteza da chuva e a do próprio modelo.
#
# Uso: Rscript previsao_afluencia.R [--forcar]

suppressPackageStartupMessages({
  library(dplyr)
})
source("R/modelo_afluencia.R")

ARQ_MEMBROS <- "data/previsao_chuva_membros.csv"
ARQ_SAIDA   <- "data/previsao_afluencia.csv"
ARQ_HIST    <- "data/previsao_afluencia_historico.csv"
LIMIAR_CHEIA <- 300          # m³/s
QUANTIS <- seq(0.05, 0.95, by = 0.05)

forcar <- "--forcar" %in% commandArgs(trailingOnly = TRUE)
hoje <- as.Date(format(Sys.time(), "%Y-%m-%d", tz = "America/Bahia"))

if (!file.exists(ARQ_MEMBROS)) { message("sem previsão de chuva por cenário; nada a fazer"); quit(save = "no") }
membros <- read.csv(ARQ_MEMBROS) |> mutate(dia = as.Date(dia))
emitido_chuva <- membros$emitido_em[1]

if (!forcar && file.exists(ARQ_SAIDA) &&
    identical(read.csv(ARQ_SAIDA)$chuva_emitida_em[1], emitido_chuva)) {
  message("previsão de afluência já feita para a chuva emitida em ", emitido_chuva)
  quit(save = "no")
}

# ---- Base e modelos -----------------------------------------------------------
t0 <- Sys.time()
base <- carregar_base_modelo()
pb <- base$pb
modelos <- treinar_modelos(pb, num_trees = 300)
message(sprintf("modelos treinados em %.0f s", as.numeric(difftime(Sys.time(), t0, units = "secs"))))

# ---- Dia de referência t ------------------------------------------------------
# último dia até ontem com afluência e chuva observada
ref <- pb |> filter(data <= hoje - 1, !is.na(afl0), !is.na(chuva0)) |> slice_max(data, n = 1)
t_ref <- ref$data
# rio a montante: se faltar no dia (ANA fora), usa o último valor dos 3 dias anteriores
if (is.na(ref$mont0)) {
  ult <- pb |> filter(data <= t_ref, data >= t_ref - 3, !is.na(montante)) |> slice_max(data, n = 1)
  ref$mont0 <- if (nrow(ult)) ult$montante else ref$afl0
}
if (is.na(ref$mont1)) ref$mont1 <- ref$mont0
if (is.na(ref$afl1)) ref$afl1 <- ref$afl0
message("dia de referência: ", t_ref)

# ---- Chuva t+1..t+7 por cenário: observada (MERGE) onde já existe, prevista no resto
obs <- base$chuva |> select(data, chuva_media)
datas_fut <- t_ref + 1:7
cenarios <- membros |> distinct(modelo, membro)

mat_cenario <- function(mod, mem) {
  prev <- membros |> filter(modelo == mod, membro == mem) |> select(dia, chuva)
  vapply(datas_fut, function(d) {
    o <- obs$chuva_media[obs$data == d]
    if (length(o) && !is.na(o)) return(o)
    p <- prev$chuva[prev$dia == d]
    if (length(p)) p else NA_real_
  }, numeric(1))
}
chuva_fut <- t(mapply(mat_cenario, cenarios$modelo, cenarios$membro))   # [cenários, 7]

# ---- Previsão por horizonte ---------------------------------------------------
res <- bind_rows(lapply(HORIZONTES, function(h) {
  ok <- stats::complete.cases(chuva_fut[, seq_len(h), drop = FALSE])
  if (!any(ok)) return(NULL)
  novos <- cbind(ref[rep(1, sum(ok)), ], preditores_futuros(chuva_fut[ok, , drop = FALSE], h))
  q <- prever_quantis(modelos[[h]], novos, QUANTIS)          # [cenários, quantis]
  valores <- as.vector(q)                                    # mistura cenários × quantis
  tibble(
    data_alvo = t_ref + h, h = h, cenarios = sum(ok),
    p10 = stats::quantile(valores, 0.10), p50 = stats::quantile(valores, 0.50),
    p90 = stats::quantile(valores, 0.90),
    prob_cheia = mean(valores > LIMIAR_CHEIA),
    chuva_p50 = stats::median(rowSums(chuva_fut[ok, seq_len(h), drop = FALSE]))
  )
})) |>
  mutate(across(c(p10, p50, p90, chuva_p50), \(x) round(x, 1)), prob_cheia = round(prob_cheia, 3),
         emitido_em = format(Sys.time(), "%Y-%m-%d %H:%M", tz = "America/Bahia"),
         chuva_emitida_em = emitido_chuva, data_ref = t_ref, afl_ref = ref$afl0,
         .before = 1)

write.csv(res, ARQ_SAIDA, row.names = FALSE)
write.table(res, ARQ_HIST, sep = ",", row.names = FALSE,
            col.names = !file.exists(ARQ_HIST), append = file.exists(ARQ_HIST))
print(as.data.frame(res |> select(data_alvo, h, cenarios, p10, p50, p90, prob_cheia, chuva_p50)))
