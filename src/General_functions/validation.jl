function customization_error(message::AbstractString)
    @warn "Invalid project customization: $message"
    throw(ArgumentError(message))
end

function validate_project_configuration(params::Params; data_dir::AbstractString)
    warehouse = params.warehouse_config
    sku = params.sku_generation
    allocation = params.allocation
    picking = params.picking

    warehouse.n_aisles > 0 ||
        customization_error("warehouse_config.n_aisles must be greater than zero.")
    warehouse.n_shelves > 0 ||
        customization_error("warehouse_config.n_shelves must be greater than zero.")
    warehouse.shelf_capacity > 0 ||
        customization_error("warehouse_config.shelf_capacity must be greater than zero.")
    isfinite(warehouse.filling_rate) && 0 < warehouse.filling_rate <= 1 ||
        customization_error("warehouse_config.filling_rate must be in the range (0, 1].")

    isfinite(sku.sigma) && sku.sigma > 0 ||
        customization_error("sku_generation.sigma must be finite and greater than zero.")
    isfinite(sku.tipic_v) && sku.tipic_v > 0 ||
        customization_error("sku_generation.tipic_v must be finite and greater than zero.")
    isfinite(sku.volumetric_module) && sku.volumetric_module > 0 ||
        customization_error("sku_generation.volumetric_module must be finite and greater than zero.")
    all(isfinite, (sku.p_frequency, sku.p_volume, sku.p_quantity)) &&
        all(>=(0), (sku.p_frequency, sku.p_volume, sku.p_quantity)) ||
        customization_error("SKU generation weights (p_frequency, p_volume, p_quantity) must be finite and non-negative.")

    isfinite(allocation.candidate_fraction) &&
        0 < allocation.candidate_fraction <= 1 ||
        customization_error("allocation.candidate_fraction must be in the range (0, 1].")
    allocation.als_k > 0 ||
        customization_error("allocation.als_k must be greater than zero.")
    isfinite(allocation.als_factor) && allocation.als_factor >= 0 ||
        customization_error("allocation.als_factor must be finite and non-negative.")
    !isnan(allocation.distance_factor) && allocation.distance_factor >= 0 ||
        customization_error("allocation.distance_factor must be non-negative; Inf is allowed.")
    isfinite(allocation.message_passing_factor) &&
        0 <= allocation.message_passing_factor <= 1 ||
        customization_error("allocation.message_passing_factor must be in the range [0, 1].")
    allocation.max_variety > 0 ||
        customization_error("allocation.max_variety must be greater than zero.")

    picking.picker_capacity > 0 ||
        customization_error("picking.picker_capacity must be greater than zero.")

    isempty(params.data_names) &&
        customization_error("data_names must contain at least one dataset filename.")
    any(isempty, params.data_names) &&
        customization_error("data_names contains an empty filename.")
    length(unique(params.data_names)) == length(params.data_names) ||
        customization_error("data_names contains duplicate filenames; each dataset must have a unique ID.")

    for filename in params.data_names
        dataset_path = joinpath(data_dir, filename)
        isfile(dataset_path) ||
            customization_error("Dataset '$filename' was not found at '$dataset_path'; add the file or correct data_names.")
    end

    return nothing
end

function validate_registered_strategies()
    registrations = (
        ("allocation", instances(AllocationMethod), keys(ALLOCATION_STRATEGIES)),
        ("routing", instances(RoutingHeuristic), keys(ROUTING_STRATEGIES)),
        ("merge", instances(MergeHeuristic), keys(MERGE_STRATEGIES))
    )

    for (name, declared, registered) in registrations
        missing = setdiff(collect(declared), collect(registered))
        isempty(missing) ||
            customization_error(
                "The $name method(s) $(join(string.(missing), ", ")) are declared in types.jl but not registered. " *
                "Implement the method and add it to the corresponding strategy registry."
            )
    end

    return nothing
end

