# src/Picking/Route/selector.jl

# Register new routing strategies here; startup validation checks all enum entries.
const ROUTING_STRATEGIES = Dict{RoutingHeuristic, Function}(
    ASTAR_HEURISTIC => astar_next_shelf,
    GREEDY => nearest_next_shelf
)

function next_shelf_selector(
    heuristic::RoutingHeuristic,
    current::Int,
    candidates::Vector{Int},
    distance_matrix::Matrix{Float64},
    depot_distance::Vector{Float64}
)
    size(distance_matrix, 1) == size(distance_matrix, 2) ||
        customization_error("Routing distance_matrix must be square; received size $(size(distance_matrix)).")
    validate_same_length(1:size(distance_matrix, 1), depot_distance, "distance_matrix locations", "depot_distance")
    validate_index_bounds(current, size(distance_matrix, 1), "current location index")
    for candidate in candidates
        validate_index_bounds(candidate, size(distance_matrix, 1), "candidate location index")
    end

    strategy = get(ROUTING_STRATEGIES, heuristic, nothing)
    strategy === nothing &&
        customization_error("No routing implementation is registered for $heuristic.")
    next = strategy(current, candidates, distance_matrix, depot_distance)
    (next === nothing || (next isa Int && !(next isa Bool) && next in candidates)) ||
        customization_error(
            "Routing strategy $heuristic returned $next, which is not one of the candidate location indices."
        )
    return next
end
