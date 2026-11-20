# Coleta de dados da bacia a montante da UHE Pedra (fase 1 da previsão).
# Roda a cada hora junto com chesf_data.R; cada fonte decide se precisa
# atualizar e falha sozinha, sem derrubar as outras.
#
#   - Telemetria ANA (vazão/nível/chuva horários a montante): toda execução
#   - Previsão de chuva por conjunto (Open-Meteo): a cada 6 horas
#   - Chuva observada na bacia (MERGE/CPTEC): dias que ainda faltam
#
# Uso: Rscript coleta_bacia.R            (atualização normal)
#      Rscript coleta_bacia.R --forcar   (ignora o intervalo da previsão)

suppressPackageStartupMessages({
  library(dplyr)
})
source("R/fontes_bacia.R")

ARQ_TELEMETRIA    <- "data/telemetria_montante.csv"
ARQ_PREV_DIARIA   <- "data/previsao_chuva_diaria.csv"
ARQ_PREV_ACUM     <- "data/previsao_chuva_acumulada.csv"
ARQ_PREV_HIST     <- "data/previsao_chuva_historico.csv"
ARQ_MERGE         <- "data/chuva_bacia_merge.csv"

INICIO_SERIE      <- as.Date("2026-07-01")   # mesmo início da série da CHESF
INTERVALO_PREV_H  <- 6
MAX_MERGE_POR_RODADA <- as.integer(Sys.getenv("MAX_MERGE", "15"))

forcar <- "--forcar" %in% commandArgs(trailingOnly = TRUE)
agora  <- Sys.time()
hoje   <- as.Date(format(agora, "%Y-%m-%d", tz = "America/Bahia"))
fmt_hora <- function(x) format(x, "%Y-%m-%d %H:%M", tz = "America/Bahia")
ler_hora <- function(x) as.POSIXct(x, format = "%Y-%m-%d %H:%M", tz = "America/Bahia")

etapa <- function(nome, expr) {
  message("== ", nome)
  tryCatch(expr, error = function(e) message("  FALHOU: ", conditionMessage(e)))
}

# ---- 1. Telemetria a montante ----------------------------------------------
etapa("Telemetria ANA (montante)", {
  antigo <- if (file.exists(ARQ_TELEMETRIA)) {
    read.csv(ARQ_TELEMETRIA, colClasses = c(codigo = "character")) |>
      mutate(data_hora = ler_hora(data_hora))
  } else NULL

  # janela curta para a rodada horária; desde o início se o arquivo não existe
  inicio <- if (is.null(antigo)) INICIO_SERIE else hoje - 2

  # "Disjuntor": o serviço da ANA às vezes fica minutos sem responder. Na
  # primeira falha, desistimos da telemetria nesta rodada (a próxima tenta de novo).
  ana_ok <- TRUE
  consulta <- function(cod, de, ate) {
    if (!ana_ok) return(NULL)
    r <- telemetria_ana(cod, de, ate, timeout = 45, tentativas = 1)
    if (is.null(r)) ana_ok <<- FALSE
    r
  }
  novos <- bind_rows(lapply(ESTACOES_MONTANTE$codigo, function(cod) {
    # o serviço aceita intervalos longos, mas responde melhor em blocos de ~30 dias
    blocos <- seq(inicio, hoje, by = 30)
    bind_rows(lapply(blocos, \(b) consulta(cod, b, min(b + 29, hoje))))
  }))
  if (!ana_ok) message("  ANA fora do ar: telemetria pulada nesta rodada")
  message("  registros recebidos: ", nrow(novos))

  if (nrow(novos) > 0) {
    todos <- bind_rows(novos, antigo) |>
      distinct(codigo, data_hora, .keep_all = TRUE) |>   # mantém o mais novo
      arrange(codigo, data_hora)
    write.csv(mutate(todos, data_hora = fmt_hora(data_hora)), ARQ_TELEMETRIA, row.names = FALSE)
    message("  total no arquivo: ", nrow(todos))
  }
})

# ---- 2. Previsão de chuva por conjunto -------------------------------------
etapa("Previsão de chuva (Open-Meteo ensemble)", {
  ultima <- if (file.exists(ARQ_PREV_DIARIA)) ler_hora(read.csv(ARQ_PREV_DIARIA)$emitido_em[1]) else NA
  idade_h <- if (is.na(ultima)) Inf else as.numeric(difftime(agora, ultima, units = "hours"))

  if (!forcar && idade_h < INTERVALO_PREV_H) {
    message(sprintf("  previsão de %.1f h atrás; próxima após %d h", idade_h, INTERVALO_PREV_H))
  } else {
    ens <- previsao_ensemble(read.csv(PONTOS_PREVISAO))
    emitido <- fmt_hora(agora)

    diaria <- resumo_previsao_diaria(ens) |> mutate(emitido_em = emitido, .before = 1)
    acum   <- resumo_previsao_acumulada(ens, hoje) |> mutate(emitido_em = emitido, .before = 1)
    write.csv(diaria, ARQ_PREV_DIARIA, row.names = FALSE)
    write.csv(acum, ARQ_PREV_ACUM, row.names = FALSE)
    # chuva diária por cenário: entrada do modelo de afluência (previsao_afluencia.R)
    write.csv(ens |> mutate(emitido_em = emitido, chuva = round(chuva, 2)),
              "data/previsao_chuva_membros.csv", row.names = FALSE)

    # histórico de previsões (para medir acerto e corrigir viés na fase 2)
    write.table(diaria, ARQ_PREV_HIST, sep = ",", row.names = FALSE,
                col.names = !file.exists(ARQ_PREV_HIST), append = file.exists(ARQ_PREV_HIST))
    message("  ", nrow(diaria), " dias, ", max(diaria$membros), " membros")
  }
})

# ---- 3. Chuva observada (MERGE) --------------------------------------------
etapa("Chuva observada na bacia (MERGE/CPTEC)", {
  antigo <- if (file.exists(ARQ_MERGE)) read.csv(ARQ_MERGE) |> mutate(data = as.Date(data)) else NULL
  # o CPTEC reprocessa os arquivos mais recentes (o de hoje muda ao longo do
  # dia), então os 2 últimos dias são sempre baixados de novo
  faltando <- setdiff(seq(INICIO_SERIE, hoje, by = 1), antigo$data[antigo$data < hoje - 1]) |> as.Date()
  faltando <- head(sort(faltando, decreasing = TRUE), MAX_MERGE_POR_RODADA)  # mais recentes primeiro

  if (length(faltando) == 0) {
    message("  em dia")
  } else {
    bacia <- terra::vect(BACIA_GEOJSON)
    novos <- bind_rows(lapply(faltando, \(d) suppressWarnings(chuva_merge_bacia(d, bacia))))
    message("  dias novos: ", nrow(novos), " de ", length(faltando), " tentados")
    if (nrow(novos) > 0) {
      bind_rows(novos, antigo) |>
        distinct(data, .keep_all = TRUE) |>   # mantém a versão nova
        arrange(data) |>
        write.csv(ARQ_MERGE, row.names = FALSE)
    }
  }
})
