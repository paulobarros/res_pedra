# Levantamento de dados para previsão de afluência de 7 dias: Reservatório da Pedra

Data do levantamento: 2026-11-19. Os testes foram feitos com `curl` e R (sf, terra) a partir de uma máquina local, sem credenciais e sem enviar dados pessoais.
Legenda: **[verificado]** quer dizer que acessei ou testei o endpoint ou documento nesta data. **[não verificado]** quer dizer que a informação vem de documentação secundária ou de memória e precisa ser confirmada.

## Resumo executivo

- **Afluência e defluência históricas da Pedra não existem como série pública.** O SAR/ANA (Nordeste e Semiárido) tem cota e volume diários da Pedra de 2012-08 a 2026-11, com lacunas, mas não tem vazões. O ONS não inclui a Pedra.
- **Há bons *proxies* de vazão.** A estação fluviométrica **52405000 Lagoa do Tamburi**, no Rio de Contas, drena 32.500 km², cerca de 80% da bacia da barragem, e tem série diária de **1984 a 2026**. A estação **52570000 Jequié**, logo a jusante, tem série de **1934 a 2026**. Ambas são acessíveis sem cadastro pelo webservice antigo da ANA.
- **Há telemetria horária a montante.** A estação **52405100 UHE Pedra Montante 1** fica no mesmo ponto de Lagoa do Tamburi, a cerca de 70 km da barragem, e mede vazão, nível e chuva. Ela respondeu com dados até 22h de hoje. Na cheia de 17 e 18/11/2026, o pico passou por lá antes de chegar à barragem.
- **Bacia delimitada.** Pela BHO/ANA, a área a montante do trecho da barragem é de **40.418 km²** (437 ottobacias). O polígono foi baixado pela API ArcGIS da ANA. No HydroBASINS nível 8, o polígono da barragem é 6080578530, com UP_AREA de 40.634 km².
- **Chuva.** O MERGE/CPTEC (0,1°, diário, publicado no mesmo dia) é a melhor fonte observada. A média na bacia já foi calculada em R: 22,2 mm em 18/11. Para previsão, a API de ensemble do Open-Meteo devolve 50 membros do ECMWF, 30 do GEFS e 39 do ICON, com precipitação e ET0, de graça para uso não comercial.
- **Recomendação:** começar por **(a) chuva prevista na bacia com alertas** e, em seguida, **(b) um modelo estatístico com defasagens** usando a telemetria de montante e a chuva MERGE. O **(c) GR4J** é viável depois, calibrado em Lagoa do Tamburi com mais de 30 anos de dados, mas tem ressalvas para o semiárido.

---

## 1. Série histórica longa do Reservatório da Pedra

| Fonte | Pedra presente? | Período | Variáveis | Acesso | Status |
|---|---|---|---|---|---|
| SAR/ANA, Nordeste e Semiárido (`/sar0/Medicao`) | Sim, código **12320** | 01/08/2012 a 19/11/2026, 3.678 registros (com lacunas; ver abaixo) | Cota (m), volume (hm³), volume (%), capacidade de 1.640 hm³ | HTTP GET, tabela HTML | **verificado** |
| SAR/ANA, SIN (`/sar0/MedicaoSin`) | Não. Só aparecem Pedra do Cavalo e Ponte de Pedra | n/a | n/a | n/a | **verificado** |
| ONS, dados abertos, "Dados hidrológicos de reservatórios" (diários) | Não. No Nordeste só há Itapebi, Pedra do Cavalo, Boa Esperança e as usinas do São Francisco | n/a | n/a | CSV/Parquet no S3 | **verificado** (arquivo de 2025) |
| HidroWeb: estações da própria barragem (52568080, 52569000, 52410100) | Existem no inventário | Não há série convencional de cota nem de vazão (consulta vazia) | n/a | Webservice | **verificado** |
| Telemetria ANA: 52568080 UHE PEDRA BARRAMENTO | Sim | Há dados horários em 2015, 2020, 2022 e 2026, com lacunas (vazio em 2010, 2012 e 2018) | Nível em cm (22142 = 221,42 m), vazão (cerca de 13 m³/s, compatível com a defluência da CHESF) e chuva | `DadosHidrometeorologicos` | **verificado**. O significado exato do campo "Vazao" (defluência ou turbinada) **não foi verificado** |

