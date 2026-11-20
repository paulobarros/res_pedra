# Fontes de dados da bacia do Rio de Contas a montante da UHE Pedra.
# Ver docs-pesquisa/levantamento_previsao_afluencia.md para a origem de cada uma.
#
# Requer: dplyr, httr2, xml2, sf, terra

BACIA_GEOJSON  <- "data/geo/bacia_pedra.geojson"
PONTOS_PREVISAO <- "data/geo/pontos_previsao.csv"

# Estações telemétricas da AXIA publicadas pela ANA (vazão/nível/chuva horários)
ESTACOES_MONTANTE <- data.frame(
  codigo = c("52405100", "52080120", "52269510", "52370010"),
  nome   = c("Montante 1 (Manoel Vitorino)", "Montante 2 (Contendas do Sincorá)",
             "Montante 3 (Tanhaçu)", "Rio Gavião (Anagé)"),
  rio    = c("Rio de Contas", "Rio de Contas", "Rio de Contas", "Rio Gavião"),
  lat    = c(-13.878, -14.031, -14.096, -14.610),
  lon    = c(-40.897, -40.982, -41.292, -41.138)
)

# ---- Telemetria ANA (webservice antigo, sem cadastro) ----------------------
# O serviço é instável: timeouts curtos e falha silenciosa (retorna NULL).
telemetria_ana <- function(codigo, inicio, fim, timeout = 60, tentativas = 2) {
  url <- paste0(
    "http://telemetriaws1.ana.gov.br/ServiceANA.asmx/DadosHidrometeorologicos",
    "?codEstacao=", codigo,
    "&dataInicio=", format(inicio, "%d/%m/%Y"),
    "&dataFim=", format(fim, "%d/%m/%Y")
  )
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_timeout(timeout) |>
      httr2::req_retry(max_tries = tentativas, backoff = \(i) 5) |>
      httr2::req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp)) {
    message("  telemetria ", codigo, ": sem resposta da ANA")
    return(NULL)
  }
  ler_telemetria_xml(httr2::resp_body_string(resp), codigo)
}

# Separado para poder testar sem depender do serviço
ler_telemetria_xml <- function(txt, codigo) {
  doc <- xml2::read_xml(txt)
  regs <- xml2::xml_find_all(doc, ".//*[local-name()='DataHora']/..")
  if (length(regs) == 0) return(NULL)
  campo <- function(nome) {
    v <- xml2::xml_text(xml2::xml_find_first(regs, paste0("./*[local-name()='", nome, "']")))
    trimws(v)
  }
  num <- function(x) suppressWarnings(as.numeric(x))
  dplyr::tibble(
    codigo    = codigo,
    data_hora = as.POSIXct(campo("DataHora"), format = "%Y-%m-%d %H:%M:%S", tz = "America/Bahia"),
    vazao     = num(campo("Vazao")),
    nivel     = num(campo("Nivel")),
    chuva     = num(campo("Chuva"))
  ) |>
    dplyr::filter(!is.na(data_hora))
}

# ---- Previsão de chuva por conjunto (Open-Meteo) ----------------------------
# Média da bacia por membro = média simples dos pontos de uma grade regular de
# 0,5° dentro do polígono (grade regular ≈ ponderação por área).
# Retorna uma linha por (dia, modelo, membro) com a chuva média da bacia em mm.
MODELOS_ENSEMBLE <- c("ecmwf_ifs025", "gfs025", "icon_global")

previsao_ensemble <- function(pontos, dias = 8, modelos = MODELOS_ENSEMBLE) {
  resp <- httr2::request("https://ensemble-api.open-meteo.com/v1/ensemble") |>
    httr2::req_url_query(
      latitude = paste(pontos$lat, collapse = ","),
      longitude = paste(pontos$lon, collapse = ","),
      daily = "precipitation_sum",
      models = paste(modelos, collapse = ","),
      forecast_days = dias,
      timezone = "America/Bahia"
    ) |>
    httr2::req_timeout(120) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_perform()

  js <- httr2::resp_body_json(resp, simplifyVector = FALSE)
  # vários pontos -> lista de objetos; um ponto -> objeto
  if (!is.null(js$daily)) js <- list(js)
  vetor <- function(x) vapply(x, function(v) if (is.null(v)) NA_real_ else as.numeric(v), numeric(1))

  por_ponto <- lapply(seq_along(js), function(i) {
    d <- js[[i]]$daily
    cols <- grep("^precipitation_sum", names(d), value = TRUE)
    long <- lapply(cols, function(cn) {
      dplyr::tibble(dia = as.Date(unlist(d$time)), serie = cn, chuva = vetor(d[[cn]]))
    })
    dplyr::bind_rows(long) |> dplyr::mutate(ponto = i)
  })

  dplyr::bind_rows(por_ponto) |>
    dplyr::mutate(
      modelo = sub("^precipitation_sum_(member[0-9]+_)?", "", serie),
      membro = ifelse(grepl("_member[0-9]+_", serie),
                      sub("^precipitation_sum_member([0-9]+)_.*$", "\\1", serie), "00")
    ) |>
    dplyr::summarise(chuva = mean(chuva), .by = c(dia, modelo, membro))  # NA se faltar ponto
}

