#' Assign new (or existing) coldbir database
#' 
#' Method to assign either a new or existing coldbir database to an R object.
#' The current working directory is set as the default path.
#' 
#' @param path database path (the location of the coldbir database)
#' @param compress file compression level
#' @param encoding set documentation encoding (default: UTF-8)
#' @param read_only read only (default: T)
#' @param db_version instance-attribute for sycronisation of current list of variables
#' @param n_row the common length of vecrors in the database
#' 
#' @examples db <- cdb()
#' @export
cdb <- setRefClass(
  "cdb",
  fields = list(
    path         = "character",
    compress     = "integer",
    encoding     = "character",
    read_only    = "logical",
    db_version   = "numeric",
    n_row        = "integer",
    curr_var_tab = "ANY"
  ),
  methods = list(
    initialize = function(
      path      = getwd(),
      compress  = 5L,
      encoding  = "UTF-8",
      read_only = F
    ) {
      
      # Set parameters
      .self$path      <- path
      .self$compress  <- compress
      .self$encoding  <- encoding
      .self$read_only <- read_only
      .self$curr_var_tab <- get_vars(dims = T) 
      
      f <- file.path(path, .config_filename)
      
      if (file.exists(f)) {
        
        get_config()
        
      } else { # config.dat doesn't exist 
        
        if(nrow(.self$curr_var_tab) > 0L) { #data exist bunt not the config file => create the file
          
          .self$db_version <- new_time_stamp()
          .self$n_row      <- guess_db_nrow()
          put_config()
          
        } else { # no data = > postpone the creation of the config file until something is done in the directory
          
          .self$db_version <- NA_real_
          .self$n_row      <- NA_integer_
          
        }
      }
    },
    
    #' Get database variable length
    #' - Currently it compares with the first variable in the database
    guess_db_nrow = function() {
      
      if (nrow(.self$curr_var_tab) == 0L) return(NA_integer_)
      
      # Get variable dimension
      dim <- unlist(.self$curr_var_tab[1,]$dim)
      if (length(dim) == 0L) dim <- NULL
      
      # Get variable length
      # - Could have a special function looking in the header instead for length
      len <- length(get_variable(.self$curr_var_tab[1,]$variable, dim))
      
      return(len)
    },
    
    #' Save configuration settings to disk
    #' 
    #' Note: The config file can be updated even if the database is read only,
    #' as it would otherwise be more difficult to actually change the same option.
    put_config = function() {
      if (.self$read_only) wrn(1)
      
      if (is.na(file.info(.self$path)$isdir)) {
        dir.create(.self$path, recursive = T)
      }
      
      f <- file.path(.self$path, .config_filename)
      
      dta <- list(
        read_only = .self$read_only,
        db_version = .self$db_version,
        n_row = .self$n_row
      )
      
      saveRDS(dta, file = f)
    },
    
    #' Get configuration settings from disk
    get_config = function(){
      
      f <- file.path(.self$path, .config_filename)
      
      if (file.exists(f)) {
        
        dta <- readRDS(file = f)
        
        # Set field values
        .self$read_only <- dta$read_only
        .self$db_version <- dta$db_version
        .self$n_row <- dta$n_row
        
        return(T)
        
      } else return (NULL)
    },
    
    #' Put variable documentation to disk
    #'
    #' Write documentation of a variable to disk.
    #'
    #' @param x documentation string
    #' @param name Variable name
    #' 
    put_doc = function(x, name) {
      
      f <- file_path(name, .self$path, create_dir = T, file_name = F, data_folder = F)
      f <- file.path(f, .doc_file)
      
      # Create temporary file
      tmp <- create_temp_file(f)
      
      tryCatch(
        {
          con <- file(tmp, encoding = .self$encoding)
          writeLines(x, con)
          close(con)
          
          file.copy(tmp, f, overwrite = T)
        },
        finally = file.remove(tmp),
        error = function(e) {
          msg(2, name, e)
        }
      )
      
      return(T)
    },
    
    #' Get variable documentation from disk
    #'
    #' Read documentation of a variable from disk.
    #'
    #' @param name Variable name
    #' 
    get_doc = function(name) {
      
      f <- file_path(name, .self$path, create_dir = F, file_name = F, data_folder = F)
      if (is.na(f)) stp(3, .self$path)
      
      f <- file.path(f, .doc_file)
      if (!file.exists(f)) stp(4, .self$path, name)
      
      con <- file(f, "r", encoding = .self$encoding)
      lns <- readLines(con, n = -1, warn = F)
      close(con)
      
      d <- paste(lns, collapse = "\n")
      d <- RJSONIO::fromJSON(d)
      return(d)
    },
    
    # List all variables
    #'
    #' @param dims tells if column with dimensions is required
    #'
    get_vars = function(dims = F) {
      files <- search_files(path = .self$path)
      
      # Extract variable names
      vars = basename(dirname(dirname(files)))
      
      if (dims) {
        
        # Extract dims
        var_dims <- str_extract_all(files, "\\[(\\w*)\\]")
        
        # Remove square brackets
        var_dims <- sapply(var_dims, function(x) {
          x <- gsub("\\[", "", x)
          x <- gsub("\\]", "", x)
          
          #if (length(x) == 0) x <- NULL
          return(x)
        })
        
        x <- data.table(
          variable = vars,
          dims = var_dims
        )
        
      } else {
        x <- vars
      }
      
      if (dims == F) x <- unique(x)
      return(x)
    },
    
    # Get variable dimensions
    #'    
    #' @param name variable name
    #'
    get_dims = function(name) {
      x <- get_vars(dims = T)
      x <- subset(x, variable == name)
      return(x$dims)
    },
    
    # Delete variable data
    #'    
    #' @param name variable name
    #' @param dims the specified observation in the space of dimensions  
    #'     
    delete_variable = function(name, dims = NULL) {

      # Do data exists? (find faster solution)
      LeDims <- length(dims)
      tmpTable  <- data.table::copy(.self$curr_var_tab)
      tmpTable[,Nr := 1:nrow(.self$curr_var_tab)]         # temp row counter
      tmpTable[,Len:= unlist(lapply(dims, FUN=length))]   # temp lengths of dims
      selNr <- tmpTable[variable==name & Len==LeDims,Nr]   # reduce the problem
      rm(tmpTable)
      
      found <- FALSE
      k     <- length(selNr)
      while(!found && k>0L){
        ndx   <- selNr[k]
        found <- identical(as.character(.self$curr_var_tab[ndx]$dims[[1]]),as.character(dims))
        k <- k- 1L
      }     

      
      if(!found) {
        wrn(23, paste(name,"(",paste(dims,collapse=","),")",sep=""))
        return()
      }
      
      if(nrow(.self$curr_var_tab[variable==name])==1L) {  # remove the whole directory
        
         unlink(file.path(.self$path,name),recursive = TRUE)   
                                            # note: delete the documentation as well
        } else {
        
        cdb <- file_path(name, .self$path, dims, ext = c("cdb.gz", "cdb"), create_dir = F) 
        
        if(file.exists(cdb[1])){
          unlink(file.path(cdb[1])) # compressed
        } else {
          unlink(file.path(cdb[2])) # uncompressed
        }
      }
      
      .self$curr_var_tab <- .self$curr_var_tab[-ndx]
      .self$db_version      <- new_time_stamp()     
      .self$put_config()      
      
    },
    
    # Get variable data
    #'    
    #' @param name variable name
    #' @param dims the specified observation in the space of dimensions 
    #' @param na the value of missing values. NA by default. 
    #'     
    get_variable = function(name, dims = NULL, na = NA) {
  
      # Get file path
      cdb <- file_path(name, .self$path, dims, ext = c("cdb.gz", "cdb"), create_dir = F)
      
      # Connect to compressed/uncompressed file
      if (file.exists(cdb[1])) {
        bin_file <- gzfile(cdb[1], "rb")
          
      } else if (file.exists(cdb[2])) {
        bin_file <- file(cdb[2], "rb")
        
      } else err(6, name)
      
      header_len <- readBin(bin_file, integer(), n = 1, size = 8)
      header_str <- rawToChar(readBin(bin_file, raw(), n = header_len))
      header <- fromJSON(header_str, simplifyWithNames = F)
      
      vector_len <- readBin(bin_file, integer(), n = 1, size = 8)
      
      if (header$bytes <= 4) {
        x <- readBin(bin_file, integer(), n = vector_len, size = header$bytes)
      } else {
        x <- readBin(bin_file, double(), n = vector_len)
      }
      
      close(bin_file)
      
      # Check if using an old version of colbir
      if (header$db_ver != as.integer(.cdb_file_version)) err(7, name)
      
      # Prepare data depending on vector type
      
      ## integer or factor
      
      if (header$type == "integer") {
        
        if (!is.na(na)) x[is.na(x)] <- as.integer(na)
        
      } else if (header$type == "factor") {
        
        # Get lookup table, where values are to be used as levels
        lt <- .self$get_lookup(name = name)
        
        if (!is.null(lt)) {
          
          # Check whether variable has any NA
          has_na <- any(is.na(x)) && !any(is.na(lt[[2]]))
          
          # Add one level for NA
          levels_len <- max(lt[[1]]) + as.integer(has_na)
          
          # Replace NA in data with factor level
          if(has_na) x[which(is.na(x))] <- levels_len   # NA values by leveles
          
          # Create factor levels
          levels <- rep(NA_character_, levels_len)  # assert odd cases, usually 1:nrow(lt) + occasional NA
          levels[lt[[1]]] <- lt[[2]]
          if(!is.na(na)) levels[is.na(levels)] <- na
          
          # Convert to factor variable
          levels(x) <- levels
          class(x) <- "factor"

        } else {
          
          # This is outside the `if (!is.null(df))` due to the 
          # odd case of a factor variable with only NA-values
          levels(x) <- character(0)
          class(x) <- "factor"
          
        }
        
      ## double
      } else if (header$type == "double") {
        if (!is.null(header$exponent)) 
          x <- x / 10^header$exponent
        if (!is.na(na))
          x[is.na(x)] <- as.double(na)
        
      ## logical
      } else if (header$type == "logical") {
        # NA's are stored as -1, thus they are replaced with NA
        x[x == -1L] <- NA
        
        # Replace 0/1 with TRUE/FALSE
        x <- (x > 0L)
        
        if (!is.na(na))
          x[is.na(x)] <- as.logical(na)
          
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
    
    #' Put variable data
    #' 
    #' @param x vector of values. Should be of the same length as all the other variables in the database.
    #' @param name variable name
    #' @param dims the specified observation in the space of dimensions 
    #' @param attrib additional attributes to be saved  
    #' 
    put_variable = function(x, name = NULL, dims = NULL, attrib = NULL) {
      if (read_only) err(8)
      
      # If x is a data frame it will recursively run put_variable over all columns
      if (is.data.frame(x)) {
        
        sapply(names(x), function(i) {
          put_variable(
            x = x[[i]],
            name = i,
            dims = dims,
            attrib = attrib
          )
        })
        return(T)
        
      } else {
  
        # Read object name if name argument is missing
        if (is.null(name)) name <- deparse(substitute(x))
        
        # if null => exit
        if (is.null(x)) {
          wrn(9, name)
          return(F)
        }
        
        if(is.na(.self$n_row)){
          
          .self$n_row <- length(x)
          
        } else if(.self$n_row != length(x)) err(11, name)
        
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
          
          # Replace integer value with NA,
          # unless -2147483648 is in the range
          x[is.na(x)] <- -1L
          
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
            x <- as.factor(x)  # convert to factor
          }
          
          # Get previous lookup table
          lookup <- .self$get_lookup(name = name)
          
          # Get new levels (compared to lookup table)
          lvl <- levels(x)[!levels(x) %in% lookup[[2]]]
          
          # Add new levels (if there are any)
          if (length(lvl) > 0) {
            
            # Set previous lookup table length              
            len <- nrow(lookup)
            if (is.null(len)) len <- 0
            
            # Create new lookup table or add to existing (cols: key, value)
            lookup <- rbindlist(list(
              lookup, 
              data.table((len + 1):(len + length(lvl)), lvl)
            ))
            
            # Write lookup table
            .self$put_lookup(name = name, table = lookup)
          }
          
          # Convert variable (TODO: rewrite this part)
          if (!is.null(lookup)) {
            setnames(lookup, c("k", "v"))
            x_data <- data.table(k = as.integer(x), v = x, order = 1:length(x))
            x <- merge(x_data, lookup, by = "v", all.x = T, all.y = F)
            x <- x$k.y[order(x$order)]
          }
          
          header$type <- "factor"
          header$bytes <- 4L
              
        } else err(13, name)
        
        ext <- if (.self$compress > 0) "cdb.gz" else "cdb"
        
        # Construct file path
        cdb <- file_path(
          name = name,
          path = .self$path,
          dims = dims,
          ext = ext,
          create_dir = T
        )
        
        # check if we need a new entry in the internal table
        file.existed <- file.exists(cdb)
        
        # File header
        header$db_ver <- as.integer(.cdb_file_version)
          
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
          
          # future issue: no check for two vesions of the file. One compressed one not
          # Create file and add file extension
          if (.self$compress > 0) {
            bin_file <- gzfile(tmp, open = "wb", compression = .self$compress)
          } else {
            bin_file <- file(tmp, "wb")
          }
            
          # Write binary file
          writeBin(header_len, bin_file, size = 8)
          writeBin(header_raw, bin_file)
          writeBin(length(x),  bin_file, size = 8)
          writeBin(x, bin_file, size = header$bytes)  # write each vector element to bin_file
          close(bin_file)
  
          
          # Rename temporary variable to real name (overwrite)
          file.copy(tmp, cdb, overwrite = T)
          
          #bookkeeping of the internal info
          if(!file.existed)
            .self$curr_var_tab <- rbind(.self$curr_var_tab , list(variable = name, dims = list(dims)))

          .self$db_version <- new_time_stamp()
          .self$put_config()
          
          },
          finally = file.remove(tmp),
          error = function(e) {
            err(14, name, e)
          }
        )
        
        # Return TRUE if variable is successfully written
        return(T)
      }
    },
    
    #' Write lookup table to disk
    #'
    #' Write lookup table that represents variable data to disk.
    #'
    #' @param name Variable name
    #' @param table Two-column data table with keys and values
    put_lookup = function(name, table) {
      
      if (read_only) err(8)
      
      if (!is.data.frame(table) || ncol(table) != 2) err(16)
      
      # Escape characters
      table[[2]] <- escape_char(table[[2]])
      
      folder_path <- file_path(name, .self$path, create_dir = T, file_name = F, data_folder = F)
      f <- file.path(folder_path, .lookup_filename)
      
      write_lookup <- function() {
        # Write temporary doc file to disk
        write.table(table, file = tmp, quote = F, col.names = F, row.names = F, sep = "\t")
        
        # Rename temporary doc to real name (overwrite)
        file.copy(tmp, f, overwrite = T)
      }
      
      # Create temporary file
      tmp <- create_temp_file(f)
      
      # Try to write doc file to disk
      tryCatch(
        write_lookup(),
        finally = file.remove(tmp),
        error = function(e) {
          err(14, name, e)
        }
      )
      
      return(T)
    },
    
    #' Read dictionary from disk
    #'
    #' Read dictionary that represents variable data from disk.
    #'
    #' @param name Variable name
    get_lookup = function(name) {
      if (file.exists(file.path(.self$path, name))) {
        folder_path <- file_path(name, .self$path, create_dir = F, file_name = F, data_folder = F)
        file <- file.path(folder_path, .lookup_filename)
        
        if (file.exists(file)) {
          table <- read.table(file = file, header = F, quote = "", sep = "\t", stringsAsFactors = F)
          if (!is.data.frame(table) || ncol(table) != 2) {
            err(16)
          }
          return(as.data.table(table))
        } else { 
          return(NULL)
        }
      } else {
        return(NULL)
      }
    },
    #' Remove all content in database
    clean = function() {
      if (read_only) err(8)
      
      unlink(path, recursive = T)
      .self$read_only  <- read_only
      .self$db_version <- NA_real_
      .self$n_row      <- NA_integer_
      .self$curr_var_tab <- get_vars(dims = T) # Empty data.table with colnames
    }
  )
)


