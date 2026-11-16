# Gera um relatorio textual e graficos a partir do compare.csv.

import Pkg

const PROJECT_DIR = normpath(joinpath(@__DIR__, ".."))

if Base.active_project() != joinpath(PROJECT_DIR, "Project.toml")
    Pkg.activate(PROJECT_DIR; io=devnull)
end

using CSV
using DataFrames
using Plots
using StatsPlots
using Statistics
using Printf


if !isdefined(@__MODULE__, :MergeHeuristic)
    include(joinpath(@__DIR__, "General_functions", "types.jl"))
end

gr()
const COMPARE_CSV_PATH = joinpath(@__DIR__, "..", "compare.csv")
const REPORT_TXT_PATH  = joinpath(@__DIR__, "..", "compare.txt")
const GRAFICOS_DIR     = joinpath(@__DIR__, "..", "Graficos_comparacao")

function ensure_output_dirs()
    hist_dir = joinpath(GRAFICOS_DIR, "Histogramas")
    box_dir  = joinpath(GRAFICOS_DIR, "Boxplots")
    perf_dir = joinpath(GRAFICOS_DIR, "Performance_profile")

    mkpath(hist_dir)
    mkpath(box_dir)
    mkpath(perf_dir)

    return (histogramas = hist_dir, boxplots = box_dir, performance = perf_dir)
end

function load_compare_data(path::AbstractString = COMPARE_CSV_PATH)
    if !isfile(path)
        error("compare.csv file not found at: $path")
    end

    df = CSV.read(path, DataFrame)
    required_columns = [
        :data_id, :data_name, :allocation_method, :routing_heuristic, :merge_strategy,
        :allocation_time, :allocation_bytes, :route_time, :route_bytes,
        :merge_time, :merge_bytes, :distance, :sum_pickers,
    ]
    missing_columns = setdiff(required_columns, Symbol.(names(df)))
    isempty(missing_columns) || error(
        "compare.csv is missing columns from the current experiment output: " *
        join(string.(missing_columns), ", ")
    )

    for (column, enum_type) in (
        (:allocation_method, AllocationMethod),
        (:routing_heuristic, RoutingHeuristic),
        (:merge_strategy, MergeHeuristic),
    )
        valid_values = string.(instances(enum_type))
        values = string.(df[!, column])
        unknown_values = setdiff(unique(values), valid_values)
        isempty(unknown_values) || error(
            "Unknown values in $(column), not registered in General_functions/types.jl: " *
            join(unknown_values, ", ")
        )
        df[!, column] = values
    end

    return df
end

function abbreviate(s::AbstractString; maxlen::Int = 4)
    parts = split(s, "_")
    abbr_parts = [length(p) > maxlen ? p[1:maxlen] : p for p in parts]
    return join(abbr_parts, "_")
end

function add_ratio_columns!(df::DataFrame)
    transform!(
        groupby(df, [:data_id, :merge_strategy]),
        :distance    => (x -> x ./ minimum(x)) => :distance_ratio,
        :sum_pickers => (x -> x ./ minimum(x)) => :pickers_ratio,
    )
    return df
end

function split_merge_groups(df::DataFrame)
    configured = string.(instances(MergeHeuristic))
    present = Set(df.merge_strategy)
    return [
        (slug = _safe_filename(value), label = value,
         df = filter(row -> row.merge_strategy == value, df))
        for value in configured if value in present
    ]
end

_safe_filename(s::AbstractString) = replace(s, r"[^A-Za-z0-9_\-]" => "_")

fmt_value(x::AbstractFloat) = isnan(x) ? "n/a" : isinf(x) ? "infinito" : @sprintf("%.3f", x)
fmt_value(x::Integer) = string(x)
fmt_value(::Missing) = "n/a"
fmt_value(x) = string(x)

