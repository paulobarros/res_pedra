library(httr2)
library(jsonlite)
library(dplyr)
library(here)
library(lubridate)

data_base <- format(Sys.Date(), "%Y-%m-%d")
# dataBase é ignorado pelo servidor (testado com datas passadas, futuras,
# ausentes e até valores inválidos - todas retornam a mesma janela móvel de
# ~31 dias terminando na data atual do servidor). Mantido apenas como
# documentação da intenção original da API; não há endpoint público para
# consultar dados históricos além dessa janela.
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

df_novo <- data.frame(
  data = sapply(leituras, \(l) substr(campo(l, "Data"), 1, 10)),
  cota = sapply(leituras, \(l) numero(campo(l, "Cota24h"))),
  afluencia = sapply(leituras, \(l) numero(campo(l, "Afluencia"))),
  defluencia = sapply(leituras, \(l) numero(campo(l, "Defluencia"))),
  volume = sapply(leituras, \(l) numero(campo(l, "VolumeUtil")))
) |>
  mutate(data = as.Date(data))

caminho_csv <- here("data", "pedra_dados.csv")

# A API só devolve uma janela rolante de ~31 dias. Para manter o histórico
# completo ao longo do tempo, mesclamos com o CSV existente em vez de
# sobrescrevê-lo, priorizando os valores mais recentes da API em caso de
# datas repetidas (dados de dias recentes costumam ser refinados depois).
df_antigo <- if (file.exists(caminho_csv)) {
  read.csv(caminho_csv) |> mutate(data = as.Date(data))
} else {
  df_novo[0, ]
}

df_final <- bind_rows(df_novo, df_antigo) |>
  distinct(data, .keep_all = TRUE) |>
  arrange(desc(data))

write.csv(df_final, caminho_csv, row.names = FALSE)

message(paste0("OK: ", nrow(df_novo), " leituras novas consultadas, ", nrow(df_final), " leituras no histórico total"))
