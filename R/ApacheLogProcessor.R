
#' read.apache.log
#'
#' Reads the Apache Log Common or Combined Format and return a data frame with the log data.
#'
#' The functions recives a full path to the log file and process the default log in common or combined format of Apache. 
#' LogFormat "\%h \%l \%u \%t \\"\%r\\" \%>s \%b \\"\%\{Referer\}i\\" \\"\%\{User-Agent\}i\\"" combined
#' LogFormat "\%h \%l \%u \%t \\"\%r\\" \%>s \%b\\" common
#'
#' @param file string. Full path to the log file.
#' @param format string. Values "common" or "combined" to set the input log format. The default value is the combined.
#' @param url_includes regex. If passed only the urls that matches with the regular expression passed will be returned.
#' @param url_excludes regex. If passed only the urls that don't matches with the regular expression passed will be returned.
#' @param columns list. List of columns names that will be included in data frame output. All columns is the default value. c("ip", "datetime", "url", "httpcode", "size" , "referer", "useragent")
#' @param num_cores number. Number of cores for parallel execution, if not passed 1 core is assumed. Used only to convert datetime form string to datetime type.
#' @param fields_have_quotes boolean. If passesd as true search and remove the quotes inside the all text fields. 
#' @return a data frame with the apache log file information.
#' @author Diogo Silveira Mendonca
#' @seealso \url{http://httpd.apache.org/docs/1.3/logs.html}
#' @examples
#' path_combined = system.file("examples", "access_log_combined.txt", package = "ApacheLogProcessor")
#' path_common = system.file("examples", "access_log_common.txt", package = "ApacheLogProcessor")
#' 
#' #Read a log file with combined format and return it in a data frame
#' df1 = read.apache.access.log(path_combined)
#'
#' #Read a log file with common format and return it in a data frame
#' df2 = read.apache.access.log(path_common, format="common") 
#' 
#' #Read only the lines that url matches with the pattern passed
#' df3 = read.apache.access.log(path_combined, url_includes="infinance")
#' 
#' #Read only the lines that url matches with the pattern passed, but do not matche the exclude pattern
#' df4 = read.apache.access.log(path_combined, 
#' url_includes="infinance", url_excludes="infinanceclient")
#' 
#' #Return only the ip, url and datetime columns
#' df5 = read.apache.access.log(path_combined, columns=c("ip", "url", "datetime"))
#' 
#' #Process using 2 cores in parallel for speed up. 
#' df6 = read.apache.access.log(path_combined, num_cores=2)
#' 
#' 
#' @import foreach
#' @import parallel
#' @import doParallel
#' @importFrom utils read.csv
#' @export
read.apache.access.log <- function(file, format = "combined", url_includes = "", url_excludes = "",
                                     columns = c("ip", "datetime", "url", "httpcode", "size" , 
                                                 "referer", "useragent"), num_cores = 1,
                            fields_have_quotes = TRUE){
  
  #=== REMOVE QUOTES INSIDE QUOTES IN URL FIELD ===================================
  if(fields_have_quotes == TRUE){
    text <- readLines(file)
    text <- gsub("\\\\\"", "'", text)
    tConnection <- textConnection(text)
  }else{
    tConnection <- file
  }
  #=== LOAD THE APACHE ACCESS LOG FILE AS CSV =====================================
  
  logDf = read.csv(tConnection, header = FALSE, sep = " ", quote = "\"",
                   dec = ".", fill = FALSE, stringsAsFactors = FALSE)
  
  if (fields_have_quotes == TRUE){
    close(tConnection)
  }
  
  #=== SET UP THE COLUMNS =========================================================
  
  #remove the columns that will not be used
  logDf$V2 <- NULL; 
  logDf$V3 <- NULL; 
  
  #set the column names
  if(format == "common"){
    cl <- c("ip", "datetime", "timezone", "url", "httpcode", "size")
    colnames(logDf) <- cl
    columns <- columns[columns %in% cl]
  }else{
    colnames(logDf) <- c("ip", "datetime", "timezone", "url", "httpcode", "size" , "referer", "useragent")  
  }
  
  
  #include only the columns required
  c_include = c()
  for (col in colnames(logDf)){
    if (col %in% columns){
      c_include <- c(c_include, col)
      if(col == "datetime"){
        c_include <- c(c_include, "timezone")
      }
    }
  }
  logDf <- logDf[,c_include]
  
  #=== APPLY RULES FROM LINES ====================================================
  
  #filter the lines to be included
  line_numbers <- grep(url_includes, t(logDf["url"]))
  
  #filter the lines to be excluded
  if(url_excludes != ""){
    line_numbers <- 
      line_numbers[ !line_numbers %in% 
                              grep(url_excludes, t(logDf["url"]))]
  }
  
  #Get only the necessary lines
  logDf <- logDf[line_numbers,]
  
  #=== CLEAR THE DATETIME AND TIMEZONE COLUMNS ====================================
  if ("datetime" %in% c_include){
    
    #Create a vector of dates
    dates = seq( as.POSIXlt(Sys.Date()), by=1, len=nrow(logDf))
    lct <- Sys.getlocale("LC_TIME") 
    Sys.setlocale("LC_TIME", "C")
    
    #CREATE CLUSTERS FOR PARALLEL EXECUTION
    cl <- makeCluster(num_cores)
    registerDoParallel(cl)
    
    #parse the dates form data frame to dates vector
    i <- 0
    dates <- foreach (i = 1:nrow(logDf), .combine=rbind) %dopar%{
      Sys.setlocale("LC_TIME", "C")
      datetimeWithTimezone = paste(logDf$datetime[i], logDf$timezone[i])
      dates[i] <- strptime(datetimeWithTimezone, format="[%d/%b/%Y:%H:%M:%S %z]")
      return(dates[i])
    }
    
    Sys.setlocale("LC_TIME", lct)
    dates <- as.POSIXct(dates, origin="1970-01-01")
    
    #Shutdown the cluster
    stopCluster(cl)
    
    #Create a new data frame with coverted dates
    datesFrame <- data.frame(dates)
    colnames(datesFrame) <- c("datetime")
    
    #Remove old date and timezone columns
    logDf$datetime <- NULL; 
    logDf$timezone <- NULL;
    
    #Inserts the converted dates in logDf data frame
    logDf <- cbind(logDf, datesFrame)
  }
  
  
  #=== CONVERT THE SIZE COLUMN FROM TEXT TO NUMERIC ===========================
  
  if("size" %in% c_include){
    sizes <- logDf$size
    sizes <- as.numeric(sizes)
    logDf$size <- NULL
    sizesFrame <- data.frame(sizes)
    colnames(sizesFrame) <- c("size")
    logDf <- cbind(logDf, sizesFrame)
  }
  
  #=== RETURN THE DATA FRAME ==================================================
  logDf
  
}