#' Extract content from variable
#' 
#' Function to extract data content from a Coldbir variable.
#' Overloads the `[`-method.
#' 
#' @param x cdb object
#' @param i variable name
#' @param j variable dims
#' @param na NA value (default: NA)
#' 
#' @name `[`
#' @docType methods
#' @rdname extract-methods
setMethod(
  f = "[",
  signature = "cdb",
  definition = function(x, i, j, na = NA){
    
    # ._     ==  NA
    # .all   ==  -.Machine$integer.max
    
    IFtZhmqaOHbU671928 <- x  # "IFtZhmqaOHbU671928" for avoiding name conflicts
    rm(x)                    # :) paste(paste(sample(c(letters,LETTERS),12),collapse=""),as.integer(1e6*runif(1)),sep="")
    
    if(nrow(IFtZhmqaOHbU671928$curr_var_tab) == 0){
      if(missing(i) && missing(j)) return(NULL)
      
      wrn(17,IFtZhmqaOHbU671928$path) # the database table is empty,
      return(NULL)   
    }
    
    # at first: fast track for a one column output
    if(!missing(i) && !is.null(i) && !is.na(i) && length(i) == 1L) { 
      
      if(missing(j) || is.null(j)) {                                                          # special case 1
        
        v <- data.table(IFtZhmqaOHbU671928$get_variable(name = i, dims = NULL, na = na))
        setnames(v,names(v),i)
        return(v)
        
      } else if(j != .all && !is.na(j) && length(j) > 0L && all(!is.na(j)) ) { # special case 2
        
        v <- data.table(IFtZhmqaOHbU671928$get_variable(name = i, dims = j, na = na))
        setnames(v,names(v), paste(i,paste(j,collapse="."),sep="_"))
        return(v)
        
      }  # else: pass
    } # else: pass
    
    toRead  <- copy(IFtZhmqaOHbU671928$curr_var_tab)
    toRead[,len:= unlist(lapply(dims, FUN= length))]
    
      if(!missing(i) || !missing(j)){   # all cases except db[]

        if(missing(i) || is.na(i) ){      # all existing db[, ...] or db[._ , ...]
          
          i       <- unique(toRead$variable)      
          i2      <- i
          
        } else if(is.vector(i) && length(i) == 0L){ 
          
          wrn(18);return(NULL)                          # reading with an empty vector of variable names"
          
        } else { 
          
          toRead   <- toRead[variable %in% i,]          # matching variables in data base
          i2       <- unique(toRead$variable)
          
        }
        
        if(length(i2) == 0L){
          wrn(19,i);return(NULL)                        # the database doesn't match required variables                     
        }
        
        if(length(i_diff <- setdiff(i, i2))>0) {
          wrn(20,i_diff)                                # i_diff not found
        }
      
      
      if(!missing(j)){ # selection based on dimension
        
        if(is.vector(j) && (is.na(j) || j != .all)) {
          
          if(length(j) > 0){  # i.e. db[,]
            
            toRead <- toRead[len == length(j)]            
            toRead <- toRead[unlist(lapply(dims, FUN=function(a){all(a==j | is.na(j))}))]        
          } 
          
        } # else  .all => read all dimensions
        
        
      } else {  # missing(j)  
        
        toRead   <- toRead[len==0L,]            # matching zero-dim variables in thr data base table
      }
      
    } # else sepecial case 3) db[], etire data base table 
    
    
    if(nrow(toRead)==0) {
      wrn(21,ifelse(!missing(j),j,""));return(NULL)  # nothing to get, probably missmatching dimensions
    }
    
    k <- 1L
    variable <- toRead[k,]$variable
    varName  <- toRead[k,paste(variable,paste(dims[[1]],collapse="."),
                               sep=ifelse(length(dims[[1]])>0,"_",""))]
    
    resOut <- data.table(IFtZhmqaOHbU671928$get_variable(name = variable, dims = toRead[k,dims[[1]]], na = na))
    setnames(resOut,names(resOut),varName)
    
    if(nrow(IFtZhmqaOHbU671928$curr_var_tab) == 1) return(resOut)  # one entry only thus ready!
    
    for(k in 2:nrow(toRead)) {
      variable <- toRead[k,]$variable
      varName  <- toRead[k,paste(variable,paste(dims[[1]],collapse="."),
                                 sep=ifelse(length(dims[[1]])>0,"_",""))]  
      resOut[,eval(varName):= IFtZhmqaOHbU671928$get_variable(name = variable, dims = toRead[k,dims[[1]]], na = na)]
      
    }
    
    # SORING of columns - temporary solution
    # it must be som less TrIcKy way of doing this

    sL <- str_split(names(resOut), "_")
    variables <- unlist(lapply(sL,FUN=head,n=1L))
    sL <- unlist(lapply(sL,FUN=function(x)ifelse(length(x)==1,NA,x[-1]))) # dimensions
    sL <- str_split(sL, "\\.")
    #SORT?
    if(all(unlist(lapply(sL,FUN=
                           function(x)length(grep("^[0-9]*$",x))== length(x) || is.na(x)
    )))){ #numeric dimensions are applicable
      nrDimCol <- max(unlist(lapply(sL,FUN=  function(x)length(x) )))
      dT <- data.table(Nr = (1:length(variables)),varName=variables)  
      dimNames <- paste("D",1:nrDimCol,sep="")
      for(k in 1:nrDimCol) dT[,eval(dimNames[k]):= unlist(lapply(sL, FUN = function(x)as.integer(x[k])))]
      setkeyv(dT,c("varName",dimNames))       
      resOut <- resOut[,dT$Nr,with = FALSE]
    }
    
    
    return(resOut)
  }
) 


