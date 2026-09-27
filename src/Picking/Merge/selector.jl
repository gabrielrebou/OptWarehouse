# src/Picking/Merge/selector.jl
#
# Espelha Route/selector.jl: centraliza a escolha entre as
# heuristicas de merge, para merge_main nao precisar saber qual esta
# em uso nem lidar com a diferenca de assinatura entre elas (savings
# precisa de warehouse para calcular centroides; greedy nao).
# Register new merge strategies here; startup validation checks all enum entries.
merge_without_changes(pickers, args...) = pickers
merge_clarke_wright_greedy(
    pickers, distance_matrix, sku_volume, picker_capacity,
    depot_distance, depot_id, warehouse
) = clarke_wright_greedy(
    pickers, distance_matrix, sku_volume, picker_capacity, depot_distance, depot_id
)

const MERGE_STRATEGIES = Dict{MergeHeuristic, Function}(
    CLARKE_WRIGHT_HEURISTIC => clarke_wright_savings,
    CLARKE_WRIGHT => merge_clarke_wright_greedy,
    NO_HEURISTIC => merge_without_changes
)

function merge_selector(
    heuristic::MergeHeuristic,
    pickers::Vector{Pickers},
    distance_matrix::Matrix{Float64},
    sku_volume::Vector{Float64},
    picker_capacity::Float64,
    depot_distance::Vector{Float64},
    depot_id::Int,
    warehouse::Warehouse
)
    strategy = get(MERGE_STRATEGIES, heuristic, nothing)
    strategy === nothing &&
        customization_error("No merge implementation is registered for $heuristic.")
    return strategy(
        pickers, distance_matrix, sku_volume,
        picker_capacity, depot_distance, depot_id, warehouse
    )
end
