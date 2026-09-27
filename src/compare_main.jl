# src/compare_functions.jl
#
# Analise comparativa dos resultados salvos em compare.csv:
#   - Tabelas numericas impressas no terminal (brutas, agregadas e ranking)
#   - Histogramas de distancia e pickers, separados por merge_strategy:
#       CLARKE_WRIGHT (completo) / CLARKE_WRIGHT_HEURISTIC / NO_HEURISTIC
#   - Boxplots (facetados por routing_heuristic) de distancia e pickers
#   - Performance profile (Dolan-More), um por merge_strategy
#
# Uso:
#   1) Isolado, no terminal (a partir da pasta src/):
#        julia --project=.. compare_functions.jl
#      (o --project=.. ativa o ambiente do projeto, na pasta pai de src/,
#       onde deve estar o Project.toml com CSV/DataFrames/Plots/StatsPlots)
#
#   2) Incluido a partir de outro arquivo (ex.: main.jl):
#        include("compare_functions.jl")
#        gerar_comparacoes()
#      Nesse caso a funcao NAO roda automaticamente; e preciso chama-la.

import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using CSV
using DataFrames
using Plots
using StatsPlots
using Statistics
using Printf

gr()
const COMPARE_CSV_PATH = joinpath(@__DIR__, "..", "compare.csv")
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

    df.config_label = string.(
        df.allocation_method, " | ",
        df.routing_heuristic, " | ",
        df.merge_strategy
    )

    return df
end

function abbreviate(s::AbstractString; maxlen::Int = 4)
    parts = split(s, "_")
    abbr_parts = [length(p) > maxlen ? p[1:maxlen] : p for p in parts]
    return join(abbr_parts, "_")
end

function add_ratio_columns!(df::DataFrame)
    transform!(
        groupby(df, :data_id),
        :distance    => (x -> x ./ minimum(x)) => :distance_ratio,
        :sum_pickers => (x -> x ./ minimum(x)) => :pickers_ratio,
    )
    return df
end

const MERGE_GROUP_INFO = [
    ("CLARKE_WRIGHT",           "clarke",            "Clarke-Wright merge (standard)"),
    ("CLARKE_WRIGHT_HEURISTIC", "clarke_heuristic",  "Clarke-Wright merge (heuristic)"),
    ("NO_HEURISTIC",            "no_merge",           "No merge"),
]

function split_merge_groups(df::DataFrame)
    grupos = NamedTuple[]
    valores_conhecidos = first.(MERGE_GROUP_INFO)

    for (valor, slug, label) in MERGE_GROUP_INFO
        sub = filter(row -> row.merge_strategy == valor, df)
        push!(grupos, (slug = slug, label = label, df = sub))
    end

    outros = filter(row -> !(row.merge_strategy in valores_conhecidos), df)
    if !isempty(outros)
        for valor in unique(outros.merge_strategy)
            sub = filter(row -> row.merge_strategy == valor, outros)
            push!(grupos, (slug = "other_$(valor)", label = "Merge: $(valor)", df = sub))
        end
    end

    return grupos
end

_safe_filename(s::AbstractString) = replace(s, r"[^A-Za-z0-9_\-]" => "_")

fmt_value(x::AbstractFloat) = isnan(x) ? "—" : @sprintf("%.3f", x)
fmt_value(x::Integer) = string(x)
fmt_value(x) = string(x)

# Imprime um DataFrame formatado como tabela de texto alinhada.
function print_table(df::DataFrame)
    if isempty(df)
        println("(no data)")
        return
    end

    cols = names(df)
    str_cols = Dict(c => [fmt_value(df[i, c]) for i in 1:nrow(df)] for c in cols)
    widths = Dict(c => max(length(c), maximum(length.(str_cols[c]); init = 0)) for c in cols)

    header = join([rpad(c, widths[c]) for c in cols], " | ")
    println(header)
    println("-"^length(header))

    for i in 1:nrow(df)
        println(join([rpad(str_cols[c][i], widths[c]) for c in cols], " | "))
    end
end

# Tabela agregada (media, mediana, desvio, min, max, n) por grupo.
function print_summary_table(
    df::DataFrame,
    group_cols::Vector{Symbol},
    value_col::Symbol,
    title_str::AbstractString,
)
    println("\n-- $title_str --")

    if isempty(df)
        println("(no data)")
        return
    end

    resumo = combine(
        groupby(df, group_cols),
        value_col => mean => :mean,
        value_col => median => :median,
        value_col => std => :std_dev,
        value_col => minimum => :min,
        value_col => maximum => :max,
        nrow => :n,
    )
    sort!(resumo, :mean)

    print_table(resumo)
end

# Ranking geral: media da razao (em relacao ao melhor por instancia)
# de cada configuracao completa, do melhor para o pior.
function print_ranking(df::DataFrame, ratio_col::Symbol, title_str::AbstractString)
    println("\n-- Ranking — $title_str (mean ratio to the best result per instance) --")

    resumo = combine(
        groupby(df, :config_label),
        ratio_col => mean => :mean_ratio,
        nrow => :n,
    )
    sort!(resumo, :mean_ratio)

    print_table(resumo)
end

