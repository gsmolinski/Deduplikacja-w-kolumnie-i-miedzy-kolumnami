library(shiny)
library(shinythemes)
library(shinyalert)
library(readxl)
library(data.table)
library(tidyverse)
library(stringi)
library(writexl)
library(shinydisconnect)
library(lubridate)

setDTthreads(threads = 0)

options(scipen = 999, shiny.maxRequestSize = 1000 * 1024 ^ 2)

zredukuj_liste_zdublowanych_id <- function(zdublowane_id_jedno, zdublowane_id_wszystkie) {
    zdublowane_id_jedno_wektor <- unlist(stri_split_fixed(zdublowane_id_jedno, ", "), use.names = FALSE)
    zdublowane_id_calosc <- map(zdublowane_id_jedno_wektor, ~ ifelse(stri_detect_regex(zdublowane_id_wszystkie, stri_c("^", ., ",", "|", "\\s", ., ",", "|", "\\s", ., "$")), stri_c(stri_c(zdublowane_id_jedno_wektor, collapse = ", "), zdublowane_id_wszystkie, sep = ", "), NA))
    zdublowane_id_calosc <- sort(unique(unlist(stri_split_fixed(unlist(zdublowane_id_calosc, use.names = FALSE), ", "), use.names = FALSE)))
    zdublowane_id_calosc <- stri_c(zdublowane_id_calosc[!is.na(zdublowane_id_calosc)], collapse = ", ")
    zdublowane_id_calosc
}

zbierz_informacje_do_rozszerzenia <- function(kolumny_do_rozszerzenia_wybrane, plik_zdublowane, id_najdluzsze) {
    informacje <- unique(unlist(lapply(plik_zdublowane[, .SD, .SDcols = kolumny_do_rozszerzenia_wybrane], function(x) x), use.names = FALSE))
    informacje <- sort(informacje)
    if (length(informacje) < id_najdluzsze * length(kolumny_do_rozszerzenia_wybrane)) {
        braki_dodatkowe <- rep(NA, (id_najdluzsze * length(kolumny_do_rozszerzenia_wybrane)) - length(informacje))
        informacje <- c(informacje, braki_dodatkowe)
    }
    informacje
}

ujednolic_informacje_dla_zdublowanych_id <- function(plik_id_kolumny_do_deduplikacji_duble, plik, kolumny_do_rozszerzenia_wybrane, kolumny_do_deduplikacji_wybrane, wszystkie_kolumny_do_rozszerzenia, id_najdluzsze) {
    id_do_filtrowania <- unlist(stri_split_fixed(plik_id_kolumny_do_deduplikacji_duble, ", "), use.names = FALSE)
    plik_zdublowane <- plik[id_do_deduplikacji_dt %in% id_do_filtrowania]
    if (!is.null(kolumny_do_rozszerzenia_wybrane)) {
        informacje_1 <- zbierz_informacje_do_rozszerzenia(kolumny_do_deduplikacji_wybrane, plik_zdublowane, id_najdluzsze)
        informacje_1 <- c(informacje_1[!is.na(informacje_1)], informacje_1[is.na(informacje_1)])
        informacje_2 <- unlist(lapply(sort(kolumny_do_rozszerzenia_wybrane[!kolumny_do_rozszerzenia_wybrane %in% kolumny_do_deduplikacji_wybrane]), zbierz_informacje_do_rozszerzenia, plik_zdublowane = plik_zdublowane, id_najdluzsze = id_najdluzsze), use.names = FALSE)
        informacje <- c(informacje_1, informacje_2)
        plik_zdublowane <- sample_n(plik_zdublowane, 1)
        plik_zdublowane <- plik_zdublowane[, (wszystkie_kolumny_do_rozszerzenia) := lapply(informacje, function(x) x)]
    } else {
        plik_zdublowane <- sample_n(plik_zdublowane, 1)
    }
    plik_zdublowane
}

sprawdzenie_numeric <- function(plik) {
    if (!all(is.na(plik))) {
        plik <- plik[!is.na(plik)]
        all(stri_detect_regex(plik, "^\\d+$"))
    } else {
        FALSE
    }
}

