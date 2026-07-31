library(httr2)
library(jsonlite)
library(dplyr)
library(here)
library(lubridate)

data_base <- format(Sys.Date(), "%Y-%m-%d")
url_api <- paste0("https://hidrows.chesf.com.br/api/acompanhamento/Consultar?dataBase=", data_base)

message(paste0("Consultando API da Chesf para a data-base ", data_base, "..."))

resp <- request(url_api) |>
  req_headers(Accept = "application/json") |>
  req_retry(max_tries = 5, backoff = \(attempt) 10) |>
  req_perform()

bacias <- fromJSON(resp_body_string(resp), simplifyVector = FALSE)

posto_pedra <- NULL
for (bacia in bacias) {
  for (posto in bacia$Postos) {
    if (isTRUE(posto$isReservatorio) && grepl("PEDRA", posto$Nome, ignore.case = TRUE)) {
      posto_pedra <- posto
      break
    }
  }
  if (!is.null(posto_pedra)) break
}

if (is.null(posto_pedra)) {
  stop("Erro: Não foi possível localizar o Reservatório da Pedra na resposta da API.")
}

leituras <- posto_pedra$Leituras

if (length(leituras) == 0) {
  stop("Erro: A API retornou dados do Reservatório da Pedra sem nenhuma leitura.")
}

campo <- function(leitura, nome) {
  valor <- leitura[[nome]]
  if (is.null(valor)) NA_character_ else as.character(valor)
}

numero <- function(x) {
  suppressWarnings(as.numeric(gsub(",", ".", x, fixed = TRUE)))
}

df_final <- data.frame(
  data = sapply(leituras, \(l) substr(campo(l, "Data"), 1, 10)),
  cota = sapply(leituras, \(l) numero(campo(l, "Cota24h"))),
  afluencia = sapply(leituras, \(l) numero(campo(l, "Afluencia"))),
  defluencia = sapply(leituras, \(l) numero(campo(l, "Defluencia"))),
  volume = sapply(leituras, \(l) numero(campo(l, "VolumeUtil")))
) |>
  mutate(data = as.Date(data)) |>
  arrange(desc(data))

write.csv(df_final, here("data", "pedra_dados.csv"), row.names = FALSE)

message(paste0("OK: ", nrow(df_final), " leituras gravadas em data/pedra_dados.csv"))
