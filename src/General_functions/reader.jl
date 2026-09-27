# src/General_functions/reader.jl

function read_instance(filename)

    isfile(filename) ||
        customization_error("Dataset '$filename' does not exist or is not a regular file.")
    lines = readlines(filename)

    length(lines) >= 4 ||
        customization_error("Dataset '$filename' has $(length(lines)) lines; at least 4 header lines are required.")

    parse_dataset_integer(value, line_number, filename) = begin
        parsed = tryparse(Int, strip(value))
        parsed === nothing &&
            customization_error("Dataset '$filename' line $line_number must contain an integer; received '$value'.")
        parsed
    end

    n_skus = parse_dataset_integer(lines[3], 3, filename)
    n_orders = parse_dataset_integer(lines[4], 4, filename)

    orders = Order[]

    for i in 1:n_orders
        line_number = 5 + i
        line_number <= length(lines) ||
            customization_error("Dataset '$filename' declares $n_orders orders but is missing the order on line $line_number.")
        skus = parse_dataset_integer.(split(strip(lines[line_number])), line_number, filename)
        push!(orders, Order(i, skus))
    end

    return Instance(
        n_skus,
        orders
    )

end

function read_bool(prompt::String)::Bool
    print(prompt, " (y/n): ")
    while true
        input = lowercase(strip(readline()))
        input == "" && continue
        input == "y" && return true
        input == "n" && return false
        println("Invalid input. Please enter 'y' for yes or 'n' for no.")
    end
end

function read_int_range(prompt::String, max_val::Int, min_val::Int)::Int
    print(prompt, " ($min_val to $max_val): ")
    while true
        input = strip(readline())
        val = input == "" ? nothing : tryparse(Int, input)
        if val !== nothing && min_val <= val <= max_val
            return val
        end
        println("Invalid input. Enter an integer between $min_val and $max_val.")
    end
end

function read_enum_choice(prompt::String, ::Type{E}) where {E <: Enum}
    options = instances(E)

    println(prompt)
    for (i, opt) in enumerate(options)
        println("  $i) $opt")
    end

    idx = read_int_range("choose", length(options),1)
    return options[idx]
end

function read_data_id(params::Params)::Int
    return read_int_range("Choose data ID", length(params.data_names),1)
end

function read_experiment_config(params::Params)::ExperimentConfig
    data_id = read_data_id(params)
    allocation_method = read_enum_choice("Allocation method:", AllocationMethod)
    routing_heuristic = read_enum_choice("Routing heuristic:", RoutingHeuristic)
    merge_strategy = read_enum_choice("Merge strategy:", MergeHeuristic)

    return ExperimentConfig(data_id, allocation_method, routing_heuristic, merge_strategy)
end

function read_run_mode()::Symbol
    println("run mode:")
    println("  1) Run an isolated case")
    println("  2) Run more than one case (loop)")

    choice = read_int_range("Choice", 2, 1)
    return choice == 1 ? :single : :batch
end

function read_do_allocation()::Bool
    return read_bool("Execute the allocation step (if 'n', reuse the saved file, if it exists)")
end