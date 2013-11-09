#' Assign new (or existing) coldbir database
#' 
#' Method to assign either a new or existing coldbir database to an R object.
#' The current working directory is set as the default path.
#' 
#' @param path Database path (the location of the coldbir database)
#' @param dims Set default dimensions
#' @param type Return type of variable. Possible values: 'c' = character, 'f' = factor and 'n' = numeric (default).
#' Character conversion might be a bit slow; hence numeric or factor is recommended.
#' @param na Value representing missing values (default: NA_real_)
#' @param log_level Log level (default: 4). Available levels: 1-9.
#' @param log_file Log file. As default log messages will be written to console.
#' 
#' @examples db <- cdb()
#' @export
#'
cdb <- setRefClass(
  "cdb",
  fields = list(
    path = "character",
    type = "character",
    na = "numeric",
    log_level = "numeric",
    log_file = "character",
    dims = "ANY",
    compress = "numeric"
  ),
  methods = list(
    initialize = function(
        path = getwd(),
        type = "f",
        na = NA_real_, 
        log_level = 4,
        log_file = "",
        dims = NULL,
        compress = 5
      ) {
      
      # Validate
      types <- c("c", "f", "n")
      if (!(type %in% types)) {
        stop("wrong type argument; only '", paste(types, collapse = "'/'"), "' are allowed")
      }
      
      # Set parameters
      .self$path <- path
      .self$type <- type
      .self$na <- na
      .self$log_level <- log_level
      .self$log_file <- log_file
      .self$dims <- dims
      .self$compress <- compress
      
      # Set futile.logger options
      flog.threshold(log_level)
      
      if (log_file != "") {
        flog.appender(appender.file(log_file))
      } else {
        flog.appender(appender.console())
      }
    },
    get_variable = function(name) {
  
      # Get file path
      cdb <- file_path(name, .self$path, .self$dims, ext = c("cdb.gz", "cdb"), create_dir = FALSE)
      
      # Connect to compressed/uncompressed file
      if (file.exists(cdb[1])) {
          bin_file <- gzfile(cdb[1], "rb")
          
      } else if (file.exists(cdb[2])) {
          bin_file <- file(cdb[2], "rb")
          
      } else {
          flog.error("%s - file does not exist", name)
          stop()
      }
      
      header_len <- readBin(bin_file, integer(), n = 1, size = 8)
      header_str <- rawToChar(readBin(bin_file, raw(), n = header_len))
      header <- fromJSON(header_str, simplifyWithNames = FALSE)
      
      vector_len <- readBin(bin_file, integer(), n = 1, size = 8)
      
      if (header$bytes <= 4) {
          x <- readBin(bin_file, integer(), n = vector_len, size = header$bytes)
      } else {
          x <- readBin(bin_file, double(), n = vector_len)
      }
      
      close(bin_file)
      
      # Check if using an old version of colbir
      if (header$db_ver != as.integer(.database_version)) {
          flog.error("%s - version of coldbir package and file format does not match", name)
          stop()
      }
  
      # Prepare data depending on vector type
      
      ## integer or factor
      if (header$type %in% c("integer", "factor")) {
          if (!is.na(.self$na)) 
              x[is.na(x)] <- as.integer(.self$na)
      
      ## double
      } else if (header$type == "double") {
          if (!is.null(header$exponent)) 
              x <- x / 10^header$exponent
          if (!is.na(.self$na))
              x[is.na(x)] <- as.double(.self$na)
        
      ## logical
      } else if (header$type == "logical") {
          x <- (x > 0L)
          if (!is.na(.self$na)) 
              x[is.na(x)] <- as.logical(.self$na)
          
      ## Date
      } else if (header$type == "Date") {
          origin <- "1970-01-01"
          x <- as.Date(x, origin = origin)
          
      ## POSIXt
      } else if (header$type %in% c("POSIXct", "POSIXlt")) {
          origin <- as.POSIXct("1970-01-01 00:00:00", tz = .tzone)
          x <- as.POSIXct(x, tz = .tzone, origin = origin)
      }
      
      # Add attributes to vector
      if (!is.null(header$attributes)) {
          attributes(x) <- c(attributes(x), header$attributes)
      }
      
      return(x)
    },
    
    put_variable = function(x, name = NULL, attrib = NULL, lookup = TRUE) {
      
      # If x is a data frame it will recursively run put_variable over all columns
      if (is.data.frame(x)) {
        sapply(names(x), function(i) {
          put_variable(
            x = x[[i]],
            name = i,
            attrib = attrib,
            lookup = lookup
          )
        })
        return(TRUE)
        
      } else {
  
        # Read object name if name argument is missing
        if (is.null(name)) name <- deparse(substitute(x))
        
        # if null => exit
        if (is.null(x)) {
          flog.warn("%s - variable is NULL; nothing to write", name)
          return(FALSE)
        }
        
        # Info
        if (all(is.na(x))) {
          flog.info("%s - all values are missing", name)
        }
          
        # Create empty header
        header <- list()
          
        # Check/set vector type and number of bytes
          
        if (is.numeric(x)) {
              
          if (is.integer(x)) {
            header$type <- "integer"
            header$bytes <- 4L  # H_itemSize, note: NA for integers is already -2147483648 in R
                    
          } else if (is.double(x)) {
            header$type <- "double"
            header$exponent <- find_exp(x)
            
            if (header$exponent <= 9L) {
              x <- round(x * 10^header$exponent, 0)
              header$bytes <- check_repr(x)
              if (header$bytes <= 4L) {
                header$bytes <- 4L
              }
            } else {
              header$bytes <- 8L
              header$exponent <- 0L
            }
          }
  
        } else if (is.logical(x)) {
          header$type <- "logical"
          header$bytes <- 1L
          if (any(is.na(x))) {
            flog.warn("%s - logical vector; NA is converted to FALSE", name)
          }
              
        } else if ("POSIXt" %in% class(x)) {  # OBS: must be checked before is.double
          header$type <- "POSIXct"
          header$bytes <- 8L  # save as double
  
          x <- lubridate::force_tz(x, .tzone)  # convert to GMT
          x <- as.double(x)  # convert to double
  
        } else if ("Date" %in% class(x)) {
          header$type <- "Date"
          header$bytes <- 8L
  
        } else if (is.factor(x) || is.character(x)) {
          if (is.character(x)) {
            x <- as.factor(x)
            flog.warn("%s - character converted to factor", name)
          }
              
          if (lookup) {
            values <- levels(x)
            lt <- data.frame(key = 1:length(values), value = values)
            put_lookup(lt, name = name, path = path)
          }
          
          header$type <- "factor"
          header$bytes <- 4L
              
        } else {
          flog.error("%s - data type is not supported", name)
          stop()
        }
          
        ext <- if (.self$compress > 0) "cdb.gz" else "cdb"
        
        # Construct file path
        cdb <- file_path(
          name = name,
          path = .self$path,
          dims = .self$dims,
          ext = ext,
          create_dir = T
        )
        
        # File header
        header$db_ver <- as.integer(.database_version)
          
        # Add attributes
        header$attributes <- attrib
          
        header_raw <- charToRaw(toJSON(header, digits = 50))
        header_len <- length(header_raw)
        
        # Removes attributes from vector
        if (header$bytes == 8) {
          x <- as.double(x)
        } else {
          x <- as.integer(x)
        }
        
        # Create temporary file
        tmp <- create_temp_file(cdb)
  
        # Try to write file to disk
        tryCatch({
          
          # Create file and add file extension
          if (.self$compress > 0) {
            bin_file <- gzfile(tmp, open = "wb", compression = .self$compress)
          } else {
            bin_file <- file(tmp, "wb")
          }
            
          # Write binary file
          writeBin(header_len, bin_file, size = 8)
          writeBin(header_raw, bin_file)
          writeBin(length(x), bin_file, size = 8)
          writeBin(x, bin_file, size = header$bytes)  # write each vector element to bin_file
          close(bin_file)
  
          # Rename temporary variable to real name (overwrite)
          file.copy(tmp, cdb, overwrite = TRUE)
              
          },
          finally = file.remove(tmp),
          error = function(e) {
            flog.fatal("%s - writing failed; rollback! (%s)", name, e)
          }
        )
            
        # Return TRUE and message if variable is successfully written
        flog.info(cdb)
        return(TRUE)
      }
    }
  )
)