const COLUMN_LABELS = Dict(
    "data_id" => "ID",
    "data_name" => "Instância",
    "allocation_method" => "Alocação",
    "routing_heuristic" => "Roteamento",
    "merge_strategy" => "Merge",
    "distance" => "Distância",
    "sum_pickers" => "Pickers",
    "allocation_time" => "Tempo alocacao (s)",
    "route_time" => "Tempo rota (s)",
    "merge_time" => "Tempo merge (s)",
    "distance_ratio" => "Razão distância",
    "pickers_ratio" => "Razão pickers",
    "mean" => "Media",
    "median" => "Mediana",
    "std_dev" => "Desvio padrão",
    "min" => "Minimo",
    "max" => "Maximo",
    "n_instances" => "Instancias",
    "runs" => "Execucoes",
)

function print_table(io::IO, df::DataFrame)
    if isempty(df)
        println(io, "Sem dados.")
        return
    end

    cols = names(df)
    str_cols = Dict(c => [fmt_value(df[i, c]) for i in 1:nrow(df)] for c in cols)
    widths = Dict(c => max(length(c), maximum(length.(str_cols[c]); init = 0)) for c in cols)

    headers = Dict(c => get(COLUMN_LABELS, c, c) for c in cols)
    widths = Dict(c => max(widths[c], length(headers[c])) for c in cols)
    header = join([rpad(headers[c], widths[c]) for c in cols], " | ")
    println(io, header)
    println(io, "-"^length(header))

    for i in 1:nrow(df)
        println(io, join([rpad(str_cols[c][i], widths[c]) for c in cols], " | "))
    end
end

function aggregate_config_results(df::DataFrame)
    group_columns = [
        :data_id, :data_name, :allocation_method, :routing_heuristic, :merge_strategy,
    ]
    return combine(
        groupby(df, group_columns),
        :allocation_time => mean => :allocation_time,
        :route_time => mean => :route_time,
        :merge_time => mean => :merge_time,
        :distance => mean => :distance,
        :sum_pickers => mean => :sum_pickers,
        nrow => :runs,
    )
end

function valid_result(row)
    for metric in (row.distance, row.sum_pickers)
        if ismissing(metric) || !(metric isa Real) || !isfinite(metric) || metric <= 0
            return false
        end
    end
    return true
end

function invalid_result_reason(row)
    reasons = String[]
    for (label, metric) in (("distancia", row.distance), ("pickers", row.sum_pickers))
        if ismissing(metric)
            push!(reasons, "$label ausente")
        elseif !(metric isa Real) || !isfinite(metric)
            push!(reasons, "$label invalida")
        elseif metric <= 0
            push!(reasons, "$label nao positiva")
        end
    end
    return join(reasons, "; ")
end

function print_summary_table(
    io::IO,
    df::DataFrame,
    group_cols::Vector{Symbol},
    value_col::Symbol,
    title_str::AbstractString,
)
    println(io, "\n$title_str")

    if isempty(df)
        println(io, "Sem dados.")
        return
    end

    summary = combine(
        groupby(df, group_cols),
        value_col => mean => :mean,
        value_col => median => :median,
        value_col => std => :std_dev,
        value_col => minimum => :min,
        value_col => maximum => :max,
        nrow => :n_instances,
        :runs => sum => :runs,
    )
    sort!(summary, :mean)

    print_table(io, summary)
end

function print_ranking(io::IO, df::DataFrame, ratio_col::Symbol, title_str::AbstractString)
    println(io, "\nRanking por $title_str (menor razao media e melhor)")

    summary = combine(
        groupby(df, [:allocation_method, :routing_heuristic]),
        ratio_col => mean => :mean_ratio,
        nrow => :n_instances,
        :runs => sum => :runs,
    )
    sort!(summary, :mean_ratio)

    rename!(summary, :mean_ratio => :mean)
    print_table(io, summary)
end