**Como acessar o SAR** (verificado). O formulário usa GET:
```
https://www.ana.gov.br/sar0/Medicao?dropDownListEstados=6&dropDownListReservatorios=12320&dataInicial=01/01/1990&dataFinal=19/11/2026&button=Buscar
```
A resposta é um HTML de cerca de 3 MB com `<table>`, colunas Estado, Reservatório, Capacidade, Cota, Volume, Volume (%) e Data. O botão "Salvar em Excel" (`/sar0/Medicao/ExportarExcel`) depende de sessão. O mais simples é usar `rvest::html_table()`.

Amostra real (verificado):

| Data | Cota (m) | Volume (hm³) | Volume (%) |
|---|---|---|---|
| 01/08/2012 | 212,12 | 501 | 30,55 |
| 01/04/2022 | 221,74 | 1085 | 66,16 |
| 01/04/2024 | 223,05 | 1180 | 71,95 |
| 01/12/2025 | 216,02 | 701 | 42,74 |
| 18/11/2026 | 221,40 | 1061 | 64,70 |

Registros por ano: 2012: 42, 2013: 319, 2014: 329, 2015: 244, **2016: 133, 2017: 138**, 2018: 262, **2019: 130**, 2020: 185, 2021: 213, 2022: 362, 2023: 316, 2024: 351, 2025: 343, 2026: 311.

Observações:
- A cota do SAR em 18/11/2026 (221,40) bate com a do CSV do repositório. O volume do SAR é o **total** (64,7% de 1.640 hm³). O da CHESF é o **útil** (54,58%), então não dá para misturar os dois sem conversão.
- Dá para reconstruir a afluência por balanço (ΔV + defluência), mas o resultado é ruim. A resolução de 1 hm³/dia equivale a cerca de 11,6 m³/s, e não existe defluência histórica pública da barragem. A própria afluência da CHESF, que também é calculada por balanço, é ruidosa (0, 37, 11 e 46 m³/s entre 14 e 17/11).
- **Proxy recomendado:** usar como afluência a vazão de **52405000 Lagoa do Tamburi** (32.500 km²) multiplicada pela razão de áreas (40.418/32.500 ≈ 1,24), ou a soma Tamburi + Jacaré (52406000) + incremental. Usar **52570000 Jequié** como proxy de defluência mais a contribuição incremental de cerca de 200 km². Ver a seção 2.

Fontes: https://www.ana.gov.br/sar/ , https://www.ana.gov.br/sar0/Medicao , https://www.ana.gov.br/sar0/MedicaoSin , https://dados.ons.org.br/dataset/dados-hidrologicos-res , https://ons-aws-prod-opendata.s3.amazonaws.com/dataset/dados_hidrologicos_di/DADOS_HIDROLOGICOS_RES_2025.csv

---

## 2. Estações a montante (fluviométricas e pluviométricas)

### Formas de acesso

| Serviço | Cadastro | O que entrega | Status |
|---|---|---|---|
| Webservice antigo `http://telemetriaws1.ana.gov.br/ServiceANA.asmx` | Não | `HidroInventario` (inventário por sub-bacia), `HidroSerieHistorica` (séries mensais com valores diários; tipoDados 1 = cota, 2 = chuva, 3 = vazão), `DadosHidrometeorologicos` (telemetria de 15 min ou horária, com consulta retroativa) | **verificado**, todas as chamadas abaixo funcionaram |
| API nova "Hidro Webservice" `https://www.ana.gov.br/hidrowebservice/` (OpenAPI em `/hidrowebservice/api-docs`) | **Sim**: `GET /EstacoesTelemetricas/OAUth/v1` com `Identificador` e `Senha` devolve um JWT bearer | `HidroSerieVazao`, `HidroSerieCotas`, `HidroSerieChuva`, `HidroinfoanaSerieTelemetricaAdotada/Detalhada` (v1/v2), `HidroInventarioEstacoes` etc. | Spec **verificada**. Chamadas autenticadas **não testadas**: exigem pedir credenciais à ANA, o que é um passo manual |
| Portal HidroWeb (download manual de CSV/ZIP) | Não | Séries históricas | https://www.snirh.gov.br/hidroweb/serieshistoricas , **não verificado** nesta sessão |

