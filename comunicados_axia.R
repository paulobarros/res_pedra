# Monitor dos comunicados (cartas circulares) da AXIA Nordeste.
#
# Lê a página de Gestão de Recursos Hídricos da AXIA, detecta cartas novas
# sobre a Pedra / Bacia do Rio de Contas e repassa ao canal do Telegram, com
# um resumo extraído do PDF (situação do reservatório e programação de
# defluência). As demais cartas (São Francisco, Parnaíba...) são só registradas.
#
# Estado: data/comunicados_axia.csv. Na primeira execução (arquivo ausente),
# tudo que já está publicado é registrado como "semente", sem envio.
#
# Variáveis de ambiente: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, DRY_RUN=true

suppressPackageStartupMessages({
  library(dplyr)
  library(httr2)
})

URL_PAGINA <- "https://axia.com.br/axia-nordeste-gestao-de-recursos-hidricos"
BASE <- "https://axia.com.br"
ARQ_ESTADO <- "data/comunicados_axia.csv"
RELEVANTE <- "(?i)pedra|contas"
dry_run <- identical(tolower(Sys.getenv("DRY_RUN")), "true")
agora <- format(Sys.time(), "%Y-%m-%d %H:%M", tz = "America/Bahia")

esc <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

# ---- 1. Lista de comunicados publicados ------------------------------------
listar_comunicados <- function() {
  h <- request(URL_PAGINA) |>
    req_user_agent("Mozilla/5.0 (monitor res_pedra)") |>
    req_timeout(60) |> req_retry(max_tries = 3) |>
    req_perform() |> resp_body_string()
  doc <- xml2::read_html(h)
  a <- xml2::xml_find_all(doc, "//a[contains(@href, '/documents/d/guest/')]")
  if (length(a) == 0) return(tibble(slug = character(), titulo = character(), url = character()))
  href <- xml2::xml_attr(a, "href")
  txt <- trimws(gsub("[\\s\u200b]+", " ", xml2::xml_text(a), perl = TRUE))
  tibble(url = ifelse(startsWith(href, "http"), href, paste0(BASE, href)), titulo = txt) |>
    mutate(slug = sub("\\?.*$", "", basename(url))) |>
    filter(grepl("^carta-circular", slug), titulo != "") |>
    distinct(slug, .keep_all = TRUE)
}

# ---- 2. Resumo do PDF -------------------------------------------------------
resumir_pdf <- function(url) {
  arq <- tempfile(fileext = ".pdf")
  ok <- tryCatch({
    request(url) |> req_user_agent("Mozilla/5.0 (monitor res_pedra)") |>
      req_timeout(90) |> req_perform(path = arq)
    TRUE
  }, error = function(e) FALSE)
  if (!ok || Sys.which("pdftotext") == "") return(NULL)
  if (!grepl("^%PDF", readChar(arq, 4, useBytes = TRUE))) return(NULL)
  txt <- system2("pdftotext", c("-layout", shQuote(arq), "-"), stdout = TRUE, stderr = FALSE)
  unlink(arq)
  if (length(txt) == 0) return(NULL)

  corpo <- paste(trimws(txt), collapse = "\n")
  corpo <- sub("(?s)^.*?Prezad[oa]\\(?a?\\)? Senhor\\(?a?\\)?,?", "", corpo, perl = TRUE)
  corpo <- sub("(?s)Atenciosamente.*$", "", corpo, perl = TRUE)

  # tabela de programação: linhas "dd/mm/aaaa (dia) ... valor"
  linhas <- strsplit(corpo, "\n")[[1]]
  tab <- grep("^\\d{2}/\\d{2}/\\d{4}.*\\d+\\s*$", linhas, value = TRUE, perl = TRUE)
  tab <- vapply(tab, function(l) {
    d <- sub("^(\\d{2}/\\d{2})/\\d{4}.*$", "\\1", l, perl = TRUE)
    dia <- regmatches(l, regexpr("\\(([^)]+)\\)", l))
    v <- sub("^.*?(\\d[\\d.]*)\\s*$", "\\1", l, perl = TRUE)
    paste0(d, if (length(dia)) paste0(" ", dia) else "", ": <b>", v, " m³/s</b>")
  }, character(1), USE.NAMES = FALSE)

  # 1º parágrafo (situação atual), sem rodapé/endereço
  paragrafos <- strsplit(corpo, "\n\\s*\n|\n(?=\\s{3,}\\S)", perl = TRUE)[[1]]
  paragrafos <- trimws(gsub("\\s+", " ", paragrafos))
  paragrafos <- paragrafos[nchar(paragrafos) > 80 & !grepl("axia\\.com\\.br|Rua 15 de|Av\\. Gra", paragrafos)]
  primeiro <- if (length(paragrafos)) paragrafos[1] else ""
  if (nchar(primeiro) > 600) primeiro <- paste0(substr(primeiro, 1, 597), "…")

  list(resumo = primeiro, tabela = tab)
}

