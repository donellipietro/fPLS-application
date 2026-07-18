# = ========================================================================== =
# - Script: mesh_utils.R
# - Desc: Utilities for importing mesh data, evaluating fields on meshes,
#         and generating simple test meshes/grids.
# = ========================================================================== =


## Function: import_mesh_data
# - Args:
#   * path: character string, directory containing CSV files:
#           "points.csv", "edges.csv", "elements.csv", "neigh.csv", "boundary.csv"
# - Desc:
#   Loads mesh components from CSV files and returns a named list with matrices:
#   nodes, edges, elements, neigh, boundary.
import_mesh_data <- function(path) {
  mesh_data <- list(
    nodes    = as.matrix(read.csv(file.path(path, "points.csv"))[, -1]),
    edges    = as.matrix(read.csv(file.path(path, "edges.csv"))[, -1]),
    elements = as.matrix(read.csv(file.path(path, "elements.csv"))[, -1]),
    neigh    = as.matrix(read.csv(file.path(path, "neigh.csv"))[, -1]),
    boundary = as.matrix(read.csv(file.path(path, "boundary.csv"))[, -1])
  )
  return(mesh_data)
}


## Function: evaluate_field
# - Args:
#   * grid: matrix or data.frame of evaluation points (each row is a point)
#   * f_at_nodes: numeric vector of field values at mesh nodes
#   * mesh: fdaPDE mesh object compatible with create.FEM.basis()
# - Desc:
#   Builds an fdaPDE FEM function from node values and evaluates it on 'grid'.
#   Returns a numeric vector of field values at the grid locations.
evaluate_field <- function(grid, f_at_nodes, mesh) {

  FEMbasis    <- create.FEM.basis(mesh)
  FEMfunction <- FEM(f_at_nodes, FEMbasis)
  f_at_grid   <- eval.FEM(FEMfunction, grid)

  return(f_at_grid)
}


## Function: unit_square
# - Args:
#   * n_nodes: integer, total number of nodes; should be a perfect square
#              (nodes are laid out on a sqrt(n_nodes) x sqrt(n_nodes) grid)
# - Desc:
#   Generates a structured grid on the unit square [0,1] x [0,1] and builds
#   a 2D mesh with fdaPDE::create.mesh.2D(). Returns a list with matrices:
#   nodes, edges, elements, neigh, boundary.
unit_square <- function(n_nodes) {
  x <- y <- seq(0, 1, length = sqrt(n_nodes))
  grid  <- meshgrid(x, y)
  nodes <- data.frame(as.vector(grid$X), as.vector(grid$Y))
  mesh  <- fdaPDE::create.mesh.2D(nodes)
  mesh_data <- list(
    nodes    = as.matrix(mesh$nodes),
    edges    = as.matrix(mesh$edges),
    elements = as.matrix(mesh$triangles),
    neigh    = as.matrix(mesh$neighbors),
    boundary = as.matrix(as.numeric(mesh$nodesmarkers))
  )
  return(mesh_data)
}


## Function: unit_interval
# - Args:
#   * n_nodes: integer, number of 1D grid points
# - Desc:
#   Generates a uniform grid over the unit interval [0,1].
#   Returns a numeric vector of length 'n_nodes'.
unit_interval <- function(n_nodes){
  x <- seq(0, 1, length = n_nodes)
  return(x)
}
