# = ========================================================================== =
# - Script: cat.R
# - Desc: Utility functions for formatted console output.
# = ========================================================================== =


## Function: cat.script_title
# - Args:
#   * title: character string, the main script title to print
# - Desc:
#   Prints a formatted, centered-looking title block to the console,
#   surrounded by '%' characters for emphasis.
cat.script_title <- function(title) {
  len <- nchar(title)
  spacer <- strrep("%", len)

  cat(glue::glue("\n%%%{spacer}%%%", .trim = FALSE))
  cat(glue::glue("\n%% {title} %%", .trim = FALSE))
  cat(glue::glue("\n%%%{spacer}%%%\n\n", .trim = FALSE))
}


## Function: cat.section_title
# - Args:
#   * title: character string, the section title to print
# - Desc:
#   Prints a formatted section title to the console,
#   surrounded by '|' characters for visual separation.
cat.section_title <- function(title) {
  len <- nchar(title)
  spacer <- strrep("|", len)

  cat(glue::glue("\n|||{spacer}|||", .trim = FALSE))
  cat(glue::glue("\n|| {title} ||", .trim = FALSE))
  cat(glue::glue("\n|||{spacer}|||\n\n", .trim = FALSE))
}


## Function: cat.subsection_title
# - Args:
#   * title: character string, the subsection title to print
# - Desc:
#   Prints a simple subsection title prefixed by a single '#'.
cat.subsection_title <- function(title) {
  cat(glue::glue("\n# {title}\n\n", .trim = FALSE))
}


## Function: cat.json
# - Args:
#   * json_obj: nested list or atomic object to print
#   * indent: integer, number of spaces per indentation level (default: 2)
# - Desc:
#   Recursively prints a list or JSON-like object in a readable, indented format.
#   Lists are traversed recursively; atomic values are printed inline.
cat.json <- function(json_obj, indent = 0) {

  printRecursive <- function(json_obj, indent_level) {
    if (is.list(json_obj)) {
      cat("\n")
      keys <- names(json_obj)
      for (key in keys) {
        cat(strrep(" ", indent_level * indent))
        cat(glue::glue("- {key} : "))
        printRecursive(json_obj[[key]], indent_level + 1)
        cat("\n")
      }
      cat(strrep(" ", (indent_level - 1) * indent))
    } else if (is.atomic(json_obj)) {
      cat(glue::glue("{json_obj}"))
    }
  }

  printRecursive(json_obj, 1)
  cat("\n")
}