O exemplo abaixo foi verificado e serve de modelo para o pacote R (httr2 + xml2):
```
.../ServiceANA.asmx/HidroInventario?codEstDE=&codEstATE=&tpEst=1&nmEst=&nmRio=&codSubBacia=52&codBacia=&nmMunicipio=&nmEstado=&sgResp=&sgOper=&telemetrica=
.../ServiceANA.asmx/HidroSerieHistorica?codEstacao=52405000&dataInicio=&dataFim=&tipoDados=3&nivelConsistencia=
.../ServiceANA.asmx/DadosHidrometeorologicos?codEstacao=52405100&dataInicio=01/11/2026&dataFim=19/11/2026
```
Observação: o serviço antigo usa HTTP sem TLS. A ANA indica a API nova como sucessora, mas **não verifiquei** se há data oficial de desativação do antigo.

### Fluviométricas principais (sub-bacia 52; inventário verificado, séries verificadas)

| Código | Nome | Rio | Município | Lat, Lon | Área (km²) | Série de vazão diária | Telemetria |
|---|---|---|---|---|---|---|---|
| **52405000** | LAGOA DO TAMBURI | Contas | Manoel Vitorino | -13.878, -40.896 | 32.500 | 1984-11 a 2026-06 (consistida até 2023-12) | Não (ver 52405100) |
| **52405100** | UHE PEDRA MONTANTE 1 (AXIA) | Contas | Manoel Vitorino | -13.878, -40.897 | (o inventário diz 6.980, valor que parece errado; está no mesmo ponto de Tamburi) | não tem | **Sim**: vazão, nível e chuva. Dados em 2022 e até hoje |
| **52404000** | AREIÃO | Contas | Mirante | -14.031, -40.983 | 29.600 | 1969-06 a 2026-06 | Telemetria 2021-12 a 2023-09 (encerrada) |
| 52080120 | UHE PEDRA MONTANTE 2 (AXIA) | Contas | Contendas do Sincorá | -14.031, -40.982 | n/d | não tem | **Sim**: vazão, nível e chuva |
| **52270000** | SANTO ANTÔNIO | Contas | Tanhaçu | -14.096, -41.292 | 18.200 | **1935-03** a 2026-06 | Telemetria encerrada em 2023-09 |
| 52269510 | UHE PEDRA MONTANTE 3 (AXIA) | Contas | Tanhaçu | -14.096, -41.292 | n/d | não tem | **Sim** desde 2023-11: nível e chuva, sem vazão na amostra |
| **52391000** | EXU DO GAVIÃO | Gavião | Tanhaçu | -14.183, -41.015 | 10.100 | 2006-12 a 2026-06 | Encerrada em 2023-09 |
| 52370010 | UHE PEDRA RIO GAVIÃO (AXIA) | Gavião | Anagé | -14.610, -41.138 | n/d | não tem | **Sim**: nível e chuva |
| **52264000** | TOCADAS | Brumado | Aracatu | -14.109, -41.429 | 13.500 | 2000-11 a 2026-06 | Não |
| 52404100 | SINCORÁ | Sincorá | Barra da Estiva | -13.830, -40.982 | 1.350 | 2004-12 a 2026-06 | Não |
| 52406000 | JACARÉ | do Jacaré | Maracás | -13.762, -40.712 | 2.110 | 2005-11 a 2026-06 (intermitente; zero em vários dias) | Não |
| 52090000 | CRISTALÂNDIA | Contas | Brumado | -14.015, -41.445 | 3.370 | 1969 a 2010 (desativada) | Não |
| **52570000** | JEQUIÉ (jusante) | Contas | Jequié | -13.865, -40.081 | 40.400 | **1934-05** a 2026-06 | Encerrada em 2023-09 |
| 52570100 | UHE PEDRA JUSANTE (AXIA) | Contas | Jequié | -13.865, -40.081 | 42.890 | não tem | **Sim**: vazão e nível |

O Rio do Antônio (Salto ou do Antônio) só tem estações de açudes ou pontos INEMA (52230000 Açude Truvisco, 52248000 Brumado/INEMA), sem série longa de vazão no trecho principal.

Amostra real de telemetria horária, verificada em 19/11/2026 às 22h: 52405100 com vazão de 29,4 m³/s, nível de 233 cm e chuva de 0,2 mm. Médias diárias:

| Dia | 52080120 Montante 2, Q (m³/s) | 52405100 Montante 1, Q (m³/s) | Afluência CHESF (m³/s) | 52570100 Jusante, Q (m³/s) |
|---|---|---|---|---|
| 16/11 | 14,3 | 0,9 | 11 | 29,8 |
| 17/11 | 13,6 | 6,9 | 46 | 77,0 |
| 18/11 | 50,0 | 43,0 | 28 | 28,6 |
| 19/11 | 20,4 | 44,9 | n/d | 29,6 |