function write_analysis_report(io::IO, source_path::AbstractString, all_rows::DataFrame)
    valid_rows = filter(valid_result, all_rows)
    invalid_rows = filter(row -> !valid_result(row), all_rows)

    println(io, "Relatório de comparação")
    println(io, "CSV: ", abspath(source_path))
    println(io, "Registros: $(nrow(all_rows)); válidos: $(nrow(valid_rows)); excluídos: $(nrow(invalid_rows))")
    println(io, "Distância é a soma dos percursos; pickers é a quantidade de rotas.")
    println(io, "As estatísticas são descritivas; não incluem testes de significância.")

    if !isempty(invalid_rows)
        println(io, "\nRegistros excluidos")
        invalid_table = DataFrame(
            id = invalid_rows.data_id,
            allocation_method = invalid_rows.allocation_method,
            routing_heuristic = invalid_rows.routing_heuristic,
            merge_strategy = invalid_rows.merge_strategy,
            motivo = [invalid_result_reason(row) for row in eachrow(invalid_rows)],
        )
        print_table(io, invalid_table)
    end

    if isempty(valid_rows)
        println(io, "\nNenhum registro válido para análise.")
        return DataFrame()
    end

    results = add_ratio_columns!(aggregate_config_results(valid_rows))
    if isempty(results)
        println(io, "\nNenhum registro válido para análise.")
        return results
    end

    println(io, "\nResultados por instância")
    println(io, "As médias por configuração agrupam execuções repetidas; cada instância tem o mesmo peso nas médias gerais.")
    columns = [
        :allocation_method, :routing_heuristic, :merge_strategy,
        :distance, :sum_pickers, :allocation_time, :route_time, :merge_time,
    ]
    for data_id in sort(unique(valid_rows.data_id))
        instance_rows = filter(row -> row.data_id == data_id, valid_rows)
        println(io, "\nID $(data_id) - $(first(instance_rows.data_name))")
        print_table(io, select(sort(instance_rows, :distance), columns))
    end

    for group in split_merge_groups(results)
        println(io, "\nMerge: $(group.label)")
        print_summary_table(
            io, group.df, [:allocation_method, :routing_heuristic], :distance,
            "Distancia total (unidades do modelo)",
        )
        print_summary_table(
            io, group.df, [:allocation_method, :routing_heuristic], :sum_pickers,
            "Quantidade de pickers",
        )
        println(io, "\nRazão relativa ao melhor resultado da mesma instância e merge (1,0 = melhor)")
        print_summary_table(
            io, group.df, [:allocation_method, :routing_heuristic], :distance_ratio,
            "Distancia relativa",
        )
        print_summary_table(
            io, group.df, [:allocation_method, :routing_heuristic], :pickers_ratio,
            "Pickers relativos",
        )
        print_ranking(io, group.df, :distance_ratio, "distancia")
        print_ranking(io, group.df, :pickers_ratio, "pickers")
    end

    return results
end

function plot_grouped_histogram(
    df::DataFrame,
    value_col::Symbol,
    group_col::Symbol,
    title_str::AbstractString,
    filename::AbstractString,
    output_dir::AbstractString;
    xlabel_str::AbstractString = string(value_col),
    bins::Int = 12,
)
    if isempty(df)
        return nothing
    end

    grupos = sort(unique(df[!, group_col]))

    p = plot(
        title = title_str,
        xlabel = xlabel_str,
        ylabel = "Frequência",
        legend = :outertopright,
        legendfontsize = 7,
        titlefontsize = 10,
        size = (800, 500),
    )

    for g in grupos
        vals = df[df[!, group_col] .== g, value_col]
        isempty(vals) && continue
        histogram!(p, vals; label = abbreviate(string(g)), alpha = 0.55, bins = bins)
    end

    savefig(p, joinpath(output_dir, filename))
    return p
end

