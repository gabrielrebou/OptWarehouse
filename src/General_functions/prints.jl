# src/General_functions/prints.jl

using Statistics

function allocation_results_dir(cfg::ExperimentConfig)
    folder_name = "$(cfg.data_id)-$(cfg.allocation_method)"
    return joinpath(@__DIR__, "..", "..", "Results", folder_name, "allocation")
end

function allocation_graphs_dir(cfg::ExperimentConfig)
    folder_name = "$(cfg.data_id)-$(cfg.allocation_method)"
    return joinpath(@__DIR__, "..", "..", "Results", folder_name, "graphs")
end

function print_allocation(cfg::ExperimentConfig, warehouse::Warehouse, instance::Instance, cooc::CooccurrenceMatrix, skus::Vector{SKU}, sparse_matrix, S_hat::Matrix, P::Matrix, W::Matrix, S_hat_hat::Matrix, allocations::Matrix, do_message_passing::Bool)
    results_dir = allocation_results_dir(cfg)
    mkpath(results_dir)

    results_path = joinpath(results_dir, "Results.txt")
    open(results_path, "w") do io

        println(io, "SKUs: ", instance.n_skus)
        println(io, "Orders: ", length(instance.orders))
        
        println(io, "\nFirst order:")
        println(io, instance.orders[1])
        
        println(io, "\nLast order:")
        println(io, instance.orders[end])
        println(io, "")

        for i in 1:warehouse.locations[end].id
            println(io, warehouse.locations[i])
        end
        
        # Exibir a matriz de coocorrencia
        println(io, "\nFrequencies: ", cooc.frequency)
        println(io, "\nCo-occurrence matrix:")
        show(io, "text/plain", cooc.matrix)
        println(io, "")
        
        for sku in skus
            println(io, sku)
        end
        
        println(io, "")
        if do_message_passing
            println(io, "Matrix ranges:")
            println(io, "S_hat: ", extrema(S_hat))
            println(io, "S_hat * P: ", extrema(S_hat * P))
            println(io, "W * S_hat: ", extrema(W * S_hat))
            println(io, "W * S_hat * P: ", extrema(W * S_hat * P))
            println(io, "correlation{S_hat, S_hat_hat} = ", cor(vec(S_hat), vec(S_hat_hat)))
            println(io, "")
        end

        for loc in warehouse.locations
            if sum(allocations[loc.id, :]) > 0
                println(io, "Location $(loc.id) (Aisle $(loc.aisle), Shelf $(loc.shelf))")
                
                for sku in axes(allocations, 2)
                    if allocations[loc.id, sku] > 0
                        println(io, "   SKU $sku -> $(allocations[loc.id, sku])")
                    end
                end
                
                println(io)
            end
        end
        
    end
    
    println("Results saved to: ", results_path)
end

function print_pickers(
    cfg::ExperimentConfig,
    pickers_route::Vector{Pickers},
    data_name::String,
    distance::Float64,
    sum_pickers::Int
)
    folder_name = "$(cfg.data_id)-$(cfg.allocation_method)-$(cfg.routing_heuristic)-$(cfg.merge_strategy)"
    results_dir = joinpath(@__DIR__, "..", "..", "Results", folder_name, "picker")
    mkpath(results_dir)
    results_path = joinpath(results_dir, "Results.txt")

    open(results_path, "w") do io
        for (i, picker) in enumerate(pickers_route)
            println(io, "Picker route ", i, ": ", picker.picker_rout)
        end
        println(io, "")
        println(io, "Test case: ", data_name)
        println(io, "")
        println(io, "Total distance: ", distance)
        println(io, "Number of pickers: ", sum_pickers)
    end
end