Nesse evento, Montante 1 sobe 1 a 2 dias antes de a afluência da barragem acompanhar. Isso serve de **preditor com antecedência de 1 a 2 dias**. A defasagem ainda precisa ser quantificada num histórico maior.

Formato da série histórica (verificado): um registro por mês com `Vazao01..Vazao31`, `Media`, `Maxima` e `NivelConsistencia` (1 = bruto, 2 = consistido). A série consistida vai até 2023-12 em quase todas as estações. Depois disso há dados brutos até 2026-06.

### Pluviométricas

Na caixa da bacia há 132 estações pluviométricas no inventário (58 marcadas como "operando" e 8 telemétricas). **Atenção:** as estações convencionais antigas do DNOCS aparecem como "operando", mas as séries terminam nos anos 1990. Por exemplo, 1341007 Contendas do Sincorá vai de 1933 a 1999-03, 1441016 Condeúba de 1911 a 1991 e 1341011 Rio de Contas de 1911 a 1991 (todas verificadas). Para o período recente, **a rede de superfície é rala e a chuva em grade é indispensável**.

Pluviômetros telemétricos verificados no inventário:

| Código | Nome | Município | Início da telemetria | Operador |
|---|---|---|---|---|
| 1340022 | UHE PEDRA BARRAMENTO | Jequié | 2018-11 (convencional desde 1943) | AXIA |
| 1340041 | UHE PEDRA MONTANTE 1 | Manoel Vitorino | 2020-02 | AXIA |
| 1440019 | UHE PEDRA AREIÃO | Mirante | 2019-11 | AXIA |
| 1441040 | UHE PEDRA RIO GAVIÃO | Anagé | 2019-11 | AXIA |
| 1441041 | UHE PEDRA MONTANTE 3 | Tanhaçu | 2023-11 | AXIA |
| 1341047 | LIVRAMENTO | Livramento de N. Sra. | 2015-07 | ANA |
| 1440037 | BOM JESUS DA SERRA | Bom Jesus da Serra | 2015-10 | ANA |
| 1441037 | JÂNIO QUADROS | Pres. Jânio Quadros | 2015-11 | ANA |

As estações fluviométricas telemétricas da AXIA (Montante 1, 2 e 3, Rio Gavião e Barramento) também devolvem chuva no `DadosHidrometeorologicos` (verificado).

Fontes: http://telemetriaws1.ana.gov.br/ServiceANA.asmx , https://www.ana.gov.br/hidrowebservice/api-docs , https://www.snirh.gov.br/hidroweb/

---

## 3. Delimitação da bacia

| Item | Valor | Fonte | Status |
|---|---|---|---|
| Coordenadas da barragem | -13.8689, -40.2358 (estação 52568080 UHE PEDRA BARRAMENTO) | Inventário ANA | **verificado** |
| Ottobacia BHO 2017 (50k) com a barragem | COBACIA **7723331**, COTRECHO 47178, curso d'água 772 (Rio de Contas), Strahler 5 | ArcGIS SNIRH `SPR/BHO2017_50K_AREADRENAGEM` | **verificado** |
| Área a montante (NUAREAMONT do trecho) | **40.417,7 km²** (a barragem fica dentro do trecho; a área contribuinte do trecho é de 173 km²) | `SPR/BHO2017_50K_TRECHODRENAGEM` | **verificado** |
| Área no inventário ANA | 38.720 km² (52568080) ou 40.200 km² (52569000) | Inventário | **verificado** (valores divergentes) |
| HydroBASINS v1c nível 8 | HYBAS_ID **6080578530**, UP_AREA **40.634 km²**, 67 polígonos a montante | hybas_sa_lev08_v1c | **verificado** |
| HydroBASINS níveis 6 e 7 | 6060581120 / 6070581120, UP_AREA de 42.346 km². O polígono avança para jusante da barragem, então não serve sozinho | idem | **verificado** |
| Extensão | lon -42,59 a -40,08; lat -15,19 a -12,94 | Polígono BHO dissolvido | **verificado** |