#' Reads multiple files of apache web server. 
#' 
#' The files can be gziped or not. If the files are gziped they are extracted once at time, processed and after only the extracted file is deleted.
#' 
#'
#' @param path path where the files are located
#' @param prefix the prefix that identify the logs files
#' @param verbose if prints messages during the processing
#' @param ... parameter to be passed to read.apache.access.log function
#'
#' @return a data frame with the apache log files information.
#' @author Diogo Silveira Mendonca
#' 
#' @examples
#' path <- system.file("examples", package="ApacheLogProcessor")
#' path <- paste(path, "/", sep="")
#' 
#' #read multiple gziped logs with the prefix m_access_log_combined_
#' dfLog <- read.multiple.apache.access.log(path, "m_access_log_combined_")
#' 
#' @export
read.multiple.apache.access.log <- function(path, prefix, verbose = TRUE, ...){
  #create the dataframe variable
  df <- NULL
  #list the log files in the path
  prefix <- paste("^", prefix, sep="")
  
  fVector <- list.files(path, pattern = prefix)
  
  if(verbose) print("Starting the log processing. This may take a long time...")
  #for each log file
  for (inputFile in fVector) {
    if(verbose) print(paste("Processing file ", inputFile))
    
    #check if the file is gziped
    gziped = FALSE
    gzipedFile <- NULL
    if(grepl("\\.gz$", inputFile)){
      gziped = TRUE
      
      #store the name of gziped file
      gzipedFile <- inputFile
      
      #change the input file name for unziped file
      inputFile <- sub(".gz", "", inputFile)
      
      #unzip the file
      if(verbose) print(paste("Unziping ", gzipedFile))
      write(readLines(zz <- gzfile(paste(path, gzipedFile, sep=""))), 
            file = paste(tempdir(), inputFile, sep="\\"))
      close(zz)
      unlink(zz)
    }
    
    #build the full file path
    if(gziped == TRUE){
      f <- paste(tempdir(), inputFile, sep = "\\")
    }else{
      f <- paste(path, inputFile, sep = "")
    }
    
    #read the log
    if(verbose) print(paste("Reading file ", inputFile))
    dfTemp <- read.apache.access.log(file = f, ...)
    #if the first file read
    if(is.null(df)){
      #just assing
      df <- dfTemp
    }else{
      #else concat with the previous dataframe
      df <- rbind(df, dfTemp)
    }

    #delete the uziped file
    if(gziped){
      file.remove(paste(tempdir(), inputFile, sep="\\"))
      if(verbose) print(paste("Removed ", inputFile))
    }
  }
  
  #sort the data frame by timestamp
  df <- df[order(df$datetime, decreasing=FALSE), ]
  
  #rbind cast the date time format to integer, casting it back to date time
  dates <- as.POSIXct(df$datetime, origin="1970-01-01")
  #Create a new data frame with coverted dates
  datesFrame <- data.frame(dates)
  colnames(datesFrame) <- c("datetime")
  #Removes the old column
  df$datetime <- NULL
  #Inserts the converted dates in logDf data frame
  df <- cbind(df, datesFrame)
  #Clear the memory
  remove(dates)
  remove(datesFrame)
  
  #return the dataframe
  df
}

