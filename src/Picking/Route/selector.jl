# src/Picking/Route/selector.jl

# Each routing strategy builds one complete picker route and returns the
# unserved SKU IDs. Startup validation checks all enum entries.
const ROUTING_STRATEGIES = Dict{RoutingHeuristic, Function}(
    ASTAR_HEURISTIC => astar_route_order_strategy,
    GREEDY => greedy_route_order!
)

function route_order_selector(
    heuristic::RoutingHeuristic,
    cfg::ExperimentConfig,
    order::Vector{Int},
    stock::Matrix{Int},
    skus::Vector{SKU},
    warehouse::Warehouse,
    picker_capacity::Int,
    distance_matrix::Matrix{Float64},
    depot_distance::Vector{Float64},
    budget::RoutingBudget
)
    n_locations = length(warehouse.locations)
    size(distance_matrix) == (n_locations, n_locations) ||
        customization_error("Routing distance_matrix has size $(size(distance_matrix)); expected ($n_locations, $n_locations).")
    length(depot_distance) == n_locations ||
        customization_error("Routing depot_distance has length $(length(depot_distance)); expected $n_locations.")
    size(stock) == (n_locations, length(skus)) ||
        customization_error("Routing stock has size $(size(stock)); expected ($n_locations, $(length(skus))).")
    all(isfinite, distance_matrix) && all(>=(0), distance_matrix) &&
        all(isfinite, depot_distance) && all(>=(0), depot_distance) ||
        customization_error("Routing distances must be finite and non-negative.")
    validate_positive(picker_capacity, "picker_capacity")

    strategy = get(ROUTING_STRATEGIES, heuristic, nothing)
    strategy === nothing &&
        customization_error("No routing implementation is registered for $heuristic.")
    stock_before = copy(stock)
    result = strategy(
        cfg, order, stock, skus, warehouse, picker_capacity,
        distance_matrix, depot_distance, budget
    )
    result isa Tuple{Pickers, Vector{Int}} ||
        customization_error("Routing strategy $heuristic must return (Pickers, Vector{Int}).")

    picker, remaining_order = result
    validate_picker(picker; depot_id=warehouse.depot.id)
    expected_distances = zeros(Float64, length(picker.picker_rout))
    for stop in 2:length(picker.picker_rout)
        previous = picker.picker_rout[stop - 1]
        current = picker.picker_rout[stop]
        expected_distances[stop] = if previous == warehouse.depot.id
            validate_index_bounds(current, n_locations, "route location")
            depot_distance[current]
        elseif current == warehouse.depot.id
            validate_index_bounds(previous, n_locations, "route location")
            depot_distance[previous]
        else
            validate_index_bounds(previous, n_locations, "route location")
            validate_index_bounds(current, n_locations, "route location")
            distance_matrix[previous, current]
        end
    end
    all(isapprox.(picker.distance, expected_distances; atol=1e-8, rtol=1e-8)) ||
        customization_error("Routing strategy $heuristic returned distances that do not match its route.")
    all(sku -> 1 <= sku <= length(skus), remaining_order) ||
        customization_error("Routing strategy $heuristic returned an invalid SKU in remaining_order.")

    requested = zeros(Int, length(skus))
    picked = zeros(Int, length(skus))
    remaining = zeros(Int, length(skus))
    for sku in order
        validate_index_bounds(sku, length(skus), "order SKU")
        requested[sku] += 1
    end
    for shelf_skus in picker.sku_shelf, sku in shelf_skus
        sku == 0 && continue
        validate_index_bounds(sku, length(skus), "picked SKU")
        picked[sku] += 1
    end
    for sku in remaining_order
        remaining[sku] += 1
    end
    picked + remaining == requested ||
        customization_error("Routing strategy $heuristic returned picks and remaining SKUs that do not match the input order.")

    all(>=(0), stock) ||
        customization_error("Routing strategy $heuristic returned negative stock quantities.")
    stock_used = stock_before - stock
    all(>=(0), stock_used) ||
        customization_error("Routing strategy $heuristic increased stock quantities.")
    vec(sum(stock_used; dims=1)) == picked ||
        customization_error("Routing strategy $heuristic stock changes do not match its reported picks.")
    picked_volume = sum(picked[sku] * skus[sku].volume for sku in eachindex(skus))
    picked_volume <= picker_capacity + 1e-8 ||
        customization_error("Routing strategy $heuristic exceeded picker capacity.")

    return picker, remaining_order
end