**Como obter o polígono por código** (verificado). As 437 ottobacias a montante seguem a regra de Pfafstetter `COBACIA >= '7723331' AND COCURSODAG LIKE '772%'`:
```
https://www.snirh.gov.br/arcgis/rest/services/SPR/BHO2017_50K_AREADRENAGEM/FeatureServer/0/query?where=COBACIA%20%3E%3D%20%277723331%27%20AND%20COCURSODAG%20LIKE%20%27772%25%27&outFields=COBACIA,NUAREACONT&returnGeometry=true&outSR=4326&f=geojson
```
O arquivo tem cerca de 7,5 MB. Basta fazer `sf::st_union()` e simplificar. A soma de NUAREACONT dá 40.417,7 km². O HydroBASINS é baixado em https://data.hydrosheds.org/file/hydrobasins/standard/hybas_sa_lev08_v1c.zip (30 MB, sem cadastro); depois é só subir o grafo `NEXT_DOWN`.

**Afluentes principais** (inventário e BHO): Brumado (com o Rio do Paulo e o Riacho de Santa Maria), do Antônio (Salto ou do Antônio, que nasce em Caculé e Licínio de Almeida), São João, Gavião (com o Champrão e o Riacho da Ressaca; Açude Anagé), Ourives, Sincorá e do Jacaré (margem esquerda, pela região de Maracás).

**Municípios** (interseção da BHO com a malha IBGE; 46 municípios com mais de 50 km² dentro da bacia; verificado). Os maiores são Brumado, Livramento de Nossa Senhora, Anagé, Maracás (64%), Aracatu, Barra da Estiva, Manoel Vitorino, Tremedal, Condeúba, Tanhaçu, Presidente Jânio Quadros, Ituaçu, Caetité (45%), Jacaraci, Iramaia, Jequié (36%), Mirante, Rio de Contas, Contendas do Sincorá, Lagoa Real, Guajeru, Licínio de Almeida, Caraíbas, Rio do Antônio, Caetanos, Piatã, Dom Basílio, Vitória da Conquista (19%), Maetinga, Caculé, Jussiape, Malhada de Pedras, Abaíra, Cordeiros, Mortugaba, Piripá, Paramirim, Ibiassucê, Belo Campo, Mucugê, Bom Jesus da Serra, Planalto, Poções, Ibicoara, Marcionílio Souza e Lafaiete Coutinho. A bacia fica toda na Bahia.

Fontes: https://www.snirh.gov.br/arcgis/rest/services/SPR , https://www.hydrosheds.org/products/hydrobasins , https://servicodados.ibge.gov.br/api/docs/malhas

---

## 4. Dados de chuva

### 4.1 Observada em grade

| Produto | Acesso | Resolução | Latência (observada) | Licença | Status |
|---|---|---|---|---|---|
| **MERGE/CPTEC** (IMERG Late + pluviômetros) | HTTPS sem cadastro: `https://ftp.cptec.inpe.br/modelos/tempo/MERGE/GPM/DAILY/AAAA/MM/MERGE_CPTEC_AAAAMMDD.grib2` (cerca de 470 KB/dia, com `.ctl`/`.idx`). O histórico de 1998 a 2024 está em `MERGE_NEW_1998_2024.tar.gz` (4,1 GB) | 0,1°, cerca de 337 células na bacia; acumulado diário das 12Z às 12Z; variáveis PREC e NEST (número de estações) | **Mesmo dia**: o arquivo de 19/11 foi modificado às 16:18 UTC de 19/11 | Dados públicos do INPE. Citar Rozante et al. (2010). A licença formal **não foi verificada** | **verificado**. Li com `terra::rast()` em R: a média na bacia foi de **22,24 mm** em 18/11/2026, com máximo de 67 mm na célula |
| **CHIRPS v3.0** | `https://data.chc.ucsb.edu/products/CHIRPS/v3.0/daily/final/{sat,rnl}/AAAA/chirps-v3.0.sat.AAAA.MM.DD.tif` (também há COG, netCDF e p25) | 0,05° | O diário final mais recente é de **2026-10-31** (cerca de 3 semanas). O preliminar só sai em pêntadas, 2 dias após o fim de cada pêntada | Domínio público ou CC, conforme o site do CHC (**não verificado** nesta sessão) | **verificado** (listagem e README). O diário é uma **desagregação** da pêntada usando ERA5 (rnl) ou IMERG (sat); o próprio README recomenda usar pêntadas ou totais mensais. O caminho do CHIRPS 2.0 diário devolveu **404** |
| **GPM IMERG V07** | NASA GES DISC: `https://gpm1.gesdisc.eosdis.nasa.gov/data/GPM_L3/GPM_3IMERGDE.07/` (Early), `GPM_3IMERGDL.07` (Late), `GPM_3IMERGDF.07` (Final). **Precisa de login no Earthdata**: o download redireciona para `urs.earthdata.nasa.gov`; a listagem é aberta | 0,1°, meia-hora e diário | Early e Late: o arquivo diário mais recente era de 18/11/2026. Final: o mais recente era de 2025-09-30 | Dados da NASA, sem restrição de uso (cadastro gratuito) | **verificado** (listagens e redirecionamento de autenticação) |