#' "["-method (overloading)
#' 
setMethod(
  f = "[",
  signature = "cdb",
  definition = function(x, i, j){
    
    if (missing(j)) j <- x$dims
    
    if (missing(i) || is.vector(i) && length(i) > 1){
      if (missing(i)){
        vars <- get_vars(a, dims = T)
        fun <- function(x) isTRUE(all.equal(x, as.character(j)))
        i <- vars[sapply(vars$dims, fun)]$variable
      }
      
      # Create data.table with first variable
      v <- data.table(first = x[i[1], j])
      setnames(v, "first", i[1])
      
      # Add all other variables
      if (length(i) > 1) {
        for(var in i[2:length(i)]){
          v[ , var := x[var, j], with = F]
        }
      }
      
    } else {
      v <- x$get_variable(i) #get_variable(name = i, path = x$path, dims = j, na = x$na)
      
      # Convert to character or factor (if requested)
      if (x$type %in% c("c", "f")) {
        factors <- if (x$type == "f") TRUE else FALSE
        v <- to_char(x = v, name = i, path = x$path, factors = factors)
      }
    }
    
    return(v)
  }
)

#' "[<-"-method (overloading)
#' 
setMethod(
  f = "[<-",
  signature = "cdb",
  definition = function(x, i, j, value){
    if (missing(j)) j <- x$dims
    
    if (all(class(value) == "doc")) {
      
      # Create readme.json
      put_variable_doc(x = to_yaml(value), name = i, path = x$path, file_name = .doc_file)
      
    } else {
      x$put_variable(x = value, name = i)
    }
    
    return(x)
  }
)


