# Fase 2 · Séries diárias de vazão (HidroWeb/ANA, webservice antigo).
#
# O serviço devolve um registro por mês com Vazao01..Vazao31 e o nível de
# consistência (1 = bruto, 2 = consistido). Quando um mês tem as duas versões,
# fica a consistida.
#
# Estações (ver docs-pesquisa/levantamento_previsao_afluencia.md):
#   52405000 Lagoa do Tamburi  — Rio de Contas, 32.500 km² (~80% da bacia da Pedra)
#   52270000 Santo Antônio     — Rio de Contas, 18.200 km² (montante)
#   52570000 Jequié            — Rio de Contas, logo a jusante da barragem

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

ESTACOES <- c("52405000" = "Lagoa do Tamburi", "52270000" = "Santo Antônio", "52570000" = "Jequié")
SAIDA <- "data/historico/vazoes_diarias_ana.csv"

serie_vazao <- function(codigo) {
  url <- paste0("http://telemetriaws1.ana.gov.br/ServiceANA.asmx/HidroSerieHistorica",
                "?codEstacao=", codigo, "&dataInicio=&dataFim=&tipoDados=3&nivelConsistencia=")
  txt <- httr2::request(url) |> httr2::req_timeout(300) |> httr2::req_retry(max_tries = 3) |>
    httr2::req_perform() |> httr2::resp_body_string()
  doc <- xml2::read_xml(txt)
  regs <- xml2::xml_find_all(doc, ".//*[local-name()='DataHora']/..")
  campo <- function(nome) xml2::xml_text(xml2::xml_find_first(regs, paste0("./*[local-name()='", nome, "']")))

  meses <- tibble(
    mes = as.Date(substr(trimws(campo("DataHora")), 1, 10)),
    consistencia = as.integer(campo("NivelConsistencia"))
  )
  for (d in 1:31) meses[[sprintf("d%02d", d)]] <- suppressWarnings(as.numeric(campo(sprintf("Vazao%02d", d))))

  meses |>
    slice_max(consistencia, n = 1, by = mes, with_ties = FALSE) |>   # consistido > bruto
    pivot_longer(starts_with("d"), names_to = "dia", values_to = "vazao") |>
    mutate(data = mes + as.integer(sub("d", "", dia)) - 1L) |>
    filter(format(data, "%m") == format(mes, "%m")) |>                # descarta 30/02 etc.
    transmute(codigo = codigo, data, vazao, consistencia) |>
    arrange(data)
}

res <- bind_rows(lapply(names(ESTACOES), function(cod) {
  message("baixando ", cod, " ", ESTACOES[[cod]], "...")
  s <- tryCatch(serie_vazao(cod), error = function(e) { message("  falhou: ", conditionMessage(e)); NULL })
  if (!is.null(s)) message(sprintf("  %s a %s, %d dias com vazão", min(s$data), max(s$data), sum(!is.na(s$vazao))))
  s
}))

write.csv(res, SAIDA, row.names = FALSE)
message("salvo em ", SAIDA, " (", nrow(res), " linhas)")