# Resumo por dia: percentis e probabilidades sobre todos os membros
resumo_previsao_diaria <- function(ens) {
  ens |>
    dplyr::filter(!is.na(chuva)) |>
    dplyr::summarise(
      membros = dplyr::n(),
      p10 = stats::quantile(chuva, 0.10), p50 = stats::quantile(chuva, 0.50),
      p90 = stats::quantile(chuva, 0.90), media = mean(chuva),
      prob_5mm = mean(chuva >= 5), prob_10mm = mean(chuva >= 10), prob_25mm = mean(chuva >= 25),
      .by = dia
    ) |>
    dplyr::mutate(dplyr::across(p10:media, ~ round(.x, 1)),
                  dplyr::across(dplyr::starts_with("prob"), ~ round(.x, 3))) |>
    dplyr::arrange(dia)
}

# Resumo de acumulados (próximos 3 e 7 dias, a partir de hoje)
resumo_previsao_acumulada <- function(ens, hoje, janelas = c(3, 7)) {
  dplyr::bind_rows(lapply(janelas, function(n) {
    ens |>
      dplyr::filter(dia >= hoje, dia < hoje + n) |>
      dplyr::summarise(total = sum(chuva), dias_ok = sum(!is.na(chuva)), .by = c(modelo, membro)) |>
      dplyr::filter(dias_ok == n) |>
      dplyr::summarise(
        janela_dias = n, membros = dplyr::n(),
        p10 = stats::quantile(total, 0.10), p50 = stats::quantile(total, 0.50),
        p90 = stats::quantile(total, 0.90),
        prob_10mm = mean(total >= 10), prob_25mm = mean(total >= 25), prob_50mm = mean(total >= 50)
      )
  })) |>
    dplyr::mutate(dplyr::across(p10:p90, ~ round(.x, 1)),
                  dplyr::across(dplyr::starts_with("prob"), ~ round(.x, 3)))
}

# ---- Chuva observada: MERGE/CPTEC -------------------------------------------
# Arquivo do dia D = chuva acumulada das 12 UTC de D-1 às 12 UTC de D
# (09h às 09h no horário da Bahia). Grade de 0,1°.
url_merge <- function(d) {
  sprintf("https://ftp.cptec.inpe.br/modelos/tempo/MERGE/GPM/DAILY/%s/%s/MERGE_CPTEC_%s.grib2",
          format(d, "%Y"), format(d, "%m"), format(d, "%Y%m%d"))
}

chuva_merge_bacia <- function(d, bacia_vect, pasta_tmp = tempdir()) {
  arq <- file.path(pasta_tmp, basename(url_merge(d)))
  ok <- tryCatch({
    httr2::request(url_merge(d)) |>
      httr2::req_timeout(120) |>
      httr2::req_retry(max_tries = 2) |>
      httr2::req_perform(path = arq)
    TRUE
  }, error = function(e) FALSE)
  if (!ok) return(NULL)
  on.exit(unlink(arq))

  r <- terra::rast(arq)[[1]]  # banda 1 = PREC
  r <- terra::crop(r, bacia_vect, snap = "out")
  # média ponderada pela fração de cada célula dentro do polígono
  ex <- terra::extract(r, bacia_vect, exact = TRUE)
  dplyr::tibble(
    data = d,
    chuva_media = round(stats::weighted.mean(ex[[2]], ex$fraction, na.rm = TRUE), 2),
    chuva_max   = round(max(ex[[2]], na.rm = TRUE), 1)
  )
}