#' Assign content to variable 
#' 
#' Function to assign content, either data or documentation,
#' to a Coldbir variable. Overloads the `[<-`-method.
#' 
#' @param x cdb object
#' @param i variable name
#' @param j variable dims
#' @param value value
#'
#' @name `[<-`
#' @docType methods
#' @rdname replace-methods
setMethod(
  f = "[<-",
  signature = "cdb",
  definition = function(x, i, j, value){    
                                            
  
    if (x$read_only) err(8)
    
    if(missing(i) && missing(j)) {
      
      if(is.null(value)) {
        
        x$clean();return(x)
        
      } else  if(is(value,"data.frame")){
        
          colNames <- names(value)    
          if(length(grep("_",colNames)>0)){
            
            sL <- str_split(colNames, "_")
            varNames <- unlist(lapply(sL,FUN=head,n=1L))
            sL <- unlist(lapply(sL,FUN=function(x)ifelse(length(x)==1,NA,x[-1]))) # dimensions left
            sL <- str_split(sL, "\\.")
            
          } else {
            
            varNames  <- colNames
            sL        <- as.list(rep(NA_character_,length(colNames)))
          }
          
          for(k in 1:length(varNames)) {
            
            if(is.na((currDim <- sL[[k]])[1])) currDim <- NULL
            
            if(is(value,"data.table")) v <- value[,k,with=FALSE][[1]] else v <- value[,k]
            
            x$put_variable(x = v, name = varNames[k], dims = currDim)
          }
          
          return(x)
          
      } else {
        wrn(22,class(value));return(x)
      }
    }
    
    if (all(class(value) == "doc")) {
      
      # Create readme.json
      x$put_doc(x = value$to_json(), name = i)
      
    } else if(is.null(value)){

      if (missing(j)) j <- NULL      
      x$delete_variable(name = i, dims = j)
      
    } else {
      
      if(is(value,"data.frame") && !missing(i)) {
        unusedName    <- i
        if(is.na(i))   unusedName <- "._" else
        if(is.null(i)) unusedName <- "NULL" else
        if(is.vector(i) && length(i) == 0L) unusedName <- "empty vector"
        wrn(24, unusedName)
      }
      
      if (missing(j)) j <- NULL
      x$put_variable(x = value, name = i, dims = j)
      
      
    }
    
    return(x)
  }
)
