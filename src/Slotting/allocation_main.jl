# src/Slotting/allocation_main.jl

function allocation_abc_strategy(context)
    classes = abc_skus(context.skus)
    allocations = abc_allocation(
        context.skus, classes, context.warehouse, context.depot_distance,
        context.params.allocation.max_variety
    )
    return (;
        allocations,
        sparse_matrix = context.empty_matrix,
        U = context.empty_matrix,
        V = context.empty_matrix,
        S_hat = context.empty_matrix,
        W = context.empty_matrix,
        P = context.empty_matrix,
        S_hat_hat = context.empty_matrix
    )
end

function allocation_abc_heuristic_strategy(context)
    classes = abc_skus(context.skus)
    allocations = abc_allocation_heuristic(
        context.skus, classes, context.cooc, context.warehouse,
        context.distance_matrix, context.depot_distance,
        context.params.allocation.max_variety
    )
    return (;
        allocations,
        sparse_matrix = context.empty_matrix,
        U = context.empty_matrix,
        V = context.empty_matrix,
        S_hat = context.empty_matrix,
        W = context.empty_matrix,
        P = context.empty_matrix,
        S_hat_hat = context.empty_matrix
    )
end

function allocation_als_strategy(context)
    sparse_matrix = build_sparse_matrix(
        context.skus, context.warehouse, context.params.allocation.candidate_fraction
    )
    U, V = als(
        sparse_matrix;
        k = context.params.allocation.als_k,
        λ = context.params.allocation.als_factor,
        maxiter = 100,
        tol = 1e-4,
        seed = context.params.sku_generation.seed
    )
    S_hat = U * V'
    allocations = als_allocate(
        S_hat, context.skus, context.warehouse, context.params.allocation.max_variety
    )
    return (;
        allocations,
        sparse_matrix,
        U,
        V,
        S_hat,
        W = context.empty_matrix,
        P = context.empty_matrix,
        S_hat_hat = context.empty_matrix
    )
end

function allocation_message_passing_strategy(context)
    als_result = allocation_als_strategy(context)
    W = correlation_distances(context.distance_matrix, context.params.allocation.distance_factor)
    P = norm_cooccurrence(context.cooc.matrix)
    S_hat_hat = (1 - context.params.allocation.message_passing_factor) * als_result.S_hat +
                context.params.allocation.message_passing_factor * W * als_result.S_hat * P
    allocations = als_allocate(
        S_hat_hat, context.skus, context.warehouse, context.params.allocation.max_variety
    )
    return merge(als_result, (; allocations, W, P, S_hat_hat))
end

const ALLOCATION_STRATEGIES = Dict{AllocationMethod, Function}(
    ABC => allocation_abc_strategy,
    ABC_HEURISTIC => allocation_abc_heuristic_strategy,
    ALS => allocation_als_strategy,
    MESSAGE_PASSING => allocation_message_passing_strategy
)

function allocation_main(cfg::ExperimentConfig, params::Params)

    validate_experiment_config(cfg, params)
    filename = params.data_names[cfg.data_id]
    instance = read_instance(joinpath(@__DIR__, "..", "..", "Data", filename))
    validate_instance(instance, filename)
    warehouse = create_warehouse(cfg,params.warehouse_config)
    depot_distance = compute_depot_distance(cfg,warehouse)
    depot_id = warehouse.depot.id

    cooc = cooccurrence_matrix(instance.orders, instance.n_skus)
    heatmap_main(cooc.matrix, "Co-occurrence Matrix")
    skus = generate_skus(params, instance, warehouse)

    distance_matrix = build_distance_matrix(cfg,warehouse.locations)

    empty_matrix = Matrix{Float64}(undef, 0, 0)
    context = (;
        cfg, params, instance, warehouse, depot_distance, cooc, skus,
        distance_matrix, empty_matrix
    )
    strategy = get(ALLOCATION_STRATEGIES, cfg.allocation_method, nothing)
    strategy === nothing &&
        customization_error("No allocation implementation is registered for $(cfg.allocation_method).")
    strategy_result = strategy(context)
    validate_allocation_strategy_result(strategy_result)
    allocations = strategy_result.allocations

    validate_allocation_matrix(
        allocations, instance, skus, warehouse, params.allocation.max_variety;
        capacity_tolerance = params.sku_generation.volumetric_module / 2
    )

    result = (;
        instance, warehouse, depot_distance, depot_id, cooc, skus,
        sparse_matrix = strategy_result.sparse_matrix,
        U = strategy_result.U,
        V = strategy_result.V,
        S_hat = strategy_result.S_hat,
        distance_matrix,
        W = strategy_result.W,
        P = strategy_result.P,
        S_hat_hat = strategy_result.S_hat_hat,
        allocations
    )

    if !isempty(allocations)
        report_allocation(cfg, result)
    end

    return result
end

# Efeitos colaterais (prints, heatmaps, gráficos) isolados numa função
# separada, para não misturar cálculo com relatório — e para não gerar
# nenhum gráfico quando o resultado vier direto do cache.
function report_allocation(cfg::ExperimentConfig, result)

    do_message_passing = cfg.allocation_method == MESSAGE_PASSING

    print_allocation(
        result.warehouse, result.instance, result.cooc, result.skus,
        result.sparse_matrix, result.S_hat, result.P, result.W, result.S_hat_hat,
        result.allocations, do_message_passing
    )

    warehouse_graph(result.warehouse)
    heatmap_main(result.cooc.matrix, "Co-occurrence Matrix")
    heatmap_main(result.distance_matrix, "Distance Matrix")
    plot_allocation(result.allocations, result.warehouse)

    if cfg.allocation_method in (ALS, MESSAGE_PASSING)
        heatmap_main(result.S_hat, "ALS S_hat Matrix")
    end

    if do_message_passing
        heatmap_main(result.P, "Normalized Co-occurrence Matrix")
        heatmap_main(result.W, "Distance Correlation Matrix")
        heatmap_main(result.S_hat_hat, "Message Passing S_hat_hat Matrix")
    end
end