ui <- fluidPage(theme = shinytheme("journal"),
                 disconnectMessage(
                     text = "Wystąpił błąd. Spróbuj ponownie lub skontaktuj się z osobą odpowiedzialną za aplikację.",
                     refresh = "Odśwież",
                     background = "#C2BC66",
                     colour = "#F8F8F8",
                     refreshColour = "#F74A7E",
                     overlayColour = "#70B2BD",
                     overlayOpacity = 1,
                     width = 450,
                     top = "center",
                     size = 24,
                     css = "font-family: Lucida;"
                 ),
                  useShinyalert(),
                  titlePanel(h1("Deduplikacja", id = "title"), windowTitle = "Deduplikacja"),
                  br(),
                  fluidRow(
                      column(3, fileInput("plik_do_deduplikacji", label = "Wybierz plik do deduplikacji", accept = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", buttonLabel = "Plik .xlsx", placeholder = "  Nie wybrano pliku.", width = "100%")),
                      column(4, htmlOutput(outputId = "kolumny_do_deduplikacji")),
                      column(5, htmlOutput(outputId = "kolumny_do_rozszerzenia"))
                  ),
                 fluidRow(
                     column(2, actionButton(inputId = "deduplikuj", label = "Deduplikuj", width = "100%")),
                     column(1, htmlOutput(outputId = "deduplikacja_gotowa")),
                     column(2, downloadButton(outputId = "pobierz_plik_po_deduplikacji", label = "Pobierz plik"))
                 ),
                 br(),
                 br(),
                 br(),
                 br(),
                 br(),
                 fluidRow(
                     column(10, htmlOutput(outputId = "instrukcja"))
                 ),
                 tags$style("
             * {
                font-family: Helvetica;
                font-size: 15px;
                }
             "),
                 tags$head(tags$style(
                     HTML('#title {
            font-family: Helvetica;
           color: #7A90B1;
           font-size: 40px;
           font-style: bold;
          }
               .shiny-notification {
              height: 50px;
              width: 400px;
              position:fixed;
              top: calc(50% - 50px);;
              left: calc(50% - 200px);;
            }'
                     ))),
)

server <- function(input, output) {
    wczytaj_plik <- reactive({
        plik <- input$plik_do_deduplikacji
        if (is.null(plik)) {
            return(NULL)
        }
        read_excel(plik$datapath, col_types = "text")
    })
    
    output$kolumny_do_deduplikacji <- renderUI({
        plik <- wczytaj_plik()
        selectInput(inputId = "kolumny_do_deduplikacji_wybrane", label = "Kolumny do deduplikacji", multiple = TRUE, choices = colnames(plik), width = "100%")
    })
    
    output$kolumny_do_rozszerzenia <- renderUI({
        plik <- wczytaj_plik()
        kolumny_do_deduplikacji_wybrane <- input$kolumny_do_deduplikacji_wybrane
        selectInput(inputId = "kolumny_do_rozszerzenia_wybrane", label = "Kolumny, które będą rozszerzone o dodatkowe informacje", multiple = TRUE, choices = colnames(plik), selected = kolumny_do_deduplikacji_wybrane, width = "100%")
    })
    
    deduplikuj <- eventReactive(input$deduplikuj, {
        withProgress(message = "Deduplikowanie", {
            plik <- wczytaj_plik()
            kolumny_do_deduplikacji_wybrane <- input$kolumny_do_deduplikacji_wybrane
            kolumny_do_rozszerzenia_wybrane <- input$kolumny_do_rozszerzenia_wybrane
            if (!is.null(kolumny_do_rozszerzenia_wybrane)) {
                test <- all(kolumny_do_deduplikacji_wybrane %in% kolumny_do_rozszerzenia_wybrane)
            } else {
                test <- TRUE
            }
            if (!is.null(plik) && !is.null(kolumny_do_deduplikacji_wybrane) && !any(is.na(plik[, kolumny_do_deduplikacji_wybrane[1]])) && all(c(kolumny_do_deduplikacji_wybrane, kolumny_do_rozszerzenia_wybrane) %in% names(plik)) && all(stri_detect_regex(names(plik), "\\n", negate = TRUE)) && all(stri_detect_regex(names(plik), "^\\w+$")) && test) {
                plik <- as.data.table(plik)
                plik[, id_do_deduplikacji_dt := 1:.N]
                plik_id_kolumny_do_deduplikacji <- plik[, .SD, .SDcols = c("id_do_deduplikacji_dt", kolumny_do_deduplikacji_wybrane)]
                plik_id_kolumny_do_deduplikacji <- melt.data.table(plik_id_kolumny_do_deduplikacji, id.vars = "id_do_deduplikacji_dt", variable.name = "nazwa_kolumny", value.name = "wartosc_kolumny", variable.factor = FALSE)
                incProgress(0.1)
                plik_id_kolumny_do_deduplikacji[, nazwa_kolumny := NULL]
                plik_id_kolumny_do_deduplikacji <- plik_id_kolumny_do_deduplikacji[!is.na(wartosc_kolumny)]
                plik_id_kolumny_do_deduplikacji[, duble := .GRP, by = wartosc_kolumny]
                plik_id_kolumny_do_deduplikacji[, zdublowane_id := stri_c(id_do_deduplikacji_dt, collapse = ", "), by = duble]
                incProgress(0.1)
                plik_id_kolumny_do_deduplikacji <- plik_id_kolumny_do_deduplikacji[, .(zdublowane_id)]
                plik_id_kolumny_do_deduplikacji_duble <- plik_id_kolumny_do_deduplikacji[, test := lapply(zdublowane_id,  stri_detect_fixed, pattern = ", ")]
                incProgress(0.1)
                plik_id_kolumny_do_deduplikacji_duble <- plik_id_kolumny_do_deduplikacji_duble[test == TRUE]
                plik_id_kolumny_do_deduplikacji_duble[, test := NULL]
                plik_id_kolumny_do_deduplikacji_duble[, zdublowane_id_temp := lapply(zdublowane_id, function(x) stri_c(sort(unlist(stri_split_fixed(x, ", "), use.names = FALSE)), collapse = ", "))]
                incProgress(0.1)
                plik_id_kolumny_do_deduplikacji_duble <- plik_id_kolumny_do_deduplikacji_duble[, .(zdublowane_id = unlist(zdublowane_id_temp, use.names = FALSE))]
                if (plik_id_kolumny_do_deduplikacji_duble[, .N] > 0) {
                    plik_id_kolumny_do_deduplikacji_duble <- unique(plik_id_kolumny_do_deduplikacji_duble, by = "zdublowane_id")
                    plik_id_kolumny_do_deduplikacji_duble <- plik_id_kolumny_do_deduplikacji_duble[, zdublowane_id := fifelse(stri_detect_fixed(zdublowane_id, ","), zdublowane_id, NA_character_)][!is.na(zdublowane_id)]
                    incProgress(0.2)
                    plik_id_kolumny_do_deduplikacji_duble <- plik_id_kolumny_do_deduplikacji_duble[, .(zdublowane_id = unlist(lapply(zdublowane_id, zredukuj_liste_zdublowanych_id, zdublowane_id_wszystkie = zdublowane_id), use.names = FALSE))]
                    plik_id_kolumny_do_deduplikacji_duble <- unique(plik_id_kolumny_do_deduplikacji_duble, by = "zdublowane_id")
                    same_id <- unique(unlist(map(plik_id_kolumny_do_deduplikacji_duble$zdublowane_id, ~ as.integer(unlist(stri_split_fixed(., ", "), use.names = FALSE)))))
                    wszystkie_kolumny_do_rozszerzenia <- NULL
                    if (!is.null(kolumny_do_rozszerzenia_wybrane)) {
                        id_najdluzsze <- max(stri_count_boundaries(plik_id_kolumny_do_deduplikacji_duble$zdublowane_id))
                        dodatkowe_kolumny_do_rozszerzenia_wybrane <- stri_c(kolumny_do_rozszerzenia_wybrane, "_dodatkowa_kolumna_po_deduplikacji_")
                        dodatkowe_kolumny_do_rozszerzenia_wybrane <- as.data.table(CJ(dodatkowe_kolumny_do_rozszerzenia_wybrane, 1:(id_najdluzsze - 1)))
                        dodatkowe_kolumny_do_rozszerzenia_wybrane <- dodatkowe_kolumny_do_rozszerzenia_wybrane[, V3 := stri_c(dodatkowe_kolumny_do_rozszerzenia_wybrane, V2)]
                        dodatkowe_kolumny_do_rozszerzenia_wybrane <- dodatkowe_kolumny_do_rozszerzenia_wybrane$V3
                        wszystkie_kolumny_do_rozszerzenia <- c(kolumny_do_deduplikacji_wybrane, dodatkowe_kolumny_do_rozszerzenia_wybrane[stri_detect_regex(dodatkowe_kolumny_do_rozszerzenia_wybrane, stri_c(stri_c("^", kolumny_do_deduplikacji_wybrane), collapse = "|"))], sort(c(kolumny_do_rozszerzenia_wybrane[!kolumny_do_rozszerzenia_wybrane %in% kolumny_do_deduplikacji_wybrane], dodatkowe_kolumny_do_rozszerzenia_wybrane[!dodatkowe_kolumny_do_rozszerzenia_wybrane %in% c(kolumny_do_deduplikacji_wybrane, dodatkowe_kolumny_do_rozszerzenia_wybrane[stri_detect_regex(dodatkowe_kolumny_do_rozszerzenia_wybrane, stri_c(stri_c("^", kolumny_do_deduplikacji_wybrane), collapse = "|"))])])))
                        plik[, (dodatkowe_kolumny_do_rozszerzenia_wybrane) := NA]
                        plik <- select(plik, all_of(c(kolumny_do_deduplikacji_wybrane, dodatkowe_kolumny_do_rozszerzenia_wybrane[stri_detect_regex(dodatkowe_kolumny_do_rozszerzenia_wybrane, stri_c(stri_c("^", kolumny_do_deduplikacji_wybrane), collapse = "|"))])), sort(c(all_of(kolumny_do_rozszerzenia_wybrane[!kolumny_do_rozszerzenia_wybrane %in% kolumny_do_deduplikacji_wybrane]), all_of(dodatkowe_kolumny_do_rozszerzenia_wybrane[!dodatkowe_kolumny_do_rozszerzenia_wybrane %in% c(kolumny_do_deduplikacji_wybrane, dodatkowe_kolumny_do_rozszerzenia_wybrane[stri_detect_regex(dodatkowe_kolumny_do_rozszerzenia_wybrane, stri_c(stri_c("^", kolumny_do_deduplikacji_wybrane), collapse = "|"))])]))), everything())
                    }
                    incProgress(0.1)
                    plik_zdublowane_id <- map_dfr(plik_id_kolumny_do_deduplikacji_duble$zdublowane_id, ujednolic_informacje_dla_zdublowanych_id, plik = plik, kolumny_do_rozszerzenia_wybrane = kolumny_do_rozszerzenia_wybrane, kolumny_do_deduplikacji_wybrane = kolumny_do_deduplikacji_wybrane, wszystkie_kolumny_do_rozszerzenia = wszystkie_kolumny_do_rozszerzenia, id_najdluzsze = id_najdluzsze)
                    incProgress(0.2)
                    plik_zdublowane_id[, liczebnosc := rowSums(!is.na(.SD)), .SDcols = kolumny_do_deduplikacji_wybrane]
                    plik_zdublowane_id <- plik_zdublowane_id[order(-liczebnosc)]
                    plik_zdublowane_id[, liczebnosc := NULL]
                    plik_zdublowane_id <- unique(plik_zdublowane_id, by = names(plik_zdublowane_id)[1])
                    plik <- plik[!id_do_deduplikacji_dt %in% same_id]
                    plik <- rbindlist(list(plik_zdublowane_id, plik))
                    plik[, id_do_deduplikacji_dt := NULL]
                    if (!is.null(kolumny_do_rozszerzenia_wybrane)) {
                       ktore_dodatkowe_kolumny_z_samymi_brakami <- unlist(map(plik[, .SD, .SDcols = dodatkowe_kolumny_do_rozszerzenia_wybrane], ~ all(is.na(.))), use.names = FALSE)
                       if (length(ktore_dodatkowe_kolumny_z_samymi_brakami) > 0) {
                           plik <- plik[, .SD, .SDcols = c(dodatkowe_kolumny_do_rozszerzenia_wybrane[!ktore_dodatkowe_kolumny_z_samymi_brakami], names(plik)[!names(plik) %in% dodatkowe_kolumny_do_rozszerzenia_wybrane])]
                       }
                       incProgress(0.1)
                       plik <- select(plik, all_of(c(kolumny_do_deduplikacji_wybrane, dodatkowe_kolumny_do_rozszerzenia_wybrane[stri_detect_regex(dodatkowe_kolumny_do_rozszerzenia_wybrane, stri_c(stri_c("^", kolumny_do_deduplikacji_wybrane), collapse = "|")) & dodatkowe_kolumny_do_rozszerzenia_wybrane %in% names(plik)])), sort(all_of(c(kolumny_do_rozszerzenia_wybrane[!kolumny_do_rozszerzenia_wybrane %in% kolumny_do_deduplikacji_wybrane], dodatkowe_kolumny_do_rozszerzenia_wybrane[(!dodatkowe_kolumny_do_rozszerzenia_wybrane %in% c(kolumny_do_deduplikacji_wybrane, dodatkowe_kolumny_do_rozszerzenia_wybrane[stri_detect_regex(dodatkowe_kolumny_do_rozszerzenia_wybrane, stri_c(stri_c("^", kolumny_do_deduplikacji_wybrane), collapse = "|"))])) & dodatkowe_kolumny_do_rozszerzenia_wybrane %in% names(plik)]))), everything())
                    }
                    plik <- as.data.table(map_if(plik, sprawdzenie_numeric, as.numeric))
                    plik
                } else {
                    shinyalert(title = "", text = "W pliku nie ma zdublowanych rekordów", type = "info", closeOnClickOutside = TRUE, closeOnEsc = TRUE, confirmButtonCol = "#955251")
                }
            } else {
                shinyalert(title = "Niepoprawne dane!", text = "Występuje jeden lub więcej z następujących problemów: (1) nie wybrano pliku, (2) nie wybrano kolumn do deduplikacji, (3) w pierwszej kolumnie do deduplikacji występuje brak danych (pusta komórka), (4) nazwy kolumn w pliku nie są poprawne - powinny być unikalne i składać się tylko z liter, cyfr, podkreślenia, (5) jeśli wybrano jakieś kolumny do rozszerzenia, to muszą być wśród nich wszystkie kolumny wybrane do deduplikacji.", type = "warning", closeOnClickOutside = TRUE, closeOnEsc = TRUE, confirmButtonCol = "#955251")
            }
        })
    })
    
    output$deduplikacja_gotowa <- renderUI({
        plik_gotowy <- deduplikuj()
        if (!is.null(plik_gotowy)) {
            p("Gotowe", style = "color:#438F3B")
        }
    })
    
    output$pobierz_plik_po_deduplikacji <- downloadHandler(
        filename = function() {
            "Plik_po_deduplikacji.xlsx"
        },
        content = function(file) {
                plik_po_deduplikacji <- deduplikuj()
                write_xlsx(plik_po_deduplikacji, file, format_headers = FALSE)
        },
        contentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    
    output$instrukcja <- renderUI({
        HTML("Instrukcja: <br>
             1. Należy wybrać plik o rozszerzeniu .xlsx, w którym dane do deduplikacji będą znajdować się w pierwszym arkuszu.<br>
             2. Następnie należy wybrać kolumny, na podstawie których odbędzie się deduplikacja, np. kolumny z numerami telefonów.<br>
             3. Ostatni krok to wybór kolumn, które zostaną poszerzone o niepowtarzające się informacje z rekordów, które zostały uznane
             za zdublowane. <br>
             4. Plik po deduplikacji należy pobrać. <br>
             5. Jeśli w pliku były kolumny z datami, to teraz będą miały reprezentację numeryczną - należy je ponownie przeformatować na datę. <br> <br>
             Jako przykład rozważmy plik składający się z pięciu kolumn: trzy pierwsze z numerów telefonów, dalej: kolumny z nazwą i kolumny mówiącej o źródle pochodzenia rekordu. 
             Przypuśćmy, że do deduplikacji wybrano wszystkie kolumny z telefonami, a jako kolumny, które zostaną rozszerzone, wybrano kolumny z telefonami oraz 
             kolumnę z nazwą. Następnie załóżmy, że rekord pierwszy i drugi okazał się zdublowany. W wyniku deduplikacji rekord pierwszy i drugi będą miały
             nastepującą postać w wynikowej bazie: zostaną zamienione na jeden rekord taki, że wszystkie niepowtarzające się numery telefonów ze zdublowanych
             rekordów zostaną zachowane, a także zostaną zachowane obie nazwy tych rekordów, o ile nie były powtórzone - wszystkie numery telefonów oraz  wszystkie nazwy zostaną podzielone na osobne kolumny. 
             Natomiast w przypadku kolumny mówiącej o źródle pochodzenia rekordu, zachowana zostanie tylko jedna wartość, wybrana losowo.")
    })
    }

shinyApp(ui = ui, server = server)