#' Clear a list of URLs according parameters. 
#'
#' @param urls list of URLs
#' @param remove_http_method boolean. If the http method will be removed from the urls.
#' @param remove_http_version booelan. If the http version will be removed from the urls.
#' @param remove_params_inside_url boolean. If the parameters inside the URL, commonly used in REST web services, will be removed from the urls.
#' @param remove_query_string boolean. If the query string will be removed from the urls.
#'
#' @return a vector with the urls cleaned
#' @author Diogo Silveira Mendonca
#' @export
#'
#' @examples
#' 
#' #Load the path to the log file
#' path_combined = system.file("examples", "access_log_combined.txt", package = "ApacheLogProcessor")
#' 
#' #Read a log file with combined format and return it in a data frame
#' df1 = read.apache.access.log(path_combined)
#' 
#' #Clear the urls
#' urls <- clear.urls(df1$url)
#' 
#' #Clear the urls but do not remove query strings
#' urlsWithQS <- clear.urls(df1$url, remove_query_string = FALSE)
#' 
#' #Load a log which the urls have parameters inside
#' path2 = system.file("examples", 
#' "access_log_with_params_inside_url.txt", package = "ApacheLogProcessor")
#' 
#' #Read a log file with combined format and return it in a data frame
#' df2 = read.apache.access.log(path2, format = "common")
#' 
#' #Clear the urls with parameters inside
#' urls2 <- clear.urls(df2$url)
#' 
clear.urls <- function(urls, remove_http_method = TRUE, 
                       remove_http_version = TRUE, 
                       remove_params_inside_url = TRUE, 
                       remove_query_string = TRUE){
  
  #instantiate a new vector for the urls cleaned
  urlsClean <- vector(length = length(urls))
  for(i in 1:length(urls)){
    urlsClean[i] <- urls[i]
    
    #removes the query string
    if (remove_query_string){
      urlsClean[i] <- sub("\\?.* ", " ", urlsClean[i])
    }
    #removes the http version
    if(remove_http_version){
      urlsClean[i] <- sub(" HTTP/.*", "", urlsClean[i])
    }
    #removes the url method
    if (remove_http_method){
      urlsClean[i] <- sub("[A-Z]* ", "", urlsClean[i])
    }
    #removes the parameters inside urls
    if (remove_params_inside_url){
      #Common Parameter Patterns
      urlsClean[i] <- gsub("/[0-9]+$", "", urlsClean[i])
      urlsClean[i] <- gsub("/[0-9]+\\?", "\\?", urlsClean[i])
      urlsClean[i] <- gsub("/[0-9]+/", "/", urlsClean[i])
      
      #OsTicket Parameter Patterns
      urlsClean[i] <- gsub("\\.[0-9]+$", "", urlsClean[i])
      urlsClean[i] <- gsub("\\..{12}$", "", urlsClean[i])
    }
    
  }
  
  urlsClean
  
}


