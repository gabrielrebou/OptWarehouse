# src/Picking/Route/heuristics/greedy_heuristic.jl

# Escolhe a proxima prateleira de forma gulosa pura (sem lookahead):
# so olha a distancia ate cada candidato, ignora o que vem depois.
function nearest_next_shelf(
    current::Int,
    candidates::Vector{Int},
    distance_matrix::Matrix{Float64},
    depot_distance::Vector{Float64}
)
    isempty(candidates) && return nothing

    best_node = nothing
    best_g = Inf

    for node in candidates
        validate_index_bounds(node, size(distance_matrix, 1), "candidate")
        g = current == 0 ? depot_distance[node] : begin
            validate_index_bounds(current, size(distance_matrix, 1), "current")
            distance_matrix[current, node]
        end

        if g < best_g
            best_g = g
            best_node = node
        end
    end

    return best_node
end
