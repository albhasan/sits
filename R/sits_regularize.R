#' @title Creates a regularized data cube from an irregular one
#' @name sits_regularize
#' @description Creates cubes with regular time intervals
#'  using the gdalcubes package. Cubes are composed using "min", "max", "mean",
#' "median" or "first" functions. Users need to provide an
#'  time interval which is used by the composition function.
#'
#' @references APPEL, Marius; PEBESMA, Edzer. On-demand processing of data cubes
#'  from satellite image collections with the gdalcubes library. Data, v. 4,
#'  n. 3, p. 92, 2019. DOI: 10.3390/data4030092.
#'
#' @examples{
#' \dontrun{
#'
#' # --- Access to the AWS STAC
#' # Provide your AWS credentials as environment variables
#' Sys.setenv(
#'     "AWS_ACCESS_KEY_ID" = <your_aws_access_key>,
#'     "AWS_SECRET_ACCESS_KEY" = <your_aws_secret_access_key>
#' )
#'
#' # define an AWS data cube
#'   s2_cube <- sits_cube(source = "AWS",
#'                       name = "T20LKP_2018_2019",
#'                       collection = "sentinel-s2-l2a",
#'                       bands = c("B08", "SCL"),
#'                       tiles = c("20LKP"),
#'                       start_date = as.Date("2018-07-18"),
#'                       end_date = as.Date("2018-08-18"),
#'                       s2_resolution = 60
#' )
#'
#' # create a directory to store the resulting images
#' dir.create(paste0(tempdir(),"/images/"))
#'
#'  # Build a data cube of equal intervals using the "gdalcubes" package
#' gc_cube <- sits_regularize(cube   = s2_cube,
#'                      name          = "T20LKP_2018_2019_1M",
#'                      dir_images   = paste0(tempdir(),"/images/"),
#'                      period        = "P1M",
#'                      agg_method    = "median",
#'                      resampling    = "bilinear",
#'                      cloud_mask    = TRUE)
#' }
#' }
#'
#' @param cube              A cube whose spacing of observation times is
#'                          not constant and will be regularized by the
#'                          "gdalcubes" packges
#' @param name              Name of the output data cube
#' @param dir_images        Directory where the regularized images will be
#'                          written by \code{gdalcubes}.
#' @param period            ISO8601 time period for regular data cubes
#'                          produced by \code{gdalcubes},
#'                          with number and unit, e.g., "P16D" for 16 days.
#'                          Use "D", "M" and "Y" for days, month and year..
#'
#' @param  roi              a region of interest (see above)
#' @param agg_method        Method that will be applied by \code{gdalcubes}
#'                          for aggregation. Options: "min", "max", "mean",
#'                          "median" and "first".
#' @param resampling        Method to be used by \code{gdalcubes}
#'                          for resampling in mosaic operation.
#'                          Options: "near", "bilinear", "bicubic"
#'                          or others supported by gdalwarp
#'                          (see https://gdal.org/programs/gdalwarp.html).
#' @param cloud_mask        Use cloud band for aggregation by \code{gdalcubes}?
#'
#'
#' @note
#'    The "roi" parameter defines a region of interest. It can be
#'    an sf_object, a shapefile, or a bounding box vector with
#'    named XY values ("xmin", "xmax", "ymin", "ymax") or
#'    named lat/long values ("lat_min", "lat_max", "long_min", "long_max")
#'
#' @export
#'
sits_regularize <- function(cube,
                            name,
                            dir_images,
                            period  = NULL,
                            roi     = NULL,
                            agg_method = NULL,
                            resampling = "bilinear",
                            cloud_mask = TRUE) {

    # require gdalcubes package
    if (!requireNamespace("gdalcubes", quietly = TRUE)) {
        stop(paste("Please install package gdalcubes from CRAN:",
                   "install.packages('gdalcubes')"), call. = FALSE
        )
    }

    # test if provided object its a sits cube
    assertthat::assert_that(
        inherits(cube, "raster_cube"),
        msg = paste("The provided cube is invalid,",
                    "please provide a 'raster_cube' object.",
                    "See '?sits_cube' for more information.")
    )

    # filter only intersecting tiles
    intersects <- slider::slide_lgl(cube,
                                    .sits_raster_sub_image_intersects,
                                    roi)

    # retrieve only intersecting tiles
    cube <- cube[intersects, ]

    # get the interval of intersection in all tiles
    interval_intersection <- function(cube) {

        max_min_date <- do.call(
            what = max,
            args = purrr::map(cube$file_info, function(file_info){
                return(min(file_info$date))
            })
        )

        min_max_date <- do.call(
            what = min,
            args = purrr::map(cube$file_info, function(file_info){
                return(max(file_info$date))
            }))

        # check if all tiles intersects
        assertthat::assert_that(
            max_min_date < min_max_date,
            msg = paste("sits_regularize: The cube tiles' timelines do not",
                        "intersect.")
        )

        list(max_min_date = max_min_date, min_max_date = min_max_date)
    }

    # timeline of intersection
    toi <- interval_intersection(cube)

    # fix cube name
    cube <- .sits_cube_fix_name(cube)

    # create an image collection
    db_file <- paste0(dir_images, "/gdalcubes.db")
    img_col <- .sits_gc_database(cube = cube, path_db = db_file)

    gc_cube <- slider::slide_dfr(cube, function(tile){

        # create a list of cube view object
        cv <- .sits_gc_cube(tile = tile,
                            period = period,
                            roi = roi,
                            toi = toi,
                            agg_method = agg_method,
                            resampling = resampling)

        # create of the aggregate cubes
        gc_tile <- .sits_gc_compose(tile = tile,
                                    name = name,
                                    cv = cv,
                                    img_col = img_col,
                                    db_file = db_file,
                                    dir_images = dir_images,
                                    cloud_mask = cloud_mask)
        return(gc_tile)

    })

    class(gc_cube) <- c("raster_cube", class(gc_cube))

    return(gc_cube)
}