#' Extract from the data frame with the access log the urls query strings parameters and values.
#'
#' The function supports multivalued parameters, but does not support parameters inside urls yet.
#' @param dfLog a dataframe with the access log. Can be load with read.apache.access.log or read.multiple.apache.access.log.
#'
#' @return a structure of data frames with query strings parameters for each url of the log
#' @author Diogo Silveira Mendonca
#' @importFrom utils URLdecode
#' @export 
#'
#' @examples
#' #Load a log which the urls have query strings
#' path = system.file("examples", "access_log_with_query_string.log", package = "ApacheLogProcessor")
#' 
#' #Read a log file with combined format and return it in a data frame
#' df = read.apache.access.log(path, format = "common")
#' 
#' #Clear the urls with parameters inside
#' params <- get.url.params(df)
#' 
get.url.params <- function(dfLog){
  
  #extract the url column
  urls <- dfLog$url
  
  #instantiate a new list for the urls parameter
  urlList <- list()
  
  #for each url access
  for(i in 1:length(urls)){
    
    #clear urls for work only with the data needed
    urlClean <- clear.urls(urls[i])
    urlParams <- clear.urls(urls[i], remove_query_string = FALSE)
    
    #instantiate the data frame for parameters 
    if(is.null(urlList[[urlClean]])){
      dfParams <- data.frame(stringsAsFactors=FALSE)
    }else{
      dfParams <- urlList[[urlClean]]
    }
    
    #get the url parameters
    getParams <- unlist(strsplit(urlParams, "?", fixed = TRUE))[2]
    
    #check if the url has GET parameters
    if(!is.na(getParams)){
      
      #create a vector to store parameters name when they are discovered
      newParams <- vector()
      
      #get the parameter splited as a vector
      parameter <- unlist(strsplit(getParams, "&", fixed = TRUE))
      
      #new list to store the parameters for the urls
      paramsList <- list()
      
      #store the the data frame row index
      paramsList["dfRowIndex"] <- i
      
      #store the the data frame row name
      paramsList["dfRowName"] <- rownames(dfLog[i, ])
      
      multiValuedParams <- vector()
      
      #for each parameter
      for(j in 1:length(parameter)){
        
        #split the key and value
        keyValue <- unlist(strsplit(parameter[j], "=", fixed = TRUE))
        key <- keyValue[1]
        
        #avoid malformed params
        if(is.na(key)) next
        
        #decode the url value
        value <- URLdecode(keyValue[2])
        
        #store the key-value pair 
        #first check if is known that the parameter has multiple values
        if(key %in% multiValuedParams){
          #stores in the list
          paramsList[[key]][nrow(paramsList[[key]]) + 1, "values"] <- value
        }else{
          #we do not know if it is multi-valued
          #check if it is not multi-valued
          if(!(key %in% names(paramsList))){
            #store the single value
            paramsList[key] <- value
          }else{
            #if it is multi-valued (second value found for the same parameter)
            #create a data frame to store the values
            tempFrame <- data.frame(stringsAsFactors = FALSE)
            #the old value is the first
            tempFrame[1, "values"] <- paramsList[key]
            #the new value is the second
            tempFrame[2, "values"] <- value
            #stores the list
            paramsList[[key]] <- tempFrame
            #now we know that the parameter is multi-valued
            multiValuedParams[[length(multiValuedParams) + 1]] <- key
          }
          
        }
        
        
        #check if the key already exists as column in data frame
        if(!(key %in% colnames(dfParams))){
          #create a column
          column <- vector(length = nrow(dfParams))
          
          #add the column in data frame
          dfParams <- cbind(dfParams, column, stringsAsFactors=FALSE)
          
          #set their name
          colnames(dfParams)[length(colnames(dfParams))] <- key
          
          #store the key name for new parameters
          newParams[[length(newParams)+1]] <- key
        }
        
      }
      
      #check the columns that exists in the data frame but not in parameter
      absentParamNames <- colnames(dfParams)[!(colnames(dfParams) %in% names(paramsList))]
      
      #include the absent parameters in the line
      for(name in absentParamNames){
        paramsList[name] <- NA
      }
      
      #include the row in the data frame
      dfParams <- rbind(dfParams, paramsList, make.row.names=FALSE, stringsAsFactors=FALSE)
      
      
      #replace FALSE value by NA in the new columns
      if (length(newParams) > 0){
        for(p in 1:length(newParams)){
          for(k in 1:(nrow(dfParams) -1)){
            dfParams[k, newParams[p]] <- NA
          }
        }
      }
        
    }#end if the URL has parameters
    
    #store the data frame in URL index
    urlList[[urlClean]] <- dfParams
    
  }#end for each URL
  
  #return the list of URLs with its respective parameters data frame
  urlList
  
}

