# src/Picking/validation.jl


# Funcoes de validacao reutilizaveis por Route/ e Merge/. Cada uma
# lanca ArgumentError (ou ErrorException, quando a inconsistencia so
# pode ser detectada apos calcular um resultado) com uma mensagem
# especifica, para que os modulos que as usam continuem
# independentes: nao precisam saber a razao da falha, so que ela
# ocorreu.

function validate_positive(value::Real, name::AbstractString)
    if value <= 0
        customization_error("$name must be positive; received: $value.")
    end
end

function validate_non_negative(value::Real, name::AbstractString)
    if value < 0
        customization_error("$name must be non-negative; received: $value.")
    end
end

function validate_same_length(a, b, name_a::AbstractString, name_b::AbstractString)
    if length(a) != length(b)
        customization_error(
            "$name_a (length $(length(a))) and $name_b (length $(length(b))) must have the same length"
        )
    end
end

function validate_route_endpoints(route::Vector{Int}, depot_id::Int)
    if isempty(route)
        customization_error("Route cannot be empty.")
    end

    if route[1] != depot_id || route[end] != depot_id
        customization_error(
            "Route must start and end at the depot (ID=$depot_id); received: $(route[1])..$(route[end])"
        )
    end
end

# Checa consistencia estrutural de um Pickers: os tres vetores
# (rota, skus por prateleira, distancia) precisam ter o mesmo
# tamanho, e nenhuma distancia pode ser negativa.
function validate_picker(picker::Pickers; depot_id::Int = 0)
    validate_same_length(picker.picker_rout, picker.sku_shelf, "picker_rout", "sku_shelf")
    validate_same_length(picker.picker_rout, picker.distance, "picker_rout", "distance")
    validate_route_endpoints(picker.picker_rout, depot_id)

    for d in picker.distance
        validate_non_negative(d, "distance")
    end
end

function validate_capacity(load::Real, capacity::Real; context::AbstractString = "")
    if load > capacity
        label = isempty(context) ? "" : " ($context)"
        customization_error("Load $load exceeds capacity $capacity$label.")
    end
end

function validate_index_bounds(index::Int, limit::Int, name::AbstractString)
    if index < 1 || index > limit
        customization_error("$name out of bounds: $index (expected between 1 and $limit).")
    end
end
