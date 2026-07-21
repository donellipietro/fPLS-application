# = ========================================================================== =
# - Script: paraview_export.R
# - Desc: Minimal ASCII VTU export for the tetrahedral brain application.
# = ========================================================================== =

write_tetrahedral_vtu <- function(path, points, elements, point_data) {
  points <- as.matrix(points)
  elements <- matrix(as.integer(elements), ncol = 4L)
  n_points <- nrow(points)
  n_cells <- nrow(elements)
  if (ncol(points) != 3L || any(elements < 1L) || any(elements > n_points)) {
    stop("invalid tetrahedral mesh for VTU export")
  }
  if (!length(point_data) || is.null(names(point_data)) || any(!nzchar(names(point_data)))) {
    stop("VTU point arrays must be a named nonempty list")
  }
  point_data <- lapply(point_data, function(values) {
    values <- as.numeric(values)
    if (length(values) != n_points || any(!is.finite(values))) {
      stop("each VTU point array must contain one finite value per mesh node")
    }
    values
  })

  write_values <- function(connection, values, type = c("numeric", "integer")) {
    type <- match.arg(type)
    chunk_size <- 10000L
    for (first in seq.int(1L, length(values), by = chunk_size)) {
      last <- min(first + chunk_size - 1L, length(values))
      text <- if (type == "numeric") {
        formatC(values[first:last], digits = 17L, format = "g")
      } else {
        as.character(values[first:last])
      }
      writeLines(paste(text, collapse = " "), connection)
    }
  }

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  connection <- file(path, open = "wt", encoding = "UTF-8")
  on.exit(close(connection), add = TRUE)
  writeLines(c(
    "<?xml version=\"1.0\"?>",
    "<VTKFile type=\"UnstructuredGrid\" version=\"0.1\" byte_order=\"LittleEndian\">",
    "  <UnstructuredGrid>",
    sprintf("    <Piece NumberOfPoints=\"%d\" NumberOfCells=\"%d\">", n_points, n_cells),
    "      <PointData>"
  ), connection)
  for (name in names(point_data)) {
    writeLines(sprintf(
      "        <DataArray type=\"Float64\" Name=\"%s\" format=\"ascii\">",
      name
    ), connection)
    write_values(connection, point_data[[name]])
    writeLines("        </DataArray>", connection)
  }
  writeLines(c(
    "      </PointData>",
    "      <CellData/>",
    "      <Points>",
    "        <DataArray type=\"Float64\" NumberOfComponents=\"3\" format=\"ascii\">"
  ), connection)
  write_values(connection, as.vector(t(points)))
  writeLines(c(
    "        </DataArray>",
    "      </Points>",
    "      <Cells>",
    "        <DataArray type=\"Int64\" Name=\"connectivity\" format=\"ascii\">"
  ), connection)
  write_values(connection, as.vector(t(elements - 1L)), type = "integer")
  writeLines(c(
    "        </DataArray>",
    "        <DataArray type=\"Int64\" Name=\"offsets\" format=\"ascii\">"
  ), connection)
  write_values(connection, seq_len(n_cells) * 4L, type = "integer")
  writeLines(c(
    "        </DataArray>",
    "        <DataArray type=\"UInt8\" Name=\"types\" format=\"ascii\">"
  ), connection)
  write_values(connection, rep.int(10L, n_cells), type = "integer")
  writeLines(c(
    "        </DataArray>",
    "      </Cells>",
    "    </Piece>",
    "  </UnstructuredGrid>",
    "</VTKFile>"
  ), connection)
  invisible(path)
}