#' Read the apache erro log file and loads it to a data frame.
#'
#' @param file path to the error log file
#' @param columns which columns should be loaded. Default value is all columns. c("datetime", "logLevel", "pid", "ip_port", "msg")
#'
#' @return a data frame with the error log data
#' @author Diogo Silveira Mendonca
#' @import stringr
#' @export
#'
#' @examples
#' 
#' #Loads the path of the erro log
#' path <- system.file("examples", "error_log.log", package = "ApacheLogProcessor")
#' 
#' #Loads the error log to a data frame
#' dfELog <- read.apache.error.log(path)
#' 
read.apache.error.log <- function(file, columns = c("datetime", "logLevel", "pid", "ip_port", "msg")){
  #store the client locale and change it
  lct <- Sys.getlocale("LC_TIME") 
  Sys.setlocale("LC_TIME", "C")
  #open the file for reading
  con  <- file(file, open = "r")
  #create the return data frame
  df <- data.frame(stringsAsFactors = FALSE)
  #create a counter variable
  i <- 0
  #for each line in file
  while (length(oneLine <- readLines(con, n = 1, warn = FALSE)) > 0) {
    #increment the counter variable
    i <- i + 1
    
    #list the regexp format for each column
    regChunks <- list()
    regChunks["datetime"] <- "\\[(.*?)\\]"
    regChunks["logLevel"] <- "\\[:(.*?)\\]"
    regChunks["pid"] <- "\\[pid (.*?)\\]"
    regChunks["ip_port"] <- "\\[client (.*?)\\]"
    regChunks["msg"] <- "(.*)"
    
    #build one regular expression with the columns passed
    strRegexp <- NULL
    for(column in columns){
      if (is.null(strRegexp)){
        strRegexp <- regChunks[column]
      }else{
        strRegexp <- paste(strRegexp, regChunks[column], sep=" ")  
      }
    }
    
    #matchs the regexp
    dfChunks <- as.data.frame(str_match(oneLine, strRegexp), stringsAsFactors = FALSE)
    
    #chek if the line is well formed
    if(ncol(dfChunks) == (length(columns)+1)){
      #assing columns names
      names(dfChunks) <- c("line", columns)
      
      #create a new entry
      entry <- list()
      
      #for each field
      for(column in columns){
        #get its value
        value <- dfChunks[1, column]
        
        #if the column is datetime clean and process datetime
        if(column == "datetime"){
          value <- dfChunks$datetime[1]
          #strip miliseconds
          value <- sub("\\.[0-9]+", "", value)
          #parse date and time
          value <- strptime(value, format="%a %b %e %H:%M:%S %Y")
          #convert the datetime to include in dataframe
          value <- as.POSIXct(value, origin="1970-01-01")
        }
        
        #store the entry
        entry[column] <- value
      }

      #insert a new row in the data frame
      df <- rbind(df, entry, stringsAsFactors = FALSE)
    }else{
      #skip and warn if it is a malformed line
      warning(gettextf("Line %d at %s skiped. Diferent number of fields (%d) and columns (%d).", i, file, ncol(dfChunks) -1, length(columns)))
    }
    
  }#end of one line
  
  #close the log file
  close(con)
  
  #convert datetime back to a readable format
  df$datetime <- as.POSIXlt(df$datetime, origin="1970-01-01")
  
  #restore the client locale
  Sys.setlocale("LC_TIME", lct)

  #return the data frame
  df
}

