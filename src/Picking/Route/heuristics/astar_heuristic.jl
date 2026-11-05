# Heuristic lower bound for the remaining route. A non-terminal state must
# travel to at least one feasible shelf; a terminal state only returns home.
const ASTAR_TOTAL_TIME_LIMIT_NS = UInt64(600_000_000_000)

mutable struct RoutingBudget
    deadline_ns::UInt64
    exhausted::Bool
end

function new_routing_budget(order_count::Int)
    validate_positive(order_count, "order_count")
    allotted_time = max(UInt64(1), ASTAR_TOTAL_TIME_LIMIT_NS ÷ order_count)
    return RoutingBudget(time_ns() + allotted_time, false)
end

function astar_budget_exhausted!(budget::RoutingBudget)
    if budget.exhausted
        return true
    end
    if time_ns() >= budget.deadline_ns
        budget.exhausted = true
        return true
    end
    return false
end

function astar_lookahead(
    current::Int,
    candidates::Vector{Int},
    distance_matrix::Matrix{Float64},
    depot_distance::Vector{Float64}
)
    if isempty(candidates)
        current == 0 && return 0.0
        validate_index_bounds(current, length(depot_distance), "current")
        return depot_distance[current]
    end

    if current != 0
        validate_index_bounds(current, size(distance_matrix, 1), "current")
    end

    if current == 0
        return minimum(depot_distance[node] for node in candidates)
    end

    return minimum(distance_matrix[current, node] for node in candidates)
end

function astar_heap_precedes(left, right)
    return left[1] < right[1] || (left[1] == right[1] && left[2] < right[2])
end

function astar_heap_push!(heap::Vector{Tuple{Float64,Int,Any,Float64}}, entry)
    push!(heap, entry)
    child = length(heap)

    while child > 1
        parent = child ÷ 2
        astar_heap_precedes(heap[parent], heap[child]) && break
        heap[parent], heap[child] = heap[child], heap[parent]
        child = parent
    end

    return nothing
end

function astar_heap_pop!(heap::Vector{Tuple{Float64,Int,Any,Float64}})
    first_entry = heap[1]
    last_entry = pop!(heap)

    if !isempty(heap)
        heap[1] = last_entry
        parent = 1

        while true
            left = 2 * parent
            left > length(heap) && break
            right = left + 1
            child = right <= length(heap) && astar_heap_precedes(heap[right], heap[left]) ?
                right : left
            astar_heap_precedes(heap[parent], heap[child]) && break
            heap[parent], heap[child] = heap[child], heap[parent]
            parent = child
        end
    end

    return first_entry
end

function astar_pick_from_shelf(
    node::Int,
    remaining::Vector{Int},
    remaining_capacity::Float64,
    stock::Matrix{Int},
    skus::Vector{SKU},
    locations::Vector{Location}
)
    location = locations[node]
    candidate_skus = Int[
        sku for sku in eachindex(remaining)
        if remaining[sku] > 0 &&
           stock[location.id, sku] > 0 &&
           skus[sku].volume <= remaining_capacity
    ]
    isempty(candidate_skus) && return nothing

    sort!(candidate_skus, by = sku -> (skus[sku].volume, sku))
    picked = zeros(Int, length(remaining))
    next_remaining = copy(remaining)
    capacity_left = remaining_capacity

    for sku in candidate_skus
        quantity = min(
            next_remaining[sku],
            stock[location.id, sku],
            floor(Int, capacity_left / skus[sku].volume)
        )

        if quantity > 0
            picked[sku] = quantity
            next_remaining[sku] -= quantity
            capacity_left -= quantity * skus[sku].volume
        end
    end

    return any(>(0), picked) ? (picked, next_remaining) : nothing
end

