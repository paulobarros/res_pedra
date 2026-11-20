# Fase 2 · Afluência histórica reconstruída da UHE Pedra por balanço hídrico.
#
#   afluência(t) ≈ defluência(t) + [V(t+1) − V(t)] / 86 400 s
#
# - V: volume diário do reservatório no SAR/ANA (hm³, desde 2012, com lacunas)
# - defluência ≈ vazão em Jequié (52570000), logo a jusante da barragem
#   (inclui ~200 km² de área incremental — desprezível nas cheias)
#
# A resolução do SAR é de 1 hm³ (≈ 11,6 m³/s em um dia), então a série é
# ruidosa em vazões baixas e boa nas cheias, que é o que interessa ao modelo.

suppressPackageStartupMessages({
  library(dplyr)
})

SAIDA_SAR <- "data/historico/sar_pedra_volume.csv"
SAIDA <- "data/historico/afluencia_pedra_reconstruida.csv"

# ---- Volume diário do SAR ---------------------------------------------------
url <- paste0("https://www.ana.gov.br/sar0/Medicao?dropDownListEstados=6&dropDownListReservatorios=12320",
              "&dataInicial=01/01/2000&dataFinal=", format(Sys.Date(), "%d/%m/%Y"), "&button=Buscar")
html <- httr2::request(url) |> httr2::req_timeout(300) |> httr2::req_retry(max_tries = 3) |>
  httr2::req_perform() |> httr2::resp_body_string()
tab <- rvest::html_table(xml2::read_html(html), convert = FALSE)
tab <- tab[[which.max(vapply(tab, nrow, integer(1)))]]
names(tab) <- tolower(iconv(names(tab), to = "ASCII//TRANSLIT"))
num <- function(x) as.numeric(gsub(",", ".", gsub("\\.", "", trimws(x))))
col <- function(padrao) names(tab)[grep(padrao, names(tab))[1]]

sar <- tibble(
  data = as.Date(trimws(tab[[col("^data")]]), format = "%d/%m/%Y"),
  cota = num(tab[[col("cota")]]),
  volume_hm3 = num(tab[[col("^volume( \\(hm|$)")]])
) |>
  filter(!is.na(data), !is.na(volume_hm3)) |>
  distinct(data, .keep_all = TRUE) |>
  arrange(data)
write.csv(sar, SAIDA_SAR, row.names = FALSE)
message(sprintf("SAR: %d dias, %s a %s", nrow(sar), min(sar$data), max(sar$data)))

# ---- Balanço hídrico --------------------------------------------------------
jequie <- read.csv("data/historico/vazoes_diarias_ana.csv", colClasses = c(codigo = "character")) |>
  filter(codigo == "52570000") |>
  transmute(data = as.Date(data), defluencia_jequie = vazao)

rec <- sar |>
  mutate(dV = lead(volume_hm3) - volume_hm3,
         dias = as.numeric(lead(data) - data)) |>
  filter(dias == 1) |>                              # só pares de dias consecutivos
  left_join(jequie, by = "data") |>
  mutate(afluencia_rec = round(defluencia_jequie + dV * 1e6 / 86400, 1)) |>
  select(data, cota, volume_hm3, dV, defluencia_jequie, afluencia_rec)

write.csv(rec, SAIDA, row.names = FALSE)
message(sprintf("reconstruída: %d dias com afluência (%s a %s)",
                sum(!is.na(rec$afluencia_rec)), min(rec$data), max(rec$data)))