#' Reads multiple apache error log files and loads them to a data frame.
#'
#' @param path path to the folder that contains the error log files
#' @param prefix prefix for all error log files that will be loaded
#' @param verbose if the function prints messages during the logs processing 
#' @param ... parameters to be passed to read.apache.error.log function
#'
#' @return a data frame with the error log data
#' @export
#'
#' @examples
#' 
#' path <- system.file("examples", package="ApacheLogProcessor")
#' path <- paste(path, "/", sep="")
#' 
#' #read multiple gziped logs with the prefix m_access_log_combined_
#' dfELog <- read.multiple.apache.error.log(path, "m_error_log_")
#' 
read.multiple.apache.error.log <- function(path, prefix, verbose = TRUE, ...){
  #create the dataframe variable
  df <- NULL
  #list the log files in the path
  prefix <- paste("^", prefix, sep="")
  
  fVector <- list.files(path, pattern = prefix)
  
  if(verbose) print("Starting the log processing. This may take a long time...")
  #for each log file
  for (inputFile in fVector) {
    if(verbose) print(paste("Processing file ", inputFile))
    
    #check if the file is gziped
    gziped = FALSE
    gzipedFile <- NULL
    if(grepl("\\.gz$", inputFile)){
      gziped = TRUE
      
      #store the name of gziped file
      gzipedFile <- inputFile
      
      #change the input file name for unziped file
      inputFile <- sub(".gz", "", inputFile)
      
      #unzip the file
      if(verbose) print(paste("Unziping ", gzipedFile))
      write(readLines(zz <- gzfile(paste(path, gzipedFile, sep=""))), 
            file = paste(tempdir(), inputFile, sep="\\"))
      close(zz)
      unlink(zz)
      
      
    }
    
    #build the full file path
    if(gziped == TRUE){
      f <- paste(tempdir(), inputFile, sep = "\\")
    }else{
      f <- paste(path, inputFile, sep = "")
    }
    
    #read the log
    if(verbose) print(paste("Reading file ", inputFile))
    dfTemp <- read.apache.error.log(file = f, ...)
    #if the first file read
    if(is.null(df)){
      #just assing
      df <- dfTemp
    }else{
      #else concat with the previous dataframe
      df <- rbind(df, dfTemp)
    }
    
    #delete the uziped file
    if(gziped){
      file.remove(paste(tempdir(), inputFile, sep="\\"))
      if(verbose) print(paste("Removed ", inputFile))
    }
  }
  
  #sort the data frame by timestamp
  df <- df[order(df$datetime, decreasing=FALSE), ]
  
  #rbind cast the date time format to integer, casting it back to date time
  dates <- as.POSIXct(df$datetime, origin="1970-01-01")
  #Create a new data frame with coverted dates
  datesFrame <- data.frame(dates)
  colnames(datesFrame) <- c("datetime")
  #Removes the old column
  df$datetime <- NULL
  #Inserts the converted dates in logDf data frame
  df <- cbind(df, datesFrame)
  #Clear the memory
  remove(dates)
  remove(datesFrame)
  
  #return the dataframe
  df
}

