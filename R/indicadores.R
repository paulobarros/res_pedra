# Indicadores compartilhados entre o painel (index.qmd) e o relatório do
# Telegram (telegram_relatorio.R). Mantê-los aqui garante que o site e o bot
# usem exatamente as mesmas regras.
#
# Requer: dplyr, zoo

carregar_dados <- function(caminho = "data/pedra_dados.csv") {
  read.csv(caminho) |>
    dplyr::mutate(data = as.Date(data)) |>
    dplyr::arrange(dplyr::desc(data))
}

# Último dia com pelo menos uma medição
ultimo_registro <- function(df) {
  df |>
    dplyr::filter(dplyr::if_any(c(cota, afluencia, defluencia, volume), ~ !is.na(.x))) |>
    dplyr::slice(1)
}

fmt_num <- function(x, dig = 1) {
  if (is.na(x)) return("—")
  format(round(x, dig), nsmall = dig, decimal.mark = ",", big.mark = ".")
}

# Valor de `col` em `dias_atras` dias antes de `data_ref`
valor_em <- function(df, col, data_ref, dias_atras) {
  v <- df[[col]][df$data == data_ref - dias_atras]
  if (length(v) == 0) NA_real_ else v[1]
}

# Variação entre dois valores. `sentido`: "sobe" | "desce" | "igual" | NA
comparacao <- function(atual, anterior, unidade, rotulo, dig = 1) {
  if (is.na(atual) || is.na(anterior)) {
    return(list(sentido = NA_character_, texto = paste("sem dado para", rotulo)))
  }
  d <- atual - anterior
  sentido <- if (abs(d) < 10^-dig) "igual" else if (d > 0) "sobe" else "desce"
  sinal <- if (d > 0) "+" else if (d < 0) "−" else ""
  list(sentido = sentido, texto = paste0(sinal, fmt_num(abs(d), dig), unidade, " ", rotulo))
}

# ---- Janelas de anomalia (aumento de vazão) --------------------------------
# Para cada dia t: compara a média dos últimos `k` dias (t-k+1 .. t) com uma
# referência = média dos `n_ref` dias imediatamente anteriores à janela.
#
# intensidade = média da janela ÷ max(referência, ref_min)
#   - `ref_min` evita que a razão "exploda" quando a referência está perto de
#     zero (estiagem): 9 m³/s contra 0,5 m³/s não é 18× na prática.
#   - `min_dif` exige um aumento absoluto mínimo (m³/s) para marcar.
# `niveis` são os limiares da escala (nome = rótulo, valor = "× a referência").
# Janelas que se sobrepõem viram um intervalo só, com o nível mais alto.
anomalias_vazao <- function(dados, col, k = 3, n_ref = 15, niveis = c(Alta = 2),
                            ref_min = 0, min_dif = 5) {
  niveis <- sort(niveis)
  d <- dados |>
    dplyr::filter(!is.na(.data[[col]])) |>
    dplyr::arrange(data)
  x <- d[[col]]
  media_k <- zoo::rollapplyr(x, k, mean, fill = NA)
  ref <- dplyr::lag(zoo::rollapplyr(x, n_ref, mean, fill = NA), k)
  razao <- media_k / pmax(ref, ref_min)
  nivel <- findInterval(razao, niveis)          # 0 = normal, 1.. = índice do nível
  nivel[is.na(ref) | is.na(razao) | (media_k - ref) < min_dif] <- 0

  d <- d |> dplyr::mutate(referencia = round(ref, 1), nivel = nivel)

  idx <- which(nivel > 0)
  janelas <- dplyr::tibble(inicio = d$data[pmax(idx - k + 1, 1)], fim = d$data[idx], nivel = nivel[idx])
  if (nrow(janelas) > 1) {
    janelas <- janelas |>
      dplyr::arrange(inicio) |>
      dplyr::mutate(grupo = cumsum(as.numeric(inicio) > dplyr::lag(cummax(as.numeric(fim)), default = -Inf) + 1)) |>
      dplyr::summarise(inicio = min(inicio), fim = max(fim), nivel = max(nivel), .by = grupo) |>
      dplyr::select(-grupo)
  }
  janelas <- janelas |> dplyr::mutate(rotulo = names(niveis)[nivel])
  list(dados = d, janelas = janelas, niveis = niveis)
}

# Escala de intensidade da afluência (× a referência de 15 dias)
niveis_afluencia <- c("Moderada" = 2, "Alta" = 3, "Muito alta" = 5, "Extrema" = 10)

anomalias_afluencia <- function(df) {
  anomalias_vazao(df, "afluencia", k = 3, n_ref = 15,
                  niveis = niveis_afluencia, ref_min = 3, min_dif = 5)
}

# A defluência é quase constante, então um aumento de 20% já é relevante
anomalias_defluencia <- function(df) {
  anomalias_vazao(df, "defluencia", k = 3, n_ref = 15,
                  niveis = c(Alta = 1.2), min_dif = 1)
}

# Janela ainda "ativa": terminou no último dia com dado daquela série
janela_ativa <- function(an) {
  if (nrow(an$janelas) == 0) return(NULL)
  ult <- an$janelas |> dplyr::slice_max(fim, n = 1)
  if (ult$fim < max(an$dados$data)) return(NULL)
  ult
}
