#' @title Apply a function over a time series.
#' @name sits_apply
#' @author Rolf Simoes, \email{rolf.simoes@@inpe.br}
#' @description Apply a 1D generic function to a time series
#'  and specific methods for common tasks,
#'  such as missing values removal and smoothing.
#' `sits_apply()` returns a sits tibble with the same samples
#'  and new bands computed by `fun`, `fun_index` functions.
#'  These functions must be defined inline; they are called by `sits_apply`
#'  for each band, whose vector values is passed as the function argument.
#'  The `fun` function may either return a vector or a list of vectors.
#'  In the first case, the vector will be the new values
#'  of the corresponding band.
#'  In the second case, the returned list must have names,
#'  and each element vector will generate a new band which name composed
#'  by concatenating original band name and the corresponding list element name.
#'
#'  If a suffix is provided in `bands_suffix`, all resulting band
#'  names will end with provided suffix separated by a ".".
#'
#' @param data          Valid sits tibble
#' @param fun           Function with one parameter as input
#'                      and a vector or list of vectors as output.
#' @param fun_index     Function with one parameter as input
#'                      and a Date vector as output.
#' @param bands_suffix  String informing the suffix of the resulting bands.
#' @param multicores    Number of cores to be used
#' @return A sits tibble with same samples and the new bands.
#' @examples
#' # Get a time series
#' point_ndvi <- sits_select(point_mt_6bands, bands = "NDVI")
#' # apply a normalization function
#' point2 <- sits_apply(point_ndvi,
#'     fun = function(x) {
#'         (x - min(x)) / (max(x) - min(x))
#'     }
#' )
#'
#'
#' @export
sits_apply <- function(data,
                       fun,
                       fun_index = function(index) {
                           return(index)
                       },
                       bands_suffix = "",
                       multicores = 1) {

    # verify if data is valid
    .sits_test_tibble(data)

    # computes fun and fun_index for all time series
    data$time_series <- data$time_series %>%
        purrr::map(function(ts) {
            ts_computed_lst <- dplyr::select(ts, -Index) %>%
                purrr::map(fun)

            # append bands names' suffixes
            if (nchar(bands_suffix) != 0) {
                  names(ts_computed_lst) <- paste0(
                      names(ts_computed_lst), ".",
                      bands_suffix
                  )
              }

            # unlist if there are more than one result from `fun`
            if (is.recursive(ts_computed_lst[[1]])) {
                  ts_computed_lst <- unlist(ts_computed_lst, recursive = FALSE)
              }

            # convert to tibble
            ts_computed <- tibble::as_tibble(ts_computed_lst)

            # compute Index column
            ts_computed <- dplyr::mutate(ts_computed,
                Index = fun_index(ts$Index)
            )

            # reorganizes time series tibble
            return(dplyr::select(ts_computed, Index, dplyr::everything()))
        })
    return(data)
}

#' @title Add new sits bands.
#' @name sits_mutate_bands
#' @keywords internal
#' @author Rolf Simoes, \email{rolf.simoes@@inpe.br}
#' @description Adds new bands and preserves existing in the time series
#'              of a sits tibble using \code{dplyr::mutate} function.
#' @param data       Valid sits tibble.
#' @param ...        Expressions written as `name = value`.
#'                   See \code{dplyr::mutate()} help for more details.
#' @return           A sits tibble with same samples and the selected bands.
#' @examples
#' \donttest{
#' # Retrieve data for time series with label samples in Mato Grosso in Brazil
#' data(samples_mt_6bands)
#' # Generate a new image with the SAVI (Soil-adjusted vegetation index)
#' savi.tb <- sits_mutate_bands(samples_mt_6bands,
#'            SAVI = (1.5 * (NIR - RED) / (NIR + RED + 0.5)))
#' }
#' @export
sits_mutate_bands <- function(data, ...) {

    # verify if data has values
    .sits_test_tibble(data)
    # bands in SITS are uppercase
    sits_bands(data) <- toupper(sits_bands(data))

    # compute mutate for each time_series tibble
    proc_fun <- function(...) {
        data$time_series <- data$time_series %>%
            purrr::map(function(ts) {
                ts_computed <- ts %>%
                    dplyr::mutate(...)
                return(ts_computed)
            })
    }

    # compute mutate for each time_series tibble
    tryCatch({
        data$time_series <- proc_fun(...)
    },
    error = function(e) {
        msg <- paste0("Error - Are your band names all uppercase?")
        message(msg)
    }
    )

    return(data)
}



#' @title Sample a percentage of a time series
#' @name sits_sample
#' @author Rolf Simoes, \email{rolf.simoes@@inpe.br}
#'
#' @description Takes a sits tibble with different labels and
#'              returns a new tibble. For a given field as a group criterion,
#'              this new tibble contains a given number or percentage
#'              of the total number of samples per group.
#'              Parameter n: number of random samples with replacement.
#'              Parameter frac: a fraction of random samples without
#'              replacement. If frac > 1, no sampling is done.
#'
#' @param  data       Input sits tibble.
#' @param  n          Number of samples to pick from each group of data.
#' @param  frac       Percentage of samples to pick from each group of data.
#' @return            A sits tibble with a fixed quantity of samples.
#' @examples
#' # Retrieve a set of time series with 2 classes
#' data(cerrado_2classes)
#' # Print the labels of the resulting tibble
#' sits_labels(cerrado_2classes)
#' # Samples the data set
#' data <- sits_sample(cerrado_2classes, n = 10)
#' # Print the labels of the resulting tibble
#' sits_labels(data)
#' @export
sits_sample <- function(data, n = NULL, frac = NULL) {

    # verify if data is valid
    .sits_test_tibble(data)

    # verify if either n or frac is informed
    assertthat::assert_that(
        !(purrr::is_null(n) & purrr::is_null(frac)),
        msg = "sits_sample: neither n or frac parameters informed"
    )

    # prepare sampling function
    sampling_fun <- if (!purrr::is_null(n)) {
          function(tb) {
              if (nrow(tb) >= n) {
                  return(dplyr::sample_n(tb,
                      size = n,
                      replace = FALSE
                  ))
              } else {
                  return(tb)
              }
          }
      } else if (frac <= 1) {
          function(tb) tb %>% dplyr::sample_frac(size = frac, replace = FALSE)
      } else {
          function(tb) tb %>% dplyr::sample_frac(size = frac, replace = TRUE)
      }

    # compute sampling
    result <- .sits_tibble()
    labels <- sits_labels(data)
    labels %>%
        purrr::map(function(l) {
            tb_l <- dplyr::filter(data, label == l)
            tb_s <- sampling_fun(tb_l)
            result <<- dplyr::bind_rows(result, tb_s)
        })

    return(result)
}

#' @title Retrieve time series for a row of a sits tibble
#' @name sits_time_series
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description Returns the time series associated to a row of the a sits tibble
#'
#' @param data     A sits tibble with one or more time series.
#' @return A tibble in sits format with the time series.
#' @examples
#' # Retrieve a set of time series with 2 classes
#' data(cerrado_2classes)
#' # Retrieve the first time series
#' sits_time_series(cerrado_2classes)
#' @export
sits_time_series <- function(data) {
    return(data$time_series[[1]])
}
