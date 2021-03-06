% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/sits_filters.R
\name{sits_envelope}
\alias{sits_envelope}
\title{Envelope filter}
\usage{
sits_envelope(data = NULL, operations = "UULL", bands_suffix = "env")
}
\arguments{
\item{data}{A tibble with time series data and metadata.}

\item{operations}{A character sequence for the sequence operations.
("U" for upper filter, "L" for lower filter).}

\item{bands_suffix}{Suffix of the resulting data.}
}
\value{
A tibble with filtered time series values.
}
\description{
This function computes the envelope of a time series using the
streaming algorithm proposed by Lemire (2009).
This functions calls `dtwclust::compute_envelope` function.
}
\examples{
# Select the NDVI band of a point in Mato Grosso
point_ndvi <- sits_select(point_mt_6bands, bands = "NDVI")
# Apply the envelope filter
point_env <- sits_envelope(point_ndvi)
# Merge the filtered with the raw data
point2 <- sits_merge(point_ndvi, point_env)
# Plot the result
plot(point2)
}
\author{
Rolf Simoes, \email{rolf.simoes@inpe.br}
}
