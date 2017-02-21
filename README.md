# ApacheLogProcessor
R Package to Process the Apache Web Server Access Log Files

Provides capabilities to process Apache HTTPD Log files. The main functionalities are to extract data from access and error log files to data frames.

Functionalities available:

1) Read Apache HTTPD access log in common or combined format to a data frame
2) Read multiple gziped Apache HTTPD access log files to a single data frame
3) Clean URLs and extract its query string parameters
4) Read single or multiple gziped Apache HTTPD erro log to a single data frame
5) Parse PHP error messages from error log and extract relevant information from it