function astar_available_picks(
    state,
    initial_demand::Vector{Int},
    stock::Matrix{Int},
    skus::Vector{SKU},
    locations::Vector{Location},
    picker_capacity::Int
)
    current, visited, remaining_tuple = state
    remaining = collect(remaining_tuple)
    used_capacity = sum(
        (initial_demand[sku] - remaining[sku]) * skus[sku].volume
        for sku in eachindex(remaining)
    )
    remaining_capacity = max(0.0, picker_capacity - used_capacity)
    actions = Tuple{Int,Vector{Int},Vector{Int}}[]

    for node in eachindex(locations)
        (visited & (BigInt(1) << (node - 1))) != 0 && continue

        pickup = astar_pick_from_shelf(
            node, remaining, remaining_capacity, stock, skus, locations
        )
        pickup === nothing && continue
        picked, next_remaining = pickup
        push!(actions, (node, picked, next_remaining))
    end

    return actions
end

function astar_greedy_complete!(
    steps::Vector{Tuple{Int,Vector{Int}}},
    state,
    initial_demand::Vector{Int},
    stock::Matrix{Int},
    skus::Vector{SKU},
    locations::Vector{Location},
    picker_capacity::Int,
    distance_matrix::Matrix{Float64},
    depot_distance::Vector{Float64}
)
    while true
        actions = astar_available_picks(
            state, initial_demand, stock, skus, locations, picker_capacity
        )
        isempty(actions) && return state

        current, visited, _ = state
        next_action_index = argmin(eachindex(actions)) do index
            node = actions[index][1]
            distance = current == 0 ?
                depot_distance[node] : distance_matrix[current, node]
            (distance, node)
        end
        node, picked, next_remaining = actions[next_action_index]
        push!(steps, (node, picked))
        state = (
            node,
            visited | (BigInt(1) << (node - 1)),
            Tuple(next_remaining)
        )
    end
end

