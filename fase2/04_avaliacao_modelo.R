# Fase 2 · Avaliação do modelo de afluência (teste retrospectivo).
#
# Alvo híbrido (ver R/modelo_afluencia.R).
# Treino: até 30/06/2021. Teste: 01/07/2021 em diante — inclui as cheias de
# dez/2022 e mar/2026. A chuva "futura" no teste é a chuva observada, então o
# resultado é o MELHOR CASO (previsão de chuva perfeita).
#
# Compara com dois métodos de referência:
#   - persistência: afluência de t+h = afluência de t
#   - climatologia: mediana da afluência no mês

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})
source("R/modelo_afluencia.R")
dir.create("fase2/resultados", showWarnings = FALSE)

pb <- carregar_base_modelo()$pb

CORTE <- as.Date("2021-06-30")

t0 <- Sys.time()
modelos <- treinar_modelos(pb, ate = CORTE)
message(sprintf("treino: %.0f s", as.numeric(difftime(Sys.time(), t0, units = "secs"))))

clim <- pb |> filter(data <= CORTE, !is.na(afl)) |>
  mutate(mes = format(data, "%m")) |> summarise(clim = median(afl), .by = mes)

nse <- function(o, p) 1 - sum((o - p)^2) / sum((o - mean(o))^2)

aval <- bind_rows(lapply(HORIZONTES, function(h) {
  tb <- tabela_horizonte(pb, h) |> filter(data > CORTE)
  tb <- tb[complete.cases(tb[, c(PREDITORES, "alvo")]), ]
  q <- prever_quantis(modelos[[h]], tb)
  tb |>
    mutate(h = h, p10 = q[, 1], p50 = q[, 2], p90 = q[, 3],
           persist = afl0, mes = format(data + h, "%m")) |>
    left_join(clim, by = "mes") |>
    select(data, h, alvo, p10, p50, p90, persist, clim)
}))
write.csv(aval, "fase2/resultados/previsoes_teste.csv", row.names = FALSE)

metricas <- aval |>
  summarise(
    n = n(),
    mae_modelo = mean(abs(alvo - p50)), mae_persist = mean(abs(alvo - persist)), mae_clim = mean(abs(alvo - clim)),
    nse_modelo = nse(alvo, p50), nse_persist = nse(alvo, persist),
    cobertura_p10_p90 = mean(alvo >= p10 & alvo <= p90),
    # cheias: dias com afluência > 300 m³/s
    n_cheia = sum(alvo > 300),
    acerto_cheia = mean((p50 > 300)[alvo > 300]),
    acerto_cheia_p90 = mean((p90 > 300)[alvo > 300]),
    falso_alarme_p90 = mean((p90 > 300)[alvo <= 300]),
    .by = h
  ) |>
  mutate(across(where(is.double), \(x) round(x, 3)))
write.csv(metricas, "fase2/resultados/metricas_teste.csv", row.names = FALSE)
print(as.data.frame(metricas))

imp <- sort(modelos[[3]]$variable.importance, decreasing = TRUE)
message("\nimportância (h = 3): ", paste(sprintf("%s=%.3f", names(imp), imp)[1:8], collapse = ", "))

# ---- Figuras: as duas cheias do período de teste ----------------------------
eventos <- list(
  "Cheia de dez/2022" = c("2022-12-10", "2023-01-10"),
  "Cheia de mar/2026" = c("2026-02-20", "2026-03-20")
)
for (nm in names(eventos)) {
  j <- as.Date(eventos[[nm]])
  d <- aval |> filter(h %in% c(1, 3, 5), data + h >= j[1], data + h <= j[2]) |>
    mutate(alvo_data = data + h, h = paste0("antecedência de ", h, " dia(s)"))
  g <- ggplot(d, aes(alvo_data)) +
    geom_ribbon(aes(ymin = p10, ymax = p90), fill = "#0a9396", alpha = 0.2) +
    geom_line(aes(y = p50, colour = "previsão (P50)"), linewidth = 0.9) +
    geom_line(aes(y = alvo, colour = "observada (balanço)"), linewidth = 0.9) +
    geom_line(aes(y = persist, colour = "persistência"), linetype = 2) +
    scale_colour_manual(values = c("previsão (P50)" = "#005f73", "observada (balanço)" = "#ee9b00", "persistência" = "grey50")) +
    facet_wrap(~h, ncol = 1) +
    labs(title = paste(nm, "· teste com chuva observada (melhor caso)"), x = NULL, y = "afluência (m³/s)",
         colour = NULL, caption = "faixa: P10–P90") +
    theme_minimal(base_size = 12) + theme(legend.position = "top")
  ggsave(sprintf("fase2/resultados/evento_%s.png", format(j[1], "%Y_%m")), g, width = 9, height = 8, dpi = 110)
}
message("figuras em fase2/resultados/")