Para o painel, o **MERGE** é a melhor opção: não exige cadastro, sai no mesmo dia, incorpora pluviômetros brasileiros e tem histórico desde 1998 para calibrar.

### 4.2 Previsão (7 dias ou mais, com ensemble)

**API de ensemble do Open-Meteo** (`https://ensemble-api.open-meteo.com/v1/ensemble`). Modelos globais, segundo a página de documentação (verificado):

| Modelo (`models=`) | Resolução | Membros | Horizonte |
|---|---|---|---|
| ECMWF IFS 0.25° (`ecmwf_ifs025`) | 25 km, 3 h | 51 | 15 d |
| ECMWF AIFS 0.25° | 25 km, 6 h | 51 | 15 d |
| NOAA GEFS 0.25° (`gfs025`) | 25 km, 3 h | 31 | 10 d |
| NOAA GEFS 0.5° | 50 km, 3 h | 31 | 35 d |
| AIGFS 0.25° | 25 km, 6 h | 31 | 16 d |
| DWD ICON-EPS (`icon_global`) | cerca de 13 km, 1 h | 40 | 7,5 d |
| GEM global (Canadá) | 25 km, 3 h | 21 | 16 d (39 d às segundas e quintas) |
| UKMO MOGREPS-G | 20 km, 1 h | 18 | 8 d |
| Google WeatherNext 2 | 25 km, 6 h | 64 | 15 d |
| BOM ACCESS-GE | 40 km | 18 | 10 d (sem atualização desde 2025-06-26) |

As variáveis testadas foram `hourly=precipitation` e `daily=precipitation_sum,et0_fao_evapotranspiration`. Ambas funcionaram, inclusive ET0 por membro.

**Teste real** (verificado), no centróide da bacia, -14.19/-41.49:
```
GET .../v1/ensemble?latitude=-14.19&longitude=-41.49&daily=precipitation_sum,et0_fao_evapotranspiration&hourly=precipitation&models=ecmwf_ifs025,gfs025,icon_global&forecast_days=10&timezone=America%2FBahia
```
O que voltou:
- **Formato:** um objeto JSON com `latitude`/`longitude` ajustadas à grade (-14.25/-41.5), `elevation: 414`, `hourly_units`, `daily_units`, `hourly` (240 passos) e `daily` (10 dias, de `time` 2026-11-19 a 2026-11-28).
- **Nomes das colunas:** uma coluna por membro, como `precipitation_sum_member01_ecmwf_ifs025_ensemble` até `member50`, mais o controle `precipitation_sum_ecmwf_ifs025_ensemble`, `..._ncep_gefs025` (30 membros) e `..._icon_global_eps` (39 membros). Os aliases pedidos foram renomeados na saída: daily tem 245 chaves e hourly 123.
- **Valores do ECMWF:** a mediana diária da precipitação foi 14,3 / 6,1 / 1,8 / 2,4 / 4,8 / 0,2 / 0 mm, com máximo de 30,9 mm no dia 1. A ET0 do membro 1 ficou entre 4,5 e 6,9 mm/d.
- **Vários pontos:** `latitude=a,b&longitude=c,d` devolve uma **lista** de objetos (verificado com 2 pontos). Para média na bacia, a sugestão é amostrar uma grade de cerca de 10 a 20 pontos dentro do polígono e ponderar.
- **Cabeçalhos:** `X-RateLimit-Limit: 600`, `X-RateLimit-Window: 60` e **`X-RateLimit-Cost: 36.6`** para essa chamada. Chamadas com muitos modelos e variáveis consomem várias "unidades" de cota.

