# Relatório diário do Reservatório da Pedra para o canal do Telegram.
#
# Variáveis de ambiente:
#   TELEGRAM_BOT_TOKEN  token do bot (BotFather)
#   TELEGRAM_CHAT_ID    @ do canal ou ID numérico (-100...)
#   DRY_RUN             "true" para só imprimir a mensagem, sem enviar
#
# Os indicadores vêm de R/indicadores.R, os mesmos usados no painel.

suppressPackageStartupMessages({
  library(dplyr)
  library(httr2)
  library(lubridate)
})

source("R/indicadores.R")

URL_PAINEL <- "https://paulobarros.github.io/res_pedra/"

df <- carregar_dados()
ult <- ultimo_registro(df)
data_ref <- ult$data
hoje <- as.Date(format(Sys.time(), "%Y-%m-%d", tz = "America/Bahia"))

# Evita boletim duplicado: o workflow pode ser disparado pelo agendador da
# Cloudflare e pelo cron do GitHub (reserva). Guarda a data do último envio.
ARQ_ULTIMO_ENVIO <- "data/telegram_ultimo_envio.txt"
dry_run <- identical(tolower(Sys.getenv("DRY_RUN")), "true")
forcar  <- identical(tolower(Sys.getenv("FORCAR")), "true")
if (!dry_run && !forcar && file.exists(ARQ_ULTIMO_ENVIO) &&
    identical(trimws(readLines(ARQ_ULTIMO_ENVIO, warn = FALSE)[1]), format(hoje))) {
  message("Boletim de hoje (", format(hoje), ") já foi enviado; nada a fazer.")
  quit(save = "no", status = 0)
}

# ---- Textos auxiliares ----------------------------------------------------

seta <- function(comp) {
  if (is.na(comp$sentido)) return("")
  c(sobe = "▲", desce = "▼", igual = "▬")[[comp$sentido]]
}

linha_comp <- function(comp, rotulo_igual = NULL) {
  if (is.na(comp$sentido)) return(paste0("<i>(", comp$texto, ")</i>"))
  if (comp$sentido == "igual" && !is.null(rotulo_igual)) {
    return(paste0("<i>(", seta(comp), " ", rotulo_igual, ")</i>"))
  }
  paste0("<i>(", seta(comp), " ", comp$texto, ")</i>")
}

fmt_data <- function(d) format(d, "%d/%m/%Y")
fmt_dm   <- function(d) format(d, "%d/%m")

# ---- Indicadores ----------------------------------------------------------

vol <- ult$volume
afl <- ult$afluencia
dfl <- ult$defluencia


comp_vol <- comparacao(vol, valor_em(df, "volume", data_ref, 7), " p.p.", "em 7 dias", 2)
comp_afl <- comparacao(afl, valor_em(df, "afluencia", data_ref, 1), " m³/s", "vs. dia anterior", 0)
comp_dfl <- comparacao(dfl, valor_em(df, "defluencia", data_ref, 1), " m³/s", "vs. dia anterior", 1)

saldo <- afl - dfl
txt_saldo <- if (is.na(saldo)) {
  "—"
} else {
  paste0(if (saldo > 0) "+" else if (saldo < 0) "−" else "", fmt_num(abs(saldo), 1), " m³/s ",
         if (saldo > 0) "(enchendo)" else if (saldo < 0) "(esvaziando)" else "(estável)")
}

# Alertas de janelas de aumento ainda ativas
alertas <- character()
emoji_nivel <- c("Moderada" = "🟡", "Alta" = "🟠", "Muito alta" = "🔴", "Extrema" = "🟣")

ja <- janela_ativa(anomalias_afluencia(df))
if (!is.null(ja)) {
  alertas <- c(alertas, sprintf(
    "%s Afluência em nível <b>%s</b> desde %s",
    emoji_nivel[[ja$rotulo]], ja$rotulo, fmt_dm(ja$inicio)
  ))
}

jd <- janela_ativa(anomalias_defluencia(df))
if (!is.null(jd)) {
  alertas <- c(alertas, sprintf(
    "🔴 Defluência em <b>alta</b> desde %s: a barragem está liberando mais água",
    fmt_dm(jd$inicio)
  ))
}

# Boletim atrasado: normalmente a AXIA publica os dados do dia anterior
aviso_atraso <- if (data_ref < hoje - 1) {
  sprintf("ℹ️ <i>A AXIA ainda não publicou dados mais recentes; os números abaixo são de %s.</i>\n\n",
          fmt_data(data_ref))
} else ""

# ---- Previsão de chuva na bacia (gerada por coleta_bacia.R) ----------------
ler_csv <- function(arq, ...) if (file.exists(arq)) read.csv(arq, ...) else NULL