function imprimir_tabelas(df::DataFrame)
    println("="^78)
    println("RAW RESULTS (compare.csv)")
    println("="^78)

    cols_brutos = [
        :allocation_method, :routing_heuristic, :merge_strategy,
        :distance, :sum_pickers,
        :allocation_time, :route_time, :merge_time,
    ]

    for data_id in sort(unique(df.data_id))
        sub = filter(row -> row.data_id == data_id, df)
        nome = first(sub.data_name)
        println("\n--- Test case ID=$data_id ($nome) — sorted by distance ---")
        sub_ordenado = sort(sub, :distance)
        print_table(select(sub_ordenado, cols_brutos))
    end

    println("\n" * "="^78)
    println("STATISTICS BY ALLOCATION METHOD (within each merge group)")
    println("="^78)
    println("""
    Each group below shows two views, always split by
    allocation_method + routing_heuristic (combining them would hide
    differences of up to ~30% between ASTAR and GREEDY for the same
    method/merge):

      (raw)    -> mean/median/etc. of distance and picker count as
                  absolute values, aggregated across all instances
                  (data_id) without adjustment. Larger instances
                  therefore have a greater effect on the mean.

      (ratio)  -> the same metrics, but each value is divided by the
                  best result for THE SAME INSTANCE (1.0 = best for
                  that instance). This fairly compares methods even
                  across different instance sizes and is recommended
                  for determining whether method X is better than Y.
    """)

    for grupo in split_merge_groups(df)
        println("\n### $(grupo.label) ###")

        println("\n[raw, unnormalized values]")
        print_summary_table(
            grupo.df, [:allocation_method, :routing_heuristic], :distance,
            "Distance by method and heuristic (raw)",
        )
        print_summary_table(
            grupo.df, [:allocation_method, :routing_heuristic], :sum_pickers,
            "Picker count by method and heuristic (raw)",
        )

        println("\n[normalized values — ratio to the best result per instance]")
        print_summary_table(
            grupo.df, [:allocation_method, :routing_heuristic], :distance_ratio,
            "Distance by method and heuristic (ratio)",
        )
        print_summary_table(
            grupo.df, [:allocation_method, :routing_heuristic], :pickers_ratio,
            "Picker count by method and heuristic (ratio)",
        )
    end

    println("\n" * "="^78)
    println("OVERALL RANKING OF COMPLETE CONFIGURATIONS")
    println("="^78)
    print_ranking(df, :distance_ratio, "Distance")
    print_ranking(df, :pickers_ratio, "Picker count")
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
        @warn "DataFrame is empty for \"$title_str\"; chart was not generated."
        return nothing
    end

    grupos = sort(unique(df[!, group_col]))

    p = plot(
        title = title_str,
        xlabel = xlabel_str,
        ylabel = "Frequency",
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
            "Distance (raw) — $(grupo.label)",
            "hist_distance_$(_safe_filename(grupo.slug))_raw.png",
            hist_dir;
            xlabel_str = "Distance",
        )

        plot_grouped_histogram(
            grupo.df, :sum_pickers, :allocation_method,
            "Picker count (raw) — $(grupo.label)",
            "hist_picker_count_$(_safe_filename(grupo.slug))_raw.png",
            hist_dir;
            xlabel_str = "Picker count",
        )

        plot_grouped_histogram(
            grupo.df, :distance_ratio, :allocation_method,
            "Distance (ratio vs. best) — $(grupo.label)",
            "hist_distance_$(_safe_filename(grupo.slug))_ratio.png",
            hist_dir;
            xlabel_str = "Distance / best distance for the instance",
        )

        plot_grouped_histogram(
            grupo.df, :pickers_ratio, :allocation_method,
            "Picker count (ratio vs. best) — $(grupo.label)",
            "hist_picker_count_$(_safe_filename(grupo.slug))_ratio.png",
            hist_dir;
            xlabel_str = "Picker count / best count for the instance",
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
        @warn "DataFrame is empty for \"$title_str\"; boxplot was not generated."
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
            xrotation = 20,
            titlefontsize = 9,
            guidefontsize = 8,
            tickfontsize = 7,
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

    return layout_final
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
        @warn "DataFrame is empty for \"$title_str\"; performance profile was not generated."
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
        @warn "No instances found for \"$title_str\"."
        return nothing
    end

    finite_ratios = vcat([filter(isfinite, ratios[s]) for s in solvers]...)
    max_tau = isempty(finite_ratios) ? 2.0 : maximum(finite_ratios) * 1.1
    max_tau = max(max_tau, 1.05)

    taus = range(1.0, max_tau; length = 200)

    p_plot = plot(
        title = title_str,
        xlabel = "τ (ratio to the best result)",
        ylabel = "ρ(τ) — fraction of instances",
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
    df.method_heuristic = string.(
        abbreviate.(string.(df.allocation_method)), " | ",
        abbreviate.(string.(df.routing_heuristic))
    )

    for grupo in split_merge_groups(df)
        performance_profile(
            grupo.df, :distance, :method_heuristic, :data_id,
            "Performance Profile — Distance — $(grupo.label)",
            "performance_profile_distance_$(_safe_filename(grupo.slug)).png",
            perf_dir;
            lower_is_better = true,
        )

        performance_profile(
            grupo.df, :sum_pickers, :method_heuristic, :data_id,
            "Performance Profile — Picker Count — $(grupo.label)",
            "performance_profile_picker_count_$(_safe_filename(grupo.slug)).png",
            perf_dir;
            lower_is_better = true,
        )
    end
end

function gerar_comparacoes(csv_path::AbstractString = COMPARE_CSV_PATH)
    df = load_compare_data(csv_path)
    add_ratio_columns!(df)
    dirs = ensure_output_dirs()

    imprimir_tabelas(df)

    gerar_histogramas(df, dirs.histogramas)
    gerar_boxplots(df, dirs.boxplots)
    gerar_performance_profiles(df, dirs.performance)

    println("\nCharts saved to: ", GRAFICOS_DIR)

    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    gerar_comparacoes()
end