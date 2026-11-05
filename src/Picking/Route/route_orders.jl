# src/Picking/Route/route_orders.jl


# Orquestracao do roteamento em si: monta a rota de um pedido
# (route_order!) e distribui um conjunto de pedidos entre pickers
# (route_orders). Nao sabe qual heuristica esta em uso -- isso e
# responsabilidade de selector.jl.

using Dates

function route_order!(
    cfg::ExperimentConfig,
    order::Vector{Int},
    stock::Matrix{Int},
    skus::Vector{SKU},
    warehouse::Warehouse,
    picker_capacity::Int,
    distance_matrix::Matrix{Float64};
    budget::RoutingBudget = new_routing_budget(1)
)
    validate_positive(picker_capacity, "picker_capacity")
    depot_distance = compute_depot_distance(cfg, warehouse)
    return route_order_selector(
        cfg.routing_heuristic, cfg, order, stock, skus, warehouse,
        picker_capacity, distance_matrix, depot_distance, budget
    )
end

function greedy_route_order!(
    cfg::ExperimentConfig,
    order::Vector{Int},
    stock::Matrix{Int},
    skus::Vector{SKU},
    warehouse::Warehouse,
    picker_capacity::Int,
    distance_matrix::Matrix{Float64},
    depot_distance::Vector{Float64},
    ::RoutingBudget
)
    depot = warehouse.depot
    locations = warehouse.locations
    n_locations = length(locations)

    demand = Dict{Int,Int}()

    for sku in order
        demand[sku] = get(demand, sku, 0) + 1
    end

    route = [depot.id]
    sku_shelf = Vector{Vector{Int}}()
    push!(sku_shelf, [0])          # deposito no inicio, sem skus
    distance = Float64[0.0]        # nenhuma distancia percorrida ainda

    current = 0
    used_capacity = 0.0

    while !isempty(demand)

        remaining_capacity = picker_capacity - used_capacity

        if remaining_capacity <= 0
            break
        end

        candidates = Int[]

        for location_index in 1:n_locations

            location = locations[location_index]

            for sku in keys(demand)

                if demand[sku] <= 0
                    continue
                end

                if stock[location.id, sku] <= 0
                    continue
                end

                if skus[sku].volume > remaining_capacity
                    continue
                end

                push!(candidates, location_index)
                break
            end
        end

        if isempty(candidates)
            println("Aviso: estoque insuficiente para atender o pedido.")
            break
        end

        next = nearest_next_shelf(current, candidates, distance_matrix, depot_distance)

        if next === nothing
            break
        end

        location = locations[next]

        capacity_left = remaining_capacity
        collected = false

        candidate_skus = Int[]

        for sku in keys(demand)

            if demand[sku] > 0 &&
               stock[location.id, sku] > 0 &&
               skus[sku].volume <= capacity_left

                push!(candidate_skus, sku)
            end
        end

        sort!(candidate_skus, by = sku -> skus[sku].volume)

        picked_skus = Int[]

        for sku in candidate_skus

            quantity = min(
                demand[sku],
                stock[location.id, sku],
                floor(Int, capacity_left / skus[sku].volume)
            )

            if quantity > 0

                collected = true

                stock[location.id, sku] -= quantity
                demand[sku] -= quantity

                used_capacity += quantity * skus[sku].volume
                capacity_left -= quantity * skus[sku].volume

                # registra cada unidade retirada dessa prateleira
                append!(picked_skus, fill(sku, quantity))
            end
        end

        if !collected
            filter!(x -> x != next, candidates)
            continue
        end

        segment_distance = current == 0 ?
            depot_distance[next] : distance_matrix[current, next]
        push!(distance, segment_distance)
        push!(route, location.id)
        push!(sku_shelf, picked_skus)

        current = next

        for sku in collect(keys(demand))
            if demand[sku] <= 0
                delete!(demand, sku)
            end
        end
    end

    if current != 0
        push!(distance, depot_distance[current])
        push!(route, depot.id)
        push!(sku_shelf, [0])
    end

    remaining_order = Int[]

    for (sku, quantity) in demand
        for _ in 1:quantity
            push!(remaining_order, sku)
        end
    end

    picker = Pickers(route, sku_shelf, distance)

    validate_picker(picker; depot_id=depot.id)

    return picker, remaining_order
end


function route_orders(
    cfg::ExperimentConfig,
    instances::Instance,
    allocations::Matrix{Int},
    skus::Vector{SKU},
    picker_capacity::Int,
    warehouse::Warehouse,
    distance_matrix::Matrix{Float64}
)
    validate_positive(picker_capacity, "picker_capacity")

    if cfg.routing_heuristic == ASTAR_HEURISTIC
        println("A* routing started at ", Dates.format(Dates.now(), "yyyy-mm-dd HH:MM:SS"))
    end

    remaining_stock = copy(allocations)

    # cada pedido pode precisar de varios pickers, entao guardamos
    # um Vector{Pickers} por pedido
    results = Vector{Vector{Pickers}}(undef, length(instances.orders))

    # TODO: atualmente os pedidos sao processados sequencialmente.
    # Rever outras estrategias de distribuicao do estoque entre
    # pedidos depois.

    order_count = length(instances.orders)
    for (i, order) in enumerate(instances.orders)
        budget = new_routing_budget(order_count)

        remaining_order = copy(order.skus)
        pickers_for_order = Pickers[]

        while !isempty(remaining_order)
            use_greedy_fallback = cfg.routing_heuristic == ASTAR_HEURISTIC && budget.exhausted
            route_cfg = use_greedy_fallback ?
                ExperimentConfig(cfg.data_id, cfg.allocation_method, GREEDY, cfg.merge_strategy) :
                cfg
            picker, remaining_order = route_order!(
                route_cfg, remaining_order, remaining_stock, skus,
                warehouse, picker_capacity, distance_matrix;
                budget
            )

            picked_count = count(!=(0), Iterators.flatten(picker.sku_shelf))
            if picked_count <= 0
                if budget.exhausted && !use_greedy_fallback
                    continue
                end
                customization_error(
                    "Could not fulfill order $i: no feasible picker route remains for " *
                    "$(length(remaining_order)) requested units. Check allocated stock and SKU volumes."
                )
            end

            push!(pickers_for_order, picker)
        end

        if budget.exhausted && cfg.routing_heuristic == ASTAR_HEURISTIC
            @warn "A* time budget reached for order $i; completed the current route greedily from the last A* shelf. " *
                  "Any demand left due to picker capacity will use additional routes from the depot."
        end

        results[i] = pickers_for_order
    end

    return results
end