function astar_route_order!(
    order::Vector{Int},
    stock::Matrix{Int},
    skus::Vector{SKU},
    warehouse::Warehouse,
    picker_capacity::Int,
    distance_matrix::Matrix{Float64},
    depot_distance::Vector{Float64},
    budget::RoutingBudget
)
    validate_positive(picker_capacity, "picker_capacity")
    locations = warehouse.locations
    n_locations = length(locations)

    size(distance_matrix) == (n_locations, n_locations) ||
        customization_error(
            "A* distance_matrix has size $(size(distance_matrix)); expected ($n_locations, $n_locations)."
        )
    length(depot_distance) == n_locations ||
        customization_error(
            "A* depot_distance has length $(length(depot_distance)); expected $n_locations."
        )
    size(stock) == (n_locations, length(skus)) ||
        customization_error(
            "A* stock has size $(size(stock)); expected ($n_locations, $(length(skus)))."
        )
    all(isfinite, distance_matrix) && all(>=(0), distance_matrix) &&
        all(isfinite, depot_distance) && all(>=(0), depot_distance) ||
        customization_error("A* distances must be finite and non-negative.")

    initial_demand = zeros(Int, length(skus))
    for sku in order
        1 <= sku <= length(skus) ||
            customization_error("A* order references SKU $sku outside 1:$(length(skus)).")
        initial_demand[sku] += 1
    end

    start = (0, BigInt(0), Tuple(initial_demand))
    open = Tuple{Float64,Int,Any,Float64}[]
    sequence = 0
    astar_heap_push!(
        open,
        (astar_lookahead(0, Int[], distance_matrix, depot_distance), sequence, start, 0.0)
    )
    best_cost = Dict{Any,Float64}(start => 0.0)
    parents = Dict{Any,Tuple{Any,Int,Vector{Int}}}()

    max_edge = max(maximum(distance_matrix), maximum(depot_distance))
    unserved_penalty = (n_locations + 1) * max_edge + 1.0
    goal = nothing
    best_state = start
    best_remaining = sum(initial_demand)
    best_cost_so_far = 0.0

    while !isempty(open)
        astar_budget_exhausted!(budget) && break
        _, _, state, queued_cost = astar_heap_pop!(open)
        queued_cost == get(best_cost, state, Inf) || continue
        current_cost = queued_cost
        actions = astar_available_picks(
            state, initial_demand, stock, skus, locations, picker_capacity
        )

        state_remaining = sum(state[3])
        if state_remaining < best_remaining ||
           (state_remaining == best_remaining && current_cost < best_cost_so_far)
            best_state = state
            best_remaining = state_remaining
            best_cost_so_far = current_cost
        end

        if isempty(actions)
            goal = state
            break
        end

        for (node, picked, next_remaining) in actions
            next_state = (
                node,
                state[2] | (BigInt(1) << (node - 1)),
                Tuple(next_remaining)
            )
            step_cost = state[1] == 0 ?
                depot_distance[node] : distance_matrix[state[1], node]
            next_cost = current_cost + step_cost

            if next_cost < get(best_cost, next_state, Inf)
                best_cost[next_state] = next_cost
                parents[next_state] = (state, node, picked)
                next_remaining_count = sum(next_remaining)
                if next_remaining_count < best_remaining ||
                   (next_remaining_count == best_remaining && next_cost < best_cost_so_far)
                    best_state = next_state
                    best_remaining = next_remaining_count
                    best_cost_so_far = next_cost
                end
                sequence += 1
                next_actions = astar_available_picks(
                    next_state, initial_demand, stock, skus, locations, picker_capacity
                )
                estimate = next_cost + astar_lookahead(
                    node,
                    Int[action[1] for action in next_actions],
                    distance_matrix,
                    depot_distance
                )
                if isempty(next_actions)
                    estimate += unserved_penalty * sum(next_remaining)
                end
                astar_heap_push!(open, (estimate, sequence, next_state, next_cost))
            end
        end
    end

    if goal === nothing
        budget.exhausted || error("A* failed to find a terminal picking state.")
        goal = best_state
    end

    steps = Tuple{Int,Vector{Int}}[]
    continuation_state = goal
    state = goal
    while state != start
        previous, node, picked = parents[state]
        push!(steps, (node, picked))
        state = previous
    end
    reverse!(steps)

    if budget.exhausted
        astar_greedy_complete!(
            steps, continuation_state, initial_demand, stock, skus, locations,
            picker_capacity, distance_matrix, depot_distance
        )
    end

    route = [warehouse.depot.id]
    sku_shelf = Vector{Vector{Int}}([[0]])
    distance = Float64[0.0]
    remaining = initial_demand
    current = 0

    for (node, picked) in steps
        location = locations[node]
        picked_skus = Int[]

        for sku in eachindex(picked)
            quantity = picked[sku]
            quantity == 0 && continue
            stock[location.id, sku] -= quantity
            remaining[sku] -= quantity
            append!(picked_skus, fill(sku, quantity))
        end

        segment_distance = current == 0 ?
            depot_distance[node] : distance_matrix[current, node]
        push!(distance, segment_distance)
        push!(route, location.id)
        push!(sku_shelf, picked_skus)
        current = node
    end

    if current != 0
        push!(distance, depot_distance[current])
        push!(route, warehouse.depot.id)
        push!(sku_shelf, [0])
    end

    remaining_order = Int[]
    for sku in eachindex(remaining)
        append!(remaining_order, fill(sku, remaining[sku]))
    end

    picker = Pickers(route, sku_shelf, distance)
    validate_picker(picker)
    return picker, remaining_order
end

function astar_route_order_strategy(
    cfg::ExperimentConfig,
    order::Vector{Int},
    stock::Matrix{Int},
    skus::Vector{SKU},
    warehouse::Warehouse,
    picker_capacity::Int,
    distance_matrix::Matrix{Float64},
    depot_distance::Vector{Float64},
    budget::RoutingBudget
)
    return astar_route_order!(
        order, stock, skus, warehouse, picker_capacity,
        distance_matrix, depot_distance, budget
    )
end
