# Modelo de previsão de afluência da UHE Pedra (fase 2).
#
# Floresta aleatória com regressão quantílica (ranger, quantreg = TRUE), um
# modelo por horizonte h = 1..7 dias. Alvo: log1p(afluência diária).
#
# Dia de referência t = último dia completo (afluência da CHESF de t já
# publicada; chuva MERGE do arquivo t = 09h de t−1 às 09h de t).
# Preditores:
#   - afluência em t e t−1 e máximo dos últimos 7 dias
#   - vazão em Lagoa do Tamburi / Montante 1 em t e t−1 (rio a montante)
#   - chuva observada na bacia: dia t e acumulados de 3, 7, 15 e 30 dias
#     (os acumulados longos funcionam como umidade do solo)
#   - chuva "futura" de t+1 a t+h: total, últimos 2 dias e máximo diário
#     (no treino = chuva observada; na operação = cada cenário da previsão)
#   - época do ano (seno/cosseno do dia do ano)
#
# Requer: dplyr, ranger

HORIZONTES <- 1:7

soma_janela <- function(x, n) {  # soma de x[t-n+1..t]
  as.numeric(stats::filter(x, rep(1, n), sides = 1))
}

# Base diária contínua com as séries alinhadas
montar_base <- function(chuva, afluencia, montante) {
  dias <- tibble::tibble(data = seq(min(chuva$data), max(c(chuva$data, afluencia$data)), by = 1))
  dias |>
    dplyr::left_join(chuva |> dplyr::select(data, chuva = chuva_media), by = "data") |>
    dplyr::left_join(afluencia |> dplyr::select(data, afl), by = "data") |>
    dplyr::left_join(montante |> dplyr::select(data, montante = vazao), by = "data") |>
    dplyr::arrange(data)
}

# Preditores observados no dia de referência t (independem do horizonte)
preditores_base <- function(b) {
  b |>
    dplyr::mutate(
      afl0 = afl, afl1 = dplyr::lag(afl),
      afl_max7 = zoo::rollapplyr(afl, 7, max, na.rm = TRUE, fill = NA, partial = TRUE),
      mont0 = montante, mont1 = dplyr::lag(montante),
      chuva0 = chuva,
      chuva_ant3 = soma_janela(chuva, 3), chuva_ant7 = soma_janela(chuva, 7),
      chuva_ant15 = soma_janela(chuva, 15), chuva_ant30 = soma_janela(chuva, 30),
      doy_sin = sin(2 * pi * as.numeric(format(data, "%j")) / 365.25),
      doy_cos = cos(2 * pi * as.numeric(format(data, "%j")) / 365.25),
      afl_max7 = ifelse(is.finite(afl_max7), afl_max7, NA)
    )
}

# Acrescenta chuva futura (t+1..t+h) a partir de um vetor de chuva diária
preditores_futuros <- function(chuva_futura_mat, h) {
  # chuva_futura_mat: matriz [linhas, 7] com chuva de t+1..t+7
  janela <- chuva_futura_mat[, seq_len(h), drop = FALSE]
  data.frame(
    fut_total = rowSums(janela),
    fut_ult2 = rowSums(janela[, max(1, h - 1):h, drop = FALSE]),
    fut_max = apply(janela, 1, max)
  )
}

PREDITORES <- c("afl0", "afl1", "afl_max7", "mont0", "mont1",
                "chuva0", "chuva_ant3", "chuva_ant7", "chuva_ant15", "chuva_ant30",
                "fut_total", "fut_ult2", "fut_max", "doy_sin", "doy_cos")

# Tabela de treino para o horizonte h (chuva futura = observada)
tabela_horizonte <- function(pb, h) {
  fut <- sapply(1:7, function(k) dplyr::lead(pb$chuva, k))
  cbind(pb, preditores_futuros(fut, h)) |>
    dplyr::mutate(alvo = dplyr::lead(afl, h))
}

treinar_modelos <- function(pb, ate = NULL, num_trees = 500, seed = 42) {
  lapply(HORIZONTES, function(h) {
    tb <- tabela_horizonte(pb, h)
    if (!is.null(ate)) tb <- tb[tb$data <= ate, ]
    tb <- tb[stats::complete.cases(tb[, c(PREDITORES, "alvo")]), ]
    tb$y <- log1p(pmax(tb$alvo, 0))
    ranger::ranger(
      x = tb[, PREDITORES], y = tb$y,
      num.trees = num_trees, min.node.size = 5, quantreg = TRUE,
      importance = "permutation", seed = seed
    )
  })
}

prever_quantis <- function(modelo, novos, q = c(0.1, 0.5, 0.9)) {
  p <- stats::predict(modelo, data = novos[, PREDITORES], type = "quantiles", quantiles = q)$predictions
  colnames(p) <- paste0("q", q * 100)
  pmax(expm1(p), 0)
}