prev <- ler_csv("data/previsao_chuva_acumulada.csv")
linha_previsao <- if (!is.null(prev) && any(prev$janela_dias == 3)) {
  p3 <- prev[prev$janela_dias == 3, ][1, ]
  sprintf("🌧 Previsão de chuva na bacia (3 dias): <b>~%s mm</b> <i>(entre %s e %s mm; chance de ≥25 mm: %s%%)</i>\n\n",
          fmt_num(p3$p50, 0), fmt_num(p3$p10, 0), fmt_num(p3$p90, 0), round(100 * p3$prob_25mm))
} else ""

# Previsão de afluência (fase 2, experimental) — próximos 3 dias, se recente
prev_afl <- ler_csv("data/previsao_afluencia.csv")
linha_afluencia <- ""
if (!is.null(prev_afl)) {
  emit <- as.POSIXct(prev_afl$emitido_em[1], tz = "America/Bahia")
  prox <- prev_afl[as.Date(prev_afl$data_alvo) >= hoje & as.Date(prev_afl$data_alvo) <= hoje + 2, ]
  if (nrow(prox) > 0 && difftime(Sys.time(), emit, units = "hours") < 24) {
    linha_afluencia <- sprintf(
      "🔮 Afluência prevista (3 dias): <b>~%s m³/s</b> <i>(cenário alto até %s m³/s; chance de cheia: %s%%)</i>\n<i>Previsão experimental.</i>\n\n",
      fmt_num(max(prox$p50), 0), fmt_num(max(prox$p90), 0), round(100 * max(prox$prob_cheia)))
  }
}

# ---- Mensagem -------------------------------------------------------------

# Glossário em citação expansível: ocupa pouco espaço e abre com um toque
glossario <- paste0(
  "<blockquote expandable>📖 <b>Entenda os termos</b>\n",
  "<b>Volume útil:</b> água disponível para uso, acima do volume morto (nível mínimo de operação), em %\n",
  "<b>Cota:</b> altura da superfície da água em relação ao nível do mar\n",
  "<b>Afluência:</b> água que <b>entra</b> no reservatório (rios e chuvas)\n",
  "<b>Defluência:</b> água que <b>sai</b> pela barragem\n",
  "<b>Saldo:</b> entrada − saída. Positivo, o reservatório enche; negativo, esvazia\n",
  "<b>Chance de cheia:</b> fração dos cenários de previsão com afluência acima de 300 m³/s\n",
  "<b>Bacia:</b> toda a área cujas chuvas escoam para o reservatório (~40 mil km², 46 municípios)\n",
  "<b>m³/s:</b> metros cúbicos por segundo (1 m³ = 1.000 litros)",
  "</blockquote>"
)

msg <- paste0(
  "📋 <b>Reservatório da Pedra</b> - Boletim de <i>", fmt_data(data_ref), "</i>\n\n",
  aviso_atraso,
  "💧 Volume útil: <b>", fmt_num(vol, 2), "%</b> ", linha_comp(comp_vol), "\n",
  "📐 Cota: <b>", fmt_num(ult$cota, 2), " m</b>\n",
  "⤵️ Afluência: <b>", fmt_num(afl, 0), " m³/s</b> ", linha_comp(comp_afl, "estável vs. dia anterior"), "\n",
  "↪️ Defluência: <b>", fmt_num(dfl, 1), " m³/s</b> ", linha_comp(comp_dfl, "estável vs. dia anterior"), "\n",
  "📊 Saldo: <b>", txt_saldo, "</b>\n\n",
  if (length(alertas) > 0) paste0(paste(alertas, collapse = "\n"), "\n\n") else "",
  linha_previsao,
  linha_afluencia,
  glossario, "\n\n",
  "🔗 Fonte: <a href=\"", URL_PAINEL, "\">Painel de Monitoramento do Reservatório da Pedra</a>"
)

# ---- Envio ----------------------------------------------------------------

if (dry_run) {
  message("DRY_RUN: mensagem não enviada.\n")
  cat(msg, "\n")
  quit(save = "no", status = 0)
}

token <- Sys.getenv("TELEGRAM_BOT_TOKEN")
chat_id <- Sys.getenv("TELEGRAM_CHAT_ID")
if (token == "" || chat_id == "") stop("Defina TELEGRAM_BOT_TOKEN e TELEGRAM_CHAT_ID.")

resp <- request(sprintf("https://api.telegram.org/bot%s/sendMessage", token)) |>
  req_body_json(list(
    chat_id = chat_id,
    text = msg,
    parse_mode = "HTML",
    link_preview_options = list(is_disabled = TRUE)
  )) |>
  req_retry(max_tries = 3) |>
  req_error(is_error = \(r) FALSE) |>
  req_perform()

corpo <- resp_body_json(resp)
if (!isTRUE(corpo$ok)) {
  stop(sprintf("Telegram recusou a mensagem: %s %s", corpo$error_code, corpo$description))
}
writeLines(format(hoje), ARQ_ULTIMO_ENVIO)
message(sprintf("Relatório enviado ao canal \"%s\" (mensagem %s).",
                corpo$result$chat$title, corpo$result$message_id))
