# src/main.jl

print("\033[2J\033[H")
printstyled("\nIt may take a while to start up; please wait."; color = :blue, bold = true)
println("")

include(joinpath(@__DIR__, "General_functions", "load.jl"))
include(joinpath(@__DIR__, "Warehouse", "load.jl"))
include(joinpath(@__DIR__, "Inventory_sizing", "load.jl"))
include(joinpath(@__DIR__, "Slotting", "load.jl"))
include(joinpath(@__DIR__, "Picking", "load.jl"))

include(joinpath(@__DIR__, "experiment_runner.jl"))

function main()
    validate_project_configuration(params; data_dir=joinpath(@__DIR__, "..", "Data"))
    validate_registered_strategies()

    replace_csv = read_bool("Replace compare.csv")
    replace_csv && clear_compare_csv!()

    mode = read_run_mode()

    if mode == :batch
        do_allocation = read_do_allocation()
        run_batch(params, do_allocation)
    else
        cfg = read_experiment_config(params)
        do_allocation = read_do_allocation()
        run_experiment(cfg, params, do_allocation)
    end

    write_results_csv()

    println("Execution finished. Press Enter to exit and clear the terminal...")
    readline()
    print("\033[2J\033[H")
end

main()