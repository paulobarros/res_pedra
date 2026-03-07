# library(rvest)
# library(dplyr)
# library(tidyr)
# library(here)
# library(lubridate)


# url_chesf <- "https://www.chesf.com.br/SistemaChesf/Pages/GestaoRecursosHidricos/GestaoRecursosHidricos.aspx"

# # 1. Comando otimizado para ignorar erros de sistema e focar no DOM
# # Adicionamos 2> /dev/null para esconder as mensagens de erro do terminal
# message("Acessando Chesf... Isso pode levar uns 15 segundos.")

# cmd <- paste0("chromium --headless --disable-gpu --dump-dom --virtual-time-budget=15000 '", url_chesf, "' 2>/dev/null")

# html_raw <- system(cmd, intern = TRUE) |>
#   paste(collapse = "\n")

# # 2. Processar com rvest
# page <- read_html(html_raw)

# xpath_header <- "//h2[contains(., 'PEDRA')]/following::table[1]"
# header_table <- page |> 
#   html_element(xpath = xpath_header) |> 
#   html_table() |> 
#   colnames() # Pegamos os nomes das colunas

# # 2. Capturar os Dados (A segunda tabela após o H2)
# xpath_data <- "//h2[contains(., 'PEDRA')]/following::table[2]"
# data_table <- page |> 
#   html_element(xpath = xpath_data) |> 
#   html_table(header = FALSE) # Lemos sem cabeçalho, pois ela é só dados

# # 3. Ajustar os nomes das colunas
# # Às vezes o header_table vem como uma lista, garantimos que seja um vetor
# colnames(data_table) <- c("data", "cota","afluencia","defluencia","volume")

# # 4. Limpeza Básica (Remover linhas vazias que o ASPX costuma gerar)
# df_final <- data_table |>
#   mutate(data = paste0(data,"/2026") |>
#   dmy()) |>
#   mutate(across(cota:volume, ~as.numeric(.)))

# write.csv(df_final,here("data","pedra_dados.csv"), row.names = F)


library(rvest)
library(dplyr)
library(tidyr)
library(here)
library(lubridate)

url_chesf <- "https://www.chesf.com.br/SistemaChesf/Pages/GestaoRecursosHidricos/GestaoRecursosHidricos.aspx"

# --- BLOCO COM LOOP WHILE ADICIONADO ---
max_tentativas <- 5
tentativa <- 0
dados_obtidos <- FALSE

while (!dados_obtidos && tentativa < max_tentativas) {
  tentativa <- tentativa + 1
  message(paste0("Tentativa ", tentativa, ": Acessando Chesf... Isso pode levar uns 15 segundos."))
  
  # Seu comando original
  cmd <- paste0("chromium --headless --disable-gpu --dump-dom --virtual-time-budget=15000 '", url_chesf, "' 2>/dev/null")
  
  html_raw <- system(cmd, intern = TRUE) |> paste(collapse = "\n")
  page <- read_html(html_raw)
  
  # Tenta localizar o elemento da tabela de dados
  xpath_data <- "//h2[contains(., 'PEDRA')]/following::table[2]"
  node_data <- page |> html_element(xpath = xpath_data)
  
  # Verifica se o elemento existe e se contém dados (não está vazio)
  if (!is.na(node_data)) {
    data_table <- node_data |> html_table(header = FALSE)
    if (nrow(data_table) > 0) {
      dados_obtidos <- TRUE
    }
  }
  
  if (!dados_obtidos && tentativa < max_tentativas) {
    message("Tabela vazia ou não encontrada. Aguardando 10s para tentar novamente...")
    Sys.sleep(10)
  }
}

# Interrompe com erro se falhar em todas as tentativas (evita que a Action rode com lixo)
if (!dados_obtidos) {
  stop("Erro: Não foi possível capturar os dados da CHESF após ", max_tentativas, " tentativas.")
}
# ---------------------------------------

# 3. Ajustar os nomes das colunas (Mantendo seu original)
colnames(data_table) <- c("data", "cota","afluencia","defluencia","volume")

# 4. Limpeza Básica (Mantendo seu original)
df_final <- data_table |>
  mutate(data = paste0(data,"/2026") |>
  dmy()) |>
  mutate(across(cota:volume, ~as.numeric(.)))

write.csv(df_final, here("data","pedra_dados.csv"), row.names = F)