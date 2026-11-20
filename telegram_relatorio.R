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

status_volume <- case_when(
  is.na(vol) ~ "⚪",
  vol < 20   ~ "🔴",
  vol < 40   ~ "🟡",
  TRUE       ~ "🟢"
)

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

# ---- Mensagem -------------------------------------------------------------

msg <- paste0(
  "💧 <b>Reservatório da Pedra</b>\n",
  "Boletim de ", fmt_data(data_ref), "\n\n",
  aviso_atraso,
  status_volume, " Volume útil: <b>", fmt_num(vol, 2), "%</b> ", linha_comp(comp_vol), "\n",
  "📏 Cota: <b>", fmt_num(ult$cota, 2), " m</b>\n",
  "📥 Afluência: <b>", fmt_num(afl, 0), " m³/s</b> ", linha_comp(comp_afl, "estável vs. dia anterior"), "\n",
  "📤 Defluência: <b>", fmt_num(dfl, 1), " m³/s</b> ", linha_comp(comp_dfl, "estável vs. dia anterior"), "\n",
  "⚖️ Saldo do dia: <b>", txt_saldo, "</b>\n",
  if (length(alertas) > 0) paste0("\n", paste(alertas, collapse = "\n"), "\n") else "",
  "\n📊 Fonte: <a href=\"", URL_PAINEL, "\">Painel de Monitoramento do Reservatório da Pedra</a>"
)

# ---- Envio ----------------------------------------------------------------

if (identical(tolower(Sys.getenv("DRY_RUN")), "true")) {
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
message(sprintf("Relatório enviado ao canal \"%s\" (mensagem %s).",
                corpo$result$chat$title, corpo$result$message_id))
