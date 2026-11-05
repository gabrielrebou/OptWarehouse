# src/experiment_runner.jl

using CSV
using DataFrames
using Serialization

function allocation_cache_path(cfg::ExperimentConfig)
    folder_name = "$(cfg.data_id)-$(cfg.allocation_method)"  # sem heuristic/merge

    dir = joinpath(@__DIR__, "..", "Results", folder_name, "Allocation_cache")
    mkpath(dir)

    return joinpath(dir, "allocation_id$(cfg.data_id)_$(cfg.allocation_method).txt")
end

function ensure_allocation(cfg::ExperimentConfig, params::Params, do_allocation::Bool)
    validate_experiment_config(cfg, params)

    if !do_allocation
        cache_file = allocation_cache_path(cfg)

        if isfile(cache_file)
            result = deserialize(cache_file)
            validate_allocation_strategy_result(result)
            required_cache_fields = (:instance, :skus, :warehouse)
            missing_cache_fields = filter(name -> !hasproperty(result, name), required_cache_fields)
            isempty(missing_cache_fields) ||
                customization_error(
                    "Cached allocation is missing $(join(string.(missing_cache_fields), ", ")); " *
                    "delete that cache entry and rerun allocation to rebuild it."
                )
            validate_instance(result.instance, params.data_names[cfg.data_id])
            validate_allocation_matrix(
                result.allocations, result.instance, result.skus, result.warehouse,
                params.allocation.max_variety;
                capacity_tolerance = params.sku_generation.volumetric_module / 2
            )
            return result
        end

        @warn "Allocation not found for ID=$(cfg.data_id), method=$(cfg.allocation_method); calculating it anyway."
    end

    result = allocation_main(cfg, params)

    if !isempty(result.allocations)
        cache_file = allocation_cache_path(cfg)
        serialize(cache_file, result)
    end

    return result
end

function run_experiment(cfg::ExperimentConfig, params::Params, do_allocation::Bool)
    mark = @timed ensure_allocation(cfg, params, do_allocation)
    run_experiment_with_allocation(cfg, params, mark.value, mark.time, mark.bytes)
end

function run_experiment_with_allocation(
    cfg::ExperimentConfig,
    params::Params,
    alloc_result::NamedTuple,
    allocation_time::Float64,
    allocation_bytes::Int64
)
    validate_experiment_config(cfg, params)

    if isempty(alloc_result.allocations)
        save_files(cfg, params.data_names[cfg.data_id], allocation_time, allocation_bytes,0,0,0,0,0,0)
        return nothing
    end
    
    max_route, route_time, route_bytes = @timed route_main(cfg,params,alloc_result)

    if cfg.merge_strategy == NO_HEURISTIC
        report_allocation(cfg,alloc_result)
        print_pickers(cfg, max_route.pickers, params.data_names[cfg.data_id], max_route.distance, max_route.sum_pickers)
        save_files(cfg, params.data_names[cfg.data_id], allocation_time, allocation_bytes, route_time, route_bytes, 0, 0, max_route.distance, max_route.sum_pickers)

    else
        merged_pickers, merge_time, merge_bytes = @timed merge_main(cfg,params,alloc_result,max_route)

        report_allocation(cfg,alloc_result)
        print_pickers(cfg, merged_pickers.pickers, params.data_names[cfg.data_id], merged_pickers.distance, merged_pickers.sum_pickers)
        save_files(cfg, params.data_names[cfg.data_id], allocation_time, allocation_bytes, route_time, route_bytes, merge_time, merge_bytes, merged_pickers.distance, merged_pickers.sum_pickers)
    end

    return nothing
end

# Modo batch: aloca uma vez por (data_id, método), reaproveita para
# todas as combinações de heurística/merge daquele par
function run_batch(params::Params, do_allocation::Bool)
    min_val = read_int_range("Choose the start ID:",length(params.data_names),1)
    max_val = read_int_range("Choose the end ID:",length(params.data_names),min_val)
    for data_id in min_val:max_val
        for method in instances(AllocationMethod)

            # heuristica/merge nao importam para a alocacao em si; um
            # ExperimentConfig "provisorio" so para acessar o cache certo
            alloc_cfg = ExperimentConfig(data_id, method, ASTAR_HEURISTIC, NO_HEURISTIC)

            mark = @timed ensure_allocation(alloc_cfg, params, do_allocation)
            alloc_result = mark.value.allocations
            allocation_time, allocation_bytes = mark.time, mark.bytes

            for heuristic in instances(RoutingHeuristic), merge in instances(MergeHeuristic)

                cfg = ExperimentConfig(data_id, method, heuristic, merge)

                println(
                    "ID: ", data_id,
                    "\nMethod: ", method,
                    "\nHeuristic: ", heuristic,
                    "\nMerge strategy: ", merge
                )

                run_experiment_with_allocation(cfg, params, mark.value, allocation_time, allocation_bytes)

                print("\033[2J\033[H")
            end
        end
    end
end