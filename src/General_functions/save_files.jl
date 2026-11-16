# src/General_function/save_files

const COMPARE_CSV_PATH = joinpath(@__DIR__, "..", "..", "compare.csv")
const known_result_rows = Set{Tuple{Vararg{String}}}()
const result_rows_loaded = Ref(false)

result_row_key(row) = Tuple(string(value) for value in row)

function clear_compare_csv!(csv_path::AbstractString = COMPARE_CSV_PATH)
    isfile(csv_path) && rm(csv_path)
    empty!(known_result_rows)
    result_rows_loaded[] = true
    return nothing
end

function append_result_csv!(result::NamedTuple, csv_path::AbstractString = COMPARE_CSV_PATH)
    mkpath(dirname(csv_path))
    new_row = DataFrame([result])

    if !result_rows_loaded[]
        if isfile(csv_path) && filesize(csv_path) > 0
            existing_rows = CSV.read(csv_path, DataFrame)
            names(existing_rows) == names(new_row) ||
                error("compare.csv columns do not match the current experiment results.")
            union!(known_result_rows, (result_row_key(row) for row in eachrow(existing_rows)))
        end
        result_rows_loaded[] = true
    end

    key = result_row_key(only(eachrow(new_row)))
    key in known_result_rows && return nothing

    if !isfile(csv_path) || filesize(csv_path) == 0
        CSV.write(csv_path, new_row)
    else
        CSV.write(csv_path, new_row; append=true, writeheader=false)
    end
    push!(known_result_rows, key)
    return nothing
end

function save_files(
    cfg::ExperimentConfig, data_name::String,
    allocation_time, allocation_bytes, route_time, route_bytes,
    merge_time, merge_bytes, distance, sum_pickers
)
    append_result_csv!((;
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