function gerar_histogramas(df::DataFrame, hist_dir::AbstractString)
    for grupo in split_merge_groups(df)
        plot_grouped_histogram(
            grupo.df, :distance, :allocation_method,
                "Distancia total - $(grupo.label)",
            "hist_distance_$(_safe_filename(grupo.slug))_raw.png",
            hist_dir;
                xlabel_str = "Distancia",
        )

        plot_grouped_histogram(
            grupo.df, :sum_pickers, :allocation_method,
              "Quantidade de pickers - $(grupo.label)",
            "hist_picker_count_$(_safe_filename(grupo.slug))_raw.png",
            hist_dir;
              xlabel_str = "Pickers",
        )

        plot_grouped_histogram(
            grupo.df, :distance_ratio, :allocation_method,
              "Razao de distancia - $(grupo.label)",
            "hist_distance_$(_safe_filename(grupo.slug))_ratio.png",
            hist_dir;
              xlabel_str = "Distancia / melhor distancia da instancia",
        )

        plot_grouped_histogram(
            grupo.df, :pickers_ratio, :allocation_method,
                "Razao de pickers - $(grupo.label)",
            "hist_picker_count_$(_safe_filename(grupo.slug))_ratio.png",
            hist_dir;
                xlabel_str = "Pickers / menor quantidade da instancia",
        )
    end
end

function plot_boxplot_faceted(
    df::DataFrame,
    value_col::Symbol,
    x_col::Symbol,
    facet_col::Symbol,
    title_str::AbstractString,
    filename::AbstractString,
    output_dir::AbstractString;
    ylabel_str::AbstractString = string(value_col),
)
    if isempty(df)
        return nothing
    end

    cores = [
        "#0072B2",
        "#E69F00",
        "#009E73",
        "#CC79A7",
        "#56B4E9",
        "#F0E442",
        "#D55E00",
        "#000000",
    ]

    facetas = sort(unique(df[!, facet_col]))
    categorias = sort(unique(string.(df[!, x_col])))

    cor_por_categoria = Dict(
        categoria => cores[mod1(i, length(cores))]
        for (i, categoria) in enumerate(categorias)
    )

    subplots = Plots.Plot[]

    for f in facetas
        sub = df[df[!, facet_col] .== f, :]

        p = plot(
            title = abbreviate(string(f)),
            ylabel = ylabel_str,
            legend = false,
            titlefontsize = 9,
            guidefontsize = 8,
        )

        for categoria in categorias
            dados = sub[string.(sub[!, x_col]) .== categoria, value_col]
            isempty(dados) && continue

            boxplot!(
                p,
                [abbreviate(categoria)],
                dados;
                fillcolor = cor_por_categoria[categoria],
                linecolor = :black,
                markercolor = :black,
            )
        end

        push!(subplots, p)
    end

    layout_final = plot(
        subplots...;
        layout = (1, length(subplots)),
        plot_title = title_str,
        plot_titlefontsize = 11,
        size = (420 * length(subplots), 480),
    )

    filename = replace(filename, r"[^A-Za-z0-9_.-]" => "_")
    mkpath(output_dir)
    caminho = joinpath(output_dir, filename)

    savefig(layout_final, caminho)
    return caminho
end


function gerar_boxplots(df::DataFrame, box_dir::AbstractString)
    for grupo in split_merge_groups(df)
        plot_boxplot_faceted(
            grupo.df, :distance, :allocation_method, :routing_heuristic,
            "Distance (raw) — $(grupo.label)",
            "boxplot_distance_$(_safe_filename(grupo.slug))_raw.png",
            box_dir;
            ylabel_str = "Distance",
        )

        plot_boxplot_faceted(
            grupo.df, :sum_pickers, :allocation_method, :routing_heuristic,
            "Picker count (raw) — $(grupo.label)",
            "boxplot_picker_count_$(_safe_filename(grupo.slug))_raw.png",
            box_dir;
            ylabel_str = "Picker count",
        )

        plot_boxplot_faceted(
            grupo.df, :distance_ratio, :allocation_method, :routing_heuristic,
            "Distance (ratio vs. best) — $(grupo.label)",
            "boxplot_distance_$(_safe_filename(grupo.slug))_ratio.png",
            box_dir;
            ylabel_str = "Distance / best for the instance",
        )

        plot_boxplot_faceted(
            grupo.df, :pickers_ratio, :allocation_method, :routing_heuristic,
            "Picker count (ratio vs. best) — $(grupo.label)",
            "boxplot_picker_count_$(_safe_filename(grupo.slug))_ratio.png",
            box_dir;
            ylabel_str = "Picker count / best for the instance",
        )
    end