**Termos de uso para uso não comercial** (verificado em https://open-meteo.com/en/terms): menos de **10.000 chamadas por dia, 5.000 por hora e 600 por minuto**; somente uso não comercial; dados sob **CC-BY 4.0** (é obrigatório atribuir); bloqueio por IP em caso de abuso. Rodar 1 a 4 vezes por dia no GitHub Actions fica muito abaixo do limite. Não convém rodar de hora em hora com muitos pontos.

**CPTEC Eta** (verificado por listagem):
- Eta 40 km: `https://ftp.cptec.inpe.br/modelos/tempo/Eta/ams_40km/brutos/AAAA/MM/DD/HH/eta_40km_AAAAMMDDHH+AAAAMMDDHH.grb`. A rodada 2026111900 vai até 2026113000, ou seja, **11 dias**.
- Eta 8 km: `https://dataserver.cptec.inpe.br/dataserver_modelos/eta/ams_08km/brutos/AAAA/MM/DD/HH/Eta_ams_08km_AAAAMMDDHH_AAAAMMDDHH.grib2`, também até +11 dias.
- É **determinístico**. Não encontrei um ensemble Eta operacional nesses diretórios (o diretório `OENSMB09` tem só `TQ0126L028`, global). Precisa de GRIB. É útil como membro extra, regional e brasileiro, mas dá mais trabalho que o Open-Meteo.

Fontes: https://open-meteo.com/en/docs/ensemble-api , https://open-meteo.com/en/terms , https://ftp.cptec.inpe.br/modelos/tempo/MERGE/GPM/DAILY/ , https://data.chc.ucsb.edu/products/CHIRPS/v3.0/README-CHIRPSv3.0.txt , https://data.chc.ucsb.edu/products/CHIRPS/v3.0/daily/final/readme.txt , https://gpm1.gesdisc.eosdis.nasa.gov/data/GPM_L3/ , https://ftp.cptec.inpe.br/modelos/tempo/Eta/

---

## 5. GR4J no airGR

| Item | Detalhe | Fonte | Status |
|---|---|---|---|
| Pacote | airGR 1.7.9 (CRAN, 2026-07-08), GPL-2. Inclui GR4H, GR5H, GR4J, GR5J, GR6J, GR2M e GR1A, em modo concentrado ou semidistribuído | https://cran.r-project.org/package=airGR | **verificado** (não está instalado nesta máquina) |
| Entradas | Passo **diário**: datas (POSIXt), precipitação média na bacia (mm/d) e ETP (mm/d). Vazão observada em mm/d para calibrar. **Não aceita NA em P nem em ETP**; NA é permitido na vazão. A ETP pode ser calculada por `PE_Oudin()` (dia juliano, temperatura média e latitude) | https://hydrogr.github.io/airGR/page_1_get_started.html | **verificado** |
| Aquecimento | "igual ou superior a um ano" | idem | **verificado** |
| Calibração | `Calibration_Michel` (varredura global seguida de busca local) com `ErrorCrit_NSE` ou `ErrorCrit_KGE`. O guia **não** fixa um comprimento mínimo de calibração | idem | **verificado** |
| Comprimento recomendado | A literatura do INRAE (Perrin et al. 2007, *HSJ* 52(1)) indica que modelos parcimoniosos se estabilizam com poucos anos, desde que haja anos úmidos e secos | — | **não verificado** (memória) |
| Semiárido e intermitência | Não achei artigo revisado por pares com GR4J em bacia intermitente do semiárido brasileiro. Há TCCs e dissertações que usam o GR4J como referência em bacias do Ceará (UFC 2022, 21 estações, dados escassos) e de Pernambuco (Capibaribe, Pajeú e Moxotó, comparado ao CAWM IV; bom desempenho "na maioria dos eventos"). A literatura internacional aponta baixa robustez e transferibilidade de parâmetros em bacias áridas e muito assimétricas e dificuldade com eventos de vários picos (EGU25, Djibouti; HESS 2026) | https://repositorio.ufc.br/ri/bitstream/riufc/76813/3/2022_tcc_lfsmoreira.pdf , https://attena.ufpe.br/bitstream/123456789/40725/1/DISSERTA%c3%87%c3%83O%20Maria%20Alice%20Britto%20Feitoza%20%281%29.pdf , https://www.scielo.br/j/rbrh/a/kkTNTn585LdhDprrDTZzKyK/?lang=en , https://presentations.copernicus.org/EGU25/EGU25-16491_presentation.pdf , https://hess.copernicus.org/articles/30/3903/2026/hess-30-3903-2026.pdf | Busca feita; textos completos **não lidos** (o SciELO devolveu 502) |
| Alternativas | **GR5J** (troca intercaptação com limiar) e **GR6J** (reservatório exponencial, melhor para recessões e estiagens), ambos no airGR. **SMAP** (usado pelo ONS e na FUNCEME/CE), **CAWM IV** (UFPE, feito para o semiárido) e **WASA** (físico, Ceará; em Aiuaba não representou intermitência e vazão ao mesmo tempo) | CRAN airGR; SciELO RCA (Umbuzeiro) | Parcialmente verificado |

Ressalvas específicas da Pedra:
1. Cerca de 40 mil km² de caatinga e cerrado, com açudes a montante (Anagé, Tremedal, Champrão, Truvisco, Luiz Vieira, Cristalândia), retiradas e perdas por transmissão no leito. A chuva concentrada na Chapada Diamantina (Piatã, Rio de Contas, Barra da Estiva) pesa mais que a média da bacia. Um GR4J concentrado tende a errar a primeira cheia da estação.
2. A calibração é viável: Lagoa do Tamburi tem mais de 30 anos de vazão diária consistida (1984 a 2023), e o MERGE tem chuva de 1998 em diante. Isso dá **cerca de 25 anos de sobreposição**, de sobra. Um modelo semidistribuído em 3 ou 4 sub-bacias (Brumado/Tocadas, Contas/Santo Antônio, Gavião/Exu, incremental) é possível com `airGR` (`page_5_sd_model`).
3. Os dados da barragem (140 dias, quase todos no período seco) **não servem para calibrar**. Servem só para validar e corrigir viés operacional.

---

## Recomendação de próximos passos

**Veredito:** (a) é viável já. (b) é viável e é o melhor custo-benefício para 1 a 3 dias, com previsão probabilística até 7 dias. (c) é viável como fase 3, porque há dados para calibrar, mas exige mais esforço e pode ter desempenho modesto na intermitência.

| Fase | Entrega | Dados | Esforço |
|---|---|---|---|
| **1: Chuva na bacia e alertas (a)** | Script R horário ou 4 vezes ao dia: polígono BHO (salvo no repositório), média ponderada na bacia do ensemble Open-Meteo (ECMWF + GEFS + ICON) para 7 a 10 dias, com percentis P10/P50/P90 e probabilidade de mais de 10/25/50 mm em 3 dias. Chuva observada do MERGE do dia anterior. Telemetria ANA de 52405100, 52080120 e 52370010 (vazão e nível a montante). Alerta no Telegram quando Montante 1 passar de X m³/s ou quando a chuva prevista P50 em 3 dias passar de Y mm | Open-Meteo, MERGE, webservice ANA (sem cadastro) | Baixo |
| **2: Modelo estatístico com defasagens (b)** | Montar a base histórica: Q de Tamburi (52405000) ×1,24 como proxy de afluência (1984 a 2026), chuva MERGE na bacia e nas sub-bacias (1998 a 2026) e telemetria de Montante 1 (2020 a 2026, com lacunas). Ajustar um modelo diário Q(t+h) ~ Q(t), Q(t-1), chuva acumulada de 1, 3 e 7 dias, chuva prevista e índice de umidade antecedente (por exemplo, GAM ou regressão quantílica; modelo em dois estágios, ocorrência e magnitude, por causa dos zeros). Rodar com cada membro do ensemble para obter a faixa de afluência. Validar contra a afluência da CHESF já coletada | Seção 2 + MERGE | Médio |
| **3: GR4J/GR6J (c)** | airGR com P = MERGE na bacia e ETP = Oudin ou ET0 (ERA5 ou Open-Meteo histórico). Calibrar em Tamburi de 1998 a 2015 e validar de 2016 a 2023 (KGE). Testar GR6J e uma versão semidistribuída. Previsão por ensemble: aquecer com o MERGE até hoje e forçar com os membros do Open-Meteo. Assimilar a vazão de Montante 1 (corrigindo o estado do reservatório de roteamento) | Idem + ETP | Médio a alto |
| **4: Pendências manuais** | (i) Pedir credenciais da API HidroWebService da ANA, para o caso de o serviço antigo sair do ar. (ii) Conta Earthdata, se o IMERG for necessário. (iii) Confirmar com a AXIA ou a ANA o significado do campo "Vazao" em 52568080 e a curva cota-área-volume, para reconstruir a afluência a partir do nível telemétrico | — | — |

Não verificado ou em aberto: licenças formais do MERGE e do CHIRPS v3; textos completos dos estudos sobre GR4J no semiárido; data de desativação do webservice antigo da ANA; semântica do campo "Vazao" das estações da AXIA; área de drenagem correta de 52405100 (o inventário diz 6.980 km², o que é inconsistente com a localização).