#' Parses PHP mesages and store its parts in a data frame that contains level, message, file, line number and referer.
#'
#' @param dfErrorLog Error log load with the read.apache.error.log or read.multiple.apache.error.log functions.
#'
#' @return a data frame with PHP error message split in parts. 
#' @export
#'
#' @examples
#' 
#' #Loads the path of the erro log
#' path <- system.file("examples", "error_log.log", package = "ApacheLogProcessor")
#' 
#' #Loads the error log to a data frame
#' dfELog <- read.apache.error.log(path)
#' 
#' dfPHPMsgs <- parse.php.msgs(dfELog)
#' 
#' 
parse.php.msgs <- function(dfErrorLog){
  
  #create the return data frame
  df <- data.frame(stringsAsFactors = FALSE)
  
  #for each line in error log
  for(i in 1:nrow(dfErrorLog)){
    #extract the message
    msg <- dfErrorLog$msg[i]
    #check if it is a PHP message, same as startsWith
    if (grepl("^PHP", msg)){
      #create a entry
      entry <- list()
      
      #store the the data frame row index
      entry["dfRowIndex"] <- i
      
      #store the the data frame row name
      entry["dfRowName"] <- rownames(dfErrorLog[i, ])
      
      #match the regexp
      dfChunks <- as.data.frame(
        str_match(msg, "PHP (.*?):(.*?) in (.*?) on line ([0-9]+)(, referer: (.*))?"),
        stringsAsFactors = FALSE)
      
      #give names to the columns
      names(dfChunks) <- c("fullMsg", "level", "phpMsg", "file", "lineNo", "fullReferer", "referer")
      
      #move only the intrest data
      entry["level"] <- dfChunks[1, "level"]
      entry["phpMsg"] <- dfChunks[1, "phpMsg"]
      entry["file"] <- dfChunks[1, "file"]
      entry["lineNo"] <- as.numeric(dfChunks[1, "lineNo"])
      entry["referer"] <- dfChunks[1, "referer"]
      
      #bind a new row
      df <- rbind(df, entry, stringsAsFactors = FALSE)
      
    }else{
      #skip and warn if it is not a PHP message
      warning(gettextf("Line %d skiped. Not a PHP message.", i))
    }
    
  }
  
  #return the data frame
  df
}

#' Apache log combined file example.
#'
#' A set of 12 log lines in Apache Log Combined Format
#'
#' @format LogFormat "\%h \%l \%u \%t \\"\%r\\" \%>s \%b \\"\%\{Referer\}i\\" \\"\%\{User-Agent\}i\\"" combined
#' @source \url{http://www.infinance.com.br/}
#' @name access_log_combined
NULL

#' Apache log common file example.
#'
#' A set of 12 log lines in Apache Log Common Format
#'
#' @format LogFormat "\%h \%l \%u \%t \\"\%r\\" \%>s \%b\\" common
#' @source \url{http://www.infinance.com.br/}
#' @name access_log_common
NULL