end

function performance_profile(
    df::DataFrame,
    metric_col::Symbol,
    solver_col::Symbol,
    problem_col::Symbol,
    title_str::AbstractString,
    filename::AbstractString,
    output_dir::AbstractString;
    lower_is_better::Bool = true,
)
    if isempty(df)
        return nothing
    end

    solvers  = sort(unique(df[!, solver_col]))
    problems = unique(df[!, problem_col])

    perf = Dict{Any, Dict{Any, Float64}}()
    for row in eachrow(df)
        p = row[problem_col]
        s = row[solver_col]
        d = get!(perf, p, Dict{Any, Float64}())
        d[s] = float(row[metric_col])
    end

    ratios = Dict{Any, Vector{Float64}}(s => Float64[] for s in solvers)

    for p in problems
        vals = perf[p]
        isempty(vals) && continue

        best = lower_is_better ? minimum(values(vals)) : maximum(values(vals))

        for s in solvers
            if haskey(vals, s)
                v = vals[s]
                r = if lower_is_better
                    best == 0 ? 1.0 : v / best
                else
                    v == 0 ? 1.0 : best / v
                end
                push!(ratios[s], r)
            else
                push!(ratios[s], Inf)
            end
        end
    end

    n_problems = length(problems)
    if n_problems == 0
        return nothing
    end

    finite_ratios = vcat([filter(isfinite, ratios[s]) for s in solvers]...)
    max_tau = isempty(finite_ratios) ? 2.0 : maximum(finite_ratios) * 1.1
    max_tau = max(max_tau, 1.05)

    taus = range(1.0, max_tau; length = 200)

    p_plot = plot(
        title = title_str,
        xlabel = "τ (razão para o melhor resultado)",
        ylabel = "ρ(τ) - fração de instâncias",
        ylim = (0, 1.05),
        legend = :outertopright,
        legendfontsize = 7,
        titlefontsize = 10,
        size = (800, 500),
    )

    for s in solvers
        rho = [count(r -> r <= t, ratios[s]) / n_problems for t in taus]
        plot!(p_plot, taus, rho; label = string(s), linewidth = 2, seriestype = :steppost)
    end

    savefig(p_plot, joinpath(output_dir, filename))
    return p_plot
end

function gerar_performance_profiles(df::DataFrame, perf_dir::AbstractString)
    df = copy(df)
        df.method_heuristic = string.(df.allocation_method, " | ", df.routing_heuristic)

    for grupo in split_merge_groups(df)
        performance_profile(
            grupo.df, :distance, :method_heuristic, :data_id,
                "Perfil de desempenho - distancia - $(grupo.label)",
            "performance_profile_distance_$(_safe_filename(grupo.slug)).png",
            perf_dir;
            lower_is_better = true,
        )

        performance_profile(
            grupo.df, :sum_pickers, :method_heuristic, :data_id,
                "Perfil de desempenho - pickers - $(grupo.label)",
            "performance_profile_picker_count_$(_safe_filename(grupo.slug)).png",
            perf_dir;
            lower_is_better = true,
        )
    end
end

function gerar_comparacoes(
    csv_path::AbstractString = COMPARE_CSV_PATH,
    report_path::AbstractString = REPORT_TXT_PATH,
)
    mkpath(dirname(report_path))

    open(report_path, "w") do io
        try
            df = load_compare_data(csv_path)
            results = write_analysis_report(io, csv_path, df)

            if !isempty(results)
                dirs = ensure_output_dirs()
                redirect_stdout(io) do
                    gerar_histogramas(results, dirs.histogramas)
                    gerar_boxplots(results, dirs.boxplots)
                    gerar_performance_profiles(results, dirs.performance)
                end
                println(io, "\nGraficos salvos em: ", abspath(GRAFICOS_DIR))
            end
        catch error
            println(io, "\nFalha na análise: ", sprint(showerror, error))
        end
    end

    return report_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    gerar_comparacoes()
end