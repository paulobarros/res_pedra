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

# ---- Bacia: chuva observada, previsão e rio a montante ---------------------
# Arquivos gerados por coleta_bacia.R; cada linha só entra se o dado existir.
ler_csv <- function(arq, ...) if (file.exists(arq)) read.csv(arq, ...) else NULL
linhas_bacia <- character()

obs <- ler_csv("data/chuva_bacia_merge.csv")
if (!is.null(obs) && nrow(obs) > 0) {
  o <- obs[which.max(as.Date(obs$data)), ]
  linhas_bacia <- c(linhas_bacia, sprintf(
    "🌧️ Chuva na bacia (até 9h de %s): <b>%s mm</b> <i>(máx. local %s mm)</i>",
    fmt_dm(as.Date(o$data)), fmt_num(o$chuva_media, 1), fmt_num(o$chuva_max, 0)))
}

prev <- ler_csv("data/previsao_chuva_acumulada.csv")
if (!is.null(prev) && any(prev$janela_dias == 3)) {
  p3 <- prev[prev$janela_dias == 3, ][1, ]
  linhas_bacia <- c(linhas_bacia, sprintf(
    "🔮 Previsão 3 dias: <b>~%s mm</b> <i>(entre %s e %s mm; chance de ≥25 mm: %s%%)</i>",
    fmt_num(p3$p50, 0), fmt_num(p3$p10, 0), fmt_num(p3$p90, 0), round(100 * p3$prob_25mm)))
}

tel <- ler_csv("data/telemetria_montante.csv", colClasses = c(codigo = "character"))
if (!is.null(tel)) {
  m1 <- tel[tel$codigo == "52405100" & !is.na(tel$vazao), ]
  m1$data_hora <- as.POSIXct(m1$data_hora, format = "%Y-%m-%d %H:%M", tz = "America/Bahia")
  m1 <- m1[order(m1$data_hora), ]
  # só mostra se a leitura for recente (o serviço da ANA às vezes fica fora)
  if (nrow(m1) > 0 && difftime(Sys.time(), tail(m1$data_hora, 1), units = "hours") < 12) {
    atual <- tail(m1, 1)
    ref24 <- m1$vazao[which.min(abs(as.numeric(difftime(m1$data_hora, atual$data_hora - 86400))))]
    linhas_bacia <- c(linhas_bacia, sprintf(
      "🏞️ Rio de Contas a montante: <b>%s m³/s</b> %s",
      fmt_num(atual$vazao, 1), linha_comp(comparacao(atual$vazao, ref24, " m³/s", "em 24 h", 1))))
  }
}

bloco_bacia <- if (length(linhas_bacia) > 0) {
  paste0("\n<b>Bacia do Rio de Contas</b>\n", paste(linhas_bacia, collapse = "\n"), "\n")
} else ""

# ---- Mensagem -------------------------------------------------------------

# Glossário em citação expansível: ocupa pouco espaço e abre com um toque
glossario <- paste0(
  "<blockquote expandable>📖 <b>Entenda os termos</b>\n",
  "<b>Volume útil:</b> água disponível para uso, acima do volume morto (nível mínimo de operação), em %\n",
  "<b>Cota:</b> altura da superfície da água em relação ao nível do mar\n",
  "<b>Afluência:</b> água que <b>entra</b> no reservatório (rios e chuvas)\n",
  "<b>Defluência:</b> água que <b>sai</b> pela barragem\n",
  "<b>Saldo:</b> entrada − saída. Positivo, o reservatório enche; negativo, esvazia\n",
  "<b>Bacia:</b> toda a área cujas chuvas escoam para o reservatório (~40 mil km², 46 municípios)\n",
  "<b>Rio a montante:</b> vazão medida no Rio de Contas ~70 km antes da barragem; costuma antecipar a afluência em 1 a 2 dias\n",
  "<b>m³/s:</b> metros cúbicos por segundo (1 m³ = 1.000 litros)",
  "</blockquote>"
)

msg <- paste0(
  "💧 <b>Reservatório da Pedra</b>\n",
  "Boletim de ", fmt_data(data_ref), "\n\n",
  aviso_atraso,
  status_volume, " Volume útil: <b>", fmt_num(vol, 2), "%</b> ", linha_comp(comp_vol), "\n",
  "📏 Cota: <b>", fmt_num(ult$cota, 2), " m</b>\n",
  "📥 Afluência: <b>", fmt_num(afl, 0), " m³/s</b> ", linha_comp(comp_afl, "estável vs. dia anterior"), "\n",
  "📤 Defluência: <b>", fmt_num(dfl, 1), " m³/s</b> ", linha_comp(comp_dfl, "estável vs. dia anterior"), "\n",
  "⚖️ Saldo do dia: <b>", txt_saldo, "</b>\n",
  bloco_bacia,
  if (length(alertas) > 0) paste0("\n", paste(alertas, collapse = "\n"), "\n") else "",
  "\n", glossario, "\n",
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