# ---- 3. Envio ---------------------------------------------------------------
enviar_telegram <- function(texto) {
  token <- Sys.getenv("TELEGRAM_BOT_TOKEN"); chat <- Sys.getenv("TELEGRAM_CHAT_ID")
  if (token == "" || chat == "") stop("Defina TELEGRAM_BOT_TOKEN e TELEGRAM_CHAT_ID.")
  r <- request(sprintf("https://api.telegram.org/bot%s/sendMessage", token)) |>
    req_body_json(list(chat_id = chat, text = texto, parse_mode = "HTML",
                       link_preview_options = list(is_disabled = TRUE))) |>
    req_retry(max_tries = 3) |> req_error(is_error = \(r) FALSE) |> req_perform()
  isTRUE(resp_body_json(r)$ok)
}

montar_mensagem <- function(titulo, url, info) {
  paste0(
    "📢 <b>Novo comunicado da AXIA sobre a Pedra</b>\n\n",
    "<b>", esc(titulo), "</b>\n",
    if (!is.null(info) && nchar(info$resumo)) paste0("\n", esc(info$resumo), "\n") else "",
    if (!is.null(info) && length(info$tabela)) paste0("\n📅 <b>Programação de defluência</b>\n",
                                                       paste(esc(info$tabela) |> gsub(pattern = "&lt;(/?)b&gt;", replacement = "<\\1b>"),
                                                             collapse = "\n"), "\n") else "",
    "\n🔗 <a href=\"", url, "\">Ler o comunicado completo</a>"
  )
}

# ---- Execução ---------------------------------------------------------------
publicados <- listar_comunicados()
message("comunicados na página: ", nrow(publicados))
if (nrow(publicados) == 0) quit(save = "no", status = 0)   # página mudou ou falhou: não mexe no estado

primeira_vez <- !file.exists(ARQ_ESTADO)
estado <- if (primeira_vez) {
  tibble(slug = character(), titulo = character(), url = character(),
         visto_em = character(), relevante = logical(), enviado = character())
} else read.csv(ARQ_ESTADO, colClasses = "character") |> mutate(relevante = as.logical(relevante))

novos <- publicados |>
  filter(!slug %in% estado$slug) |>
  mutate(visto_em = agora, relevante = grepl(RELEVANTE, paste(titulo, slug), perl = TRUE),
         enviado = ifelse(primeira_vez, "semente", ifelse(relevante, "pendente", "nao_relevante")))

# reenvia pendentes de execuções anteriores (ex.: Telegram fora)
estado <- bind_rows(estado, novos)
pend <- which(estado$enviado == "pendente")
message("novos: ", nrow(novos), " · para enviar: ", length(pend))

for (i in pend) {
  info <- resumir_pdf(estado$url[i])
  msg <- montar_mensagem(estado$titulo[i], estado$url[i], info)
  if (dry_run) {
    message("DRY_RUN — mensagem:\n", msg, "\n")
  } else if (enviar_telegram(msg)) {
    estado$enviado[i] <- agora
    message("enviado: ", estado$slug[i])
  } else {
    message("falha no envio (tenta de novo na próxima rodada): ", estado$slug[i])
  }
}

write.csv(estado |> arrange(desc(visto_em), slug), ARQ_ESTADO, row.names = FALSE)
