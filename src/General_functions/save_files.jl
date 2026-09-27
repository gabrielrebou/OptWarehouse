# src/General_function/save_files

# Resultados: acumula em memória e escreve o CSV uma única vez no final
const results_rows = NamedTuple[]
const COMPARE_CSV_PATH = joinpath(@__DIR__, "..", "..", "compare.csv")

function clear_compare_csv!(csv_path::AbstractString = COMPARE_CSV_PATH)
    isfile(csv_path) && rm(csv_path)
    return nothing
end

function save_files(
    cfg::ExperimentConfig, data_name::String,
    allocation_time, allocation_bytes, route_time, route_bytes,
    merge_time, merge_bytes, distance, sum_pickers
)
    push!(results_rows, (;
        data_id = cfg.data_id,
        data_name = data_name,
        #distance_method = cfg.distance_method,
        #shape_method = cfg.allocation_method,
        allocation_method = cfg.allocation_method,
        routing_heuristic = cfg.routing_heuristic,
        merge_strategy = cfg.merge_strategy,
        allocation_time, allocation_bytes,
        route_time, route_bytes,
        merge_time, merge_bytes,
        distance, sum_pickers
    ))
end

function write_results_csv(csv_path::AbstractString = COMPARE_CSV_PATH)
    mkpath(dirname(csv_path))

    isempty(results_rows) && return

    new_rows = DataFrame(results_rows)

    if !isfile(csv_path) || filesize(csv_path) == 0
        CSV.write(csv_path, new_rows)
        return
    end

    existing_rows = CSV.read(csv_path, DataFrame)
    names(existing_rows) == names(new_rows) ||
        error("compare.csv columns do not match the current experiment results.")

    row_key(row) = Tuple(string(value) for value in row)
    known_rows = Set(row_key(row) for row in eachrow(existing_rows))
    rows_to_append = Int[]

    for (index, row) in enumerate(eachrow(new_rows))
        key = row_key(row)
        if !(key in known_rows)
            push!(rows_to_append, index)
            push!(known_rows, key)
        end
    end

    isempty(rows_to_append) && return
    CSV.write(csv_path, new_rows[rows_to_append, :]; append=true, writeheader=false)
end