function validate_experiment_config(cfg::ExperimentConfig, params::Params)
    1 <= cfg.data_id <= length(params.data_names) ||
        customization_error("Experiment data_id=$(cfg.data_id) is outside the configured range 1:$(length(params.data_names)).")
    haskey(ALLOCATION_STRATEGIES, cfg.allocation_method) ||
        customization_error("Allocation method $(cfg.allocation_method) has no registered implementation.")
    haskey(ROUTING_STRATEGIES, cfg.routing_heuristic) ||
        customization_error("Routing heuristic $(cfg.routing_heuristic) has no registered implementation.")
    haskey(MERGE_STRATEGIES, cfg.merge_strategy) ||
        customization_error("Merge strategy $(cfg.merge_strategy) has no registered implementation.")
    return nothing
end

function validate_instance(instance::Instance, filename::AbstractString)
    instance.n_skus > 0 ||
        customization_error("Dataset '$filename' must declare at least one SKU.")
    isempty(instance.orders) &&
        customization_error("Dataset '$filename' contains no orders.")

    for (order_index, order) in enumerate(instance.orders)
        isempty(order.skus) &&
            customization_error("Dataset '$filename' has an empty order at index $order_index.")
        for sku_id in order.skus
            1 <= sku_id <= instance.n_skus ||
                customization_error(
                    "Dataset '$filename' order $order_index references SKU $sku_id, " *
                    "but valid SKU IDs are 1:$(instance.n_skus)."
                )
        end
    end

    return nothing
end

function validate_allocation_matrix(
    allocations::AbstractMatrix,
    instance::Instance,
    skus::Vector{SKU},
    warehouse::Warehouse,
    max_variety::Int;
    capacity_tolerance::Real
)
    isfinite(capacity_tolerance) && capacity_tolerance >= 0 ||
        customization_error("capacity_tolerance must be finite and non-negative; received $capacity_tolerance.")

    size(allocations) == (0, 0) && return nothing
    isempty(allocations) &&
        customization_error("An allocation strategy returned an empty matrix with size $(size(allocations)); use a 0×0 matrix only to report that no feasible allocation was found.")

    expected_size = (length(warehouse.locations), instance.n_skus)
    size(allocations) == expected_size ||
        customization_error(
            "An allocation strategy returned a matrix of size $(size(allocations)); " *
            "expected $expected_size (warehouse locations × SKUs)."
        )
    length(skus) == instance.n_skus ||
        customization_error("SKU generation returned $(length(skus)) SKUs, expected $(instance.n_skus).")
    eltype(allocations) <: Integer ||
        customization_error("An allocation strategy must return integer stock quantities; received matrix element type $(eltype(allocations)).")
    all(>=(0), allocations) ||
        customization_error("An allocation strategy returned negative stock quantities.")

    for (sku_index, sku) in enumerate(skus)
        allocated = sum(@view allocations[:, sku_index])
        allocated == round(Int, sku.quantity) ||
            customization_error(
                "Allocation strategy did not allocate SKU $sku_index completely: " *
                "$allocated units allocated, $(sku.quantity) required."
            )
    end

    for (location_index, location) in enumerate(warehouse.locations)
        volume = sum(
            allocations[location_index, sku_index] * skus[sku_index].volume
            for sku_index in eachindex(skus)
        )
        volume <= location.capacity + capacity_tolerance ||
            customization_error(
                "Allocation strategy exceeded capacity at location $(location.id): " *
                "$volume volume allocated, capacity is $(location.capacity) " *
                "(tolerance: $capacity_tolerance)."
            )
        variety = count(>(0), @view allocations[location_index, :])
        variety <= max_variety ||
            customization_error(
                "Allocation strategy placed $variety SKU varieties at location $(location.id); " *
                "max_variety is $max_variety."
            )
    end

    return nothing
end

function validate_allocation_strategy_result(result)
    required = (:allocations, :sparse_matrix, :U, :V, :S_hat, :W, :P, :S_hat_hat)
    missing = filter(name -> !hasproperty(result, name), required)
    isempty(missing) ||
        customization_error(
            "An allocation strategy result is missing $(join(string.(missing), ", ")); " *
            "return all required fields: $(join(string.(required), ", "))."
        )
    return nothing
end
