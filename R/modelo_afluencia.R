# Modelo de previsão de afluência da UHE Pedra (fase 2).
#
# Floresta aleatória com regressão quantílica (ranger, quantreg = TRUE), um
# modelo por horizonte h = 1..7 dias. Alvo: afluência diária (m³/s).
#
# Alvo "híbrido": afluência da barragem reconstruída por balanço hídrico
# (2012 em diante) + vazão de Lagoa do Tamburi nos anos anteriores (1998–2012).
# Sem os anos de Tamburi o modelo quase não vê cheias (2012–2021 foi seco) e
# não aprende a prevê-las; com eles, o cenário alto (P90) acerta ~70% dos dias
# de cheia no teste 2021–2026 (ver fase2/resultados).
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

# Alvo híbrido: barragem (balanço SAR+Jequié, completado pela CHESF) e,
# antes disso, Tamburi
alvo_hibrido <- function(reconstruida, chesf, tamburi) {
  barragem <- dplyr::bind_rows(reconstruida, chesf) |>
    dplyr::filter(!is.na(afl)) |>
    dplyr::mutate(afl = pmax(afl, 0)) |>
    dplyr::distinct(data, .keep_all = TRUE)
  inicio <- min(barragem$data)
  dplyr::bind_rows(barragem, tamburi |> dplyr::filter(data < inicio, !is.na(vazao)) |>
                     dplyr::transmute(data, afl = vazao)) |>
    dplyr::arrange(data)
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
      afl_max7 = zoo::rollapplyr(afl, 7, \(x) if (all(is.na(x))) NA_real_ else max(x, na.rm = TRUE),
                                 fill = NA, partial = TRUE),
      mont0 = montante, mont1 = dplyr::lag(montante),
      chuva0 = chuva,
      chuva_ant3 = soma_janela(chuva, 3), chuva_ant7 = soma_janela(chuva, 7),
      chuva_ant15 = soma_janela(chuva, 15), chuva_ant30 = soma_janela(chuva, 30),
      doy_sin = sin(2 * pi * as.numeric(format(data, "%j")) / 365.25),
      doy_cos = cos(2 * pi * as.numeric(format(data, "%j")) / 365.25)
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
    ranger::ranger(
      x = tb[, PREDITORES], y = pmax(tb$alvo, 0),
      num.trees = num_trees, min.node.size = 5, quantreg = TRUE,
      importance = "permutation", seed = seed
    )
  })
}

prever_quantis <- function(modelo, novos, q = c(0.1, 0.5, 0.9)) {
  p <- stats::predict(modelo, data = novos[, PREDITORES], type = "quantiles", quantiles = q)$predictions
  if (!is.matrix(p)) p <- matrix(p, nrow = 1)
  colnames(p) <- paste0("q", q * 100)
  pmax(p, 0)
}

# Carrega as séries do repositório e devolve a base de preditores
carregar_base_modelo <- function() {
  chuva <- dplyr::bind_rows(
    utils::read.csv("data/historico/chuva_bacia_merge_historico.csv"),
    utils::read.csv("data/chuva_bacia_merge.csv")
  ) |> dplyr::mutate(data = as.Date(data)) |> dplyr::distinct(data, .keep_all = TRUE)

  rec <- utils::read.csv("data/historico/afluencia_pedra_reconstruida.csv") |>
    dplyr::transmute(data = as.Date(data), afl = afluencia_rec)
  chesf <- utils::read.csv("data/pedra_dados.csv") |>
    dplyr::transmute(data = as.Date(data), afl = afluencia)
  tamburi <- utils::read.csv("data/historico/vazoes_diarias_ana.csv", colClasses = c(codigo = "character")) |>
    dplyr::filter(codigo == "52405000") |> dplyr::transmute(data = as.Date(data), vazao)

  # rio a montante: série histórica de Tamburi + telemetria da Montante 1
  # (mesmo ponto do rio) em média diária
  tel <- if (file.exists("data/telemetria_montante.csv")) {
    utils::read.csv("data/telemetria_montante.csv", colClasses = c(codigo = "character")) |>
      dplyr::filter(codigo == "52405100", !is.na(vazao)) |>
      dplyr::mutate(data = as.Date(substr(data_hora, 1, 10))) |>
      dplyr::summarise(vazao = mean(vazao), .by = data)
  } else NULL
  montante <- dplyr::bind_rows(tel, tamburi) |> dplyr::filter(!is.na(vazao)) |>
    dplyr::distinct(data, .keep_all = TRUE) |> dplyr::arrange(data)

  afl <- alvo_hibrido(rec, chesf, tamburi)
  list(pb = preditores_base(montar_base(chuva, afl, montante)), chuva = chuva)
}
