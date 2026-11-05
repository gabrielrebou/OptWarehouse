# src/General_functions/graphs.jl

using Graphs
using Plots

function warehouse_graph(cfg::ExperimentConfig, warehouse::Warehouse)
    # Criar o grafo baseado no número de localizações + depósito
    n_nos = length(warehouse.locations) + 1
    g = SimpleGraph(n_nos)

    # Mapear coordenadas (shelf = X, aisle = Y)
    x = Float64[]
    y = Float64[]
    labels = String[]

    # Adiciona o depósito primeiro
    push!(x, warehouse.depot.shelf)
    push!(y, warehouse.depot.aisle)
    push!(labels, "Depot")
    
    # Adiciona as localizações
    for (i, loc) in enumerate(warehouse.locations)
        push!(x, loc.shelf)
        push!(y, loc.aisle)
        push!(labels, "$(loc.capacity)")
    end
    # Plotando os nós
    plt = plot(
        xlabel="Shelf", 
        ylabel="Aisle",
        title="Warehouse Layout",
        grid=false,
        legend=:best,
    )
    for i in 1:warehouse.locations[end].aisle
        plot!([-warehouse.locations[end].shelf, warehouse.locations[end].shelf], [i, i], 
        label="", 
        color=:black, 
        linewidth=2
        )
    end

    plot!([0, 0], [0,warehouse.locations[end].aisle], 
        label="", 
        color=:black, 
        linewidth=4,
    )
    
    scatter!(x, y, 
        label="Shelves",
        markersize=8, 
        markercolor=:gray,
        shape =:square
    )

    scatter!([x[1]], [y[1]], label="Depot", markersize=12, markercolor=:black, shape=:square)
    for i in eachindex(x)
        annotate!(x[i], y[i] - 0.3, text(labels[i], 8, :center))
    end

    results_dir = allocation_graphs_dir(cfg)
    mkpath(results_dir)
    savefig(plt, joinpath(results_dir, "warehouse_graph.png"))
    end

function heatmap_main(cfg::ExperimentConfig, matriz::Matrix, title::String)

    num_linhas, num_colunas = size(matriz)

    plt = heatmap(matriz,
        title=title,
        color=:viridis,
        aspect_ratio=:equal,
        yflip=true,
        
        xlims = (0.5, num_colunas + 0.5), # Define o limite exato do início ao fim das colunas
        xticks = [1;5:5:num_colunas],           # Força os rótulos a irem exatamente de 1 até o número de colunas
        ylims = (0.5, num_linhas + 0.5),  # Opcional: ajusta também o limite vertical
        yticks = [1;5:5:num_linhas]             # Opcional: força marcadores de 1 até o número de linhas
    )

    results_dir = allocation_graphs_dir(cfg)
    mkpath(results_dir)

    filename = replace(title, " " => "_")
    filename = replace(filename, r"[^\w\-]" => "")

    savefig(plt, joinpath(results_dir, "heatmap_$(filename).png"))

end

function plot_allocation(cfg::ExperimentConfig, x, warehouse)
    
    locations = warehouse.locations
    
    p = plot(
        aspect_ratio = :equal,
        legend = false,
        axis = false,
        grid = false,
        size = (900,700)
    )

    for i in 1:warehouse.locations[end].aisle
        plot!([-warehouse.locations[end].shelf, warehouse.locations[end].shelf], [i, i], 
        label="", 
        color=:black, 
        linewidth=2
        )
    end
    
    palette = cgrad(:tab20, max(size(x,2), 2))
    
    plot!([0, 0], [0,warehouse.locations[end].aisle], 
    label="", 
    color=:black, 
    linewidth=4,
    )
    
    for loc in locations
        scatter!(
            [loc.shelf],
            [loc.aisle],
            marker = :rect,
            markersize = 18,
            markercolor = :white,
            markerstrokecolor = :black
            )
    end

    for loc in locations
        
        q = x[loc.id, :]
        
        maximum(q) == 0 && continue
        
        sku = argmax(q)
        
        scatter!(
            [loc.shelf],
            [loc.aisle],
            marker = :rect,
            markersize = 18,
            markercolor = palette[(sku-1)/(size(x,2)-1)],
            markerstrokecolor = :black
            )
            
            annotate!(
                loc.shelf,
                loc.aisle,
                text(string(sku), 7, :black)
                )
    end
    
    scatter!(
        [warehouse.depot.shelf],
        [warehouse.depot.aisle],
        marker = :rect,
        markersize = 18,
        markercolor = :black,
        markerstrokecolor = :black
        )
        annotate!(
            warehouse.depot.shelf,
            warehouse.depot.aisle,
            text("Depot", 7, :white)
            )

    results_dir = allocation_graphs_dir(cfg)
    mkpath(results_dir)
    savefig(p, joinpath(results_dir, "allocation.png"))

end