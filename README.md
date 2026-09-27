# Warehouse Slotting and Picking

Research code for experimenting with **warehouse slotting** (assigning SKUs to storage locations) and **order picking** (routing pickers and merging routes).

The project supports configurable warehouse layouts, SKU inventory generation, multiple allocation methods, routing heuristics, and route-merging strategies. Experiment results are written to `compare.csv` and can be analyzed with the comparison tools in `src/compare_main.jl`.

## Table of contents

- [Quick start](#quick-start)
- [Installation](#installation)
- [Run an experiment](#run-an-experiment)
- [Project structure](#project-structure)
- [Configuration](#configuration)
- [Available strategies](#available-strategies)
- [Add or modify a method](#add-or-modify-a-method)
- [Validation and troubleshooting](#validation-and-troubleshooting)
- [Contact](#contact)

## Quick start

1. Install [Julia](https://julialang.org/downloads/).
2. Install the required Julia packages using the instructions for your operating system below.
3. From the repository root, start the interactive experiment runner:

   ```sh
   julia src/main.jl
   ```

4. Answer the prompts to choose whether to replace `compare.csv`, the run mode, and the experiment settings.

The runner checks the configuration, strategy registrations, and configured dataset files before asking for experiment options. Run the command from the repository root so the `Data/`, `Results/`, and `compare.csv` paths resolve as expected.

## Installation

### Linux

Run the package setup script from the repository root:

```sh
chmod +x packages_linux.sh
./packages_linux.sh
```

### Windows

Run `packages_windows.exe`, or execute the PowerShell installer from the repository root:

```powershell
.\packages_windows.ps1
```

The setup scripts install the Julia packages used by the project. They do not launch the experiment runner; start it with `julia src/main.jl`.

## Run an experiment

The program first asks whether to replace the results file:

- **`y`** removes the existing `compare.csv`; results from this run are written to a fresh file.
- **`n`** preserves existing rows and appends only result rows that are not already present.

Then choose between a single experiment and batch mode. A single run prompts for the dataset, allocation method, routing heuristic, and merge strategy. Batch mode prompts for a dataset ID range and runs the configured method combinations.

The allocation prompt controls whether slotting is recalculated or loaded from the saved results when available. Results and cached allocation artifacts are stored under `Results/` and `Results_cache/`.

To compare results or generate comparison plots, run the comparison script from the repository root:

```sh
julia src/compare_main.jl
```

## Project structure

```text
.
├── Data/                          # Input warehouse instances
├── Results/                       # Saved experiment outputs and allocations
├── Results_cache/                 # Intermediate experiment/cache files
├── compare.csv                    # Accumulated experiment summary
└── src/
    ├── General_functions/
    │   ├── load.jl                # Loads shared types, config, I/O, and validation
    │   ├── config.jl              # Default warehouse, SKU, allocation, and picker settings
    │   ├── reader.jl              # Input parsing and interactive prompts
    │   ├── save_files.jl          # Experiment summary output
    │   ├── types.jl               # Shared data types and strategy enums
    │   └── validation.jl          # Configuration, input, and integration checks
    ├── Warehouse/
    │   ├── load.jl
    │   ├── create_warehouse.jl
    │   ├── distance.jl
    │   └── locations.jl
    ├── Inventory_sizing/
    │   ├── load.jl
    │   └── generate_skus_lognormal.jl
    ├── Slotting/
    │   ├── load.jl
    │   ├── ABC/                    # ABC classification and allocation
    │   ├── ALS/                    # ALS scoring and optimization
    │   ├── allocation_main.jl     # Allocation strategy registry and dispatch
    │   └── cooccurrence.jl
    ├── Picking/
    │   ├── load.jl
    │   ├── Route/
    │   │   ├── heuristics/         # A* and greedy routing
    │   │   └── selector.jl         # Routing strategy registry and dispatch
    │   ├── Merge/
    │   │   ├── heuristics/         # Clarke–Wright merge variants
    │   │   └── selector.jl         # Merge strategy registry and dispatch
    │   └── validation.jl
    ├── experiment_runner.jl       # Single-run and batch orchestration
    ├── compare_main.jl            # Result analysis and visualizations
    └── main.jl                    # Application entry point
```

Each subsystem has a `load.jl` file that centralizes its include order. The entry point loads these subsystem files rather than including each implementation individually.

## Configuration

Edit the `Params` values in [`src/General_functions/config.jl`](src/General_functions/config.jl) to change the default experiment setup.

| Setting | Field | Purpose |
| --- | --- | --- |
| Warehouse layout | `n_aisles`, `n_shelves` | Number of aisles and shelves per aisle side. |
| Base shelf capacity | `shelf_capacity` | Base capacity used to derive each generated location's storage volume. |
| Warehouse fill target | `filling_rate` | Target fraction of total warehouse capacity used for generated stock. |
| SKU volume generation | `sigma`, `tipic_v`, `volumetric_module`, `seed` | Log-normal volume parameters, discretization step, and random seed. |
| SKU priority weights | `p_frequency`, `p_volume`, `p_quantity` | Relative influence of demand frequency, SKU volume, and current quantity during inventory generation. |
| Candidate selection | `candidate_fraction` | Fraction of warehouse locations retained by the ALS candidate builder. |
| ALS | `als_k`, `als_factor` | Latent-factor count and regularization factor. |
| Spatial weighting | `distance_factor` | Controls the distance-based weighting used by message passing. |
| Message passing | `message_passing_factor` | Mix between ALS scores and message-passed scores; must be in `[0, 1]`. |
| Shelf variety | `max_variety` | Maximum distinct SKUs allowed at a storage location. |
| Picker capacity | `picker_capacity` | Maximum volume a picker can carry. |
| Input instances | `data_names` | Dataset filenames, resolved relative to the repository’s `Data/` directory. |

All settings are validated before the interactive prompts. For example, `candidate_fraction` must be in `(0, 1]`, capacities must be positive, and each configured dataset must exist.

`distance_factor` controls the distance weighting used by message passing. A value of `0` removes spatial weighting; increasing it makes locations at a fixed distance receive more similar weights. The ALS parameters can be explored independently, for example:

```text
als_factor = 0.001, 0.01, 0.1, 1
als_k      = 5, 10, 20, 30, 50
```

Example message-passing values include `0.1`, `0.5`, and `0.9`.

## Available strategies

### Slotting

The allocation methods are declared by `AllocationMethod` in `General_functions/types.jl`:

- **ABC** — classify SKUs and allocate them according to class and demand.
- **ABC heuristic** — use ABC priorities, co-occurrence, and location distances to guide allocation.
- **ALS** — derive SKU-location scores with alternating least squares and optimize the allocation.
- **Message passing** — adjust ALS scores using co-occurrence and distance information before optimizing allocation.

### Picking

Routing heuristics choose the next candidate location for a picker:

- **A\*** — selects using the current travel cost and a look-ahead estimate.
- **Greedy** — selects the nearest candidate.

Route-merging strategies combine picker routes:

- **Clarke–Wright** — uses the greedy merge implementation.
- **Clarke–Wright heuristic** — uses the savings-based implementation.
- **No heuristic** — returns routes without merging.

## Add or modify a method

Keep implementation code in the subsystem where it belongs. When adding a source file, include it in that subsystem’s `load.jl` **after its dependencies**. The project currently uses Julia’s global namespace for these includes, so give new functions and constants distinctive names to avoid collisions.

To add a selectable strategy, implement it and register it in the corresponding registry:

### Allocation strategy

1. Add the implementation under `Slotting/` and include it from `Slotting/load.jl`.
2. Add a function accepting `strategy(context)` and register it in `ALLOCATION_STRATEGIES` in `Slotting/allocation_main.jl`.
3. The context provides `cfg`, `params`, `instance`, `warehouse`, `depot_distance`, `cooc`, `skus`, `distance_matrix`, and `empty_matrix`.
4. Return a named tuple containing `allocations`, `sparse_matrix`, `U`, `V`, `S_hat`, `W`, `P`, and `S_hat_hat`. Use a `0 × 0` integer matrix in `allocations` only when the strategy cannot produce a feasible allocation.
5. Add the corresponding enum value to `AllocationMethod` in `General_functions/types.jl`.

The allocation matrix must contain non-negative integer quantities, allocate every SKU, and respect shelf capacity and `max_variety`. Capacity checks allow a tolerance of `volumetric_module / 2`.

### Routing heuristic

1. Add the heuristic under `Picking/Route/heuristics/` and include it from `Picking/load.jl`.
2. Register it in `ROUTING_STRATEGIES` in `Picking/Route/selector.jl`.
3. Use the signature `(current, candidates, distance_matrix, depot_distance)`. Return a candidate location index, or `nothing` when there is no valid candidate.
4. Add its enum value to `RoutingHeuristic` in `General_functions/types.jl`.

### Merge strategy

1. Add the heuristic under `Picking/Merge/heuristics/` and include it from `Picking/load.jl`.
2. Register an adapter in `MERGE_STRATEGIES` in `Picking/Merge/selector.jl`.
3. The strategy receives the routes, distance matrix, SKU volumes, picker capacity, depot distances, depot ID, and warehouse. Return a `Vector{Pickers}` with valid routes.
4. Add its enum value to `MergeHeuristic` in `General_functions/types.jl`.

At startup, the application checks that every enum option has a registered implementation. If you change a strategy’s output contract or introduce configuration fields, update the matching checks in `General_functions/validation.jl` as well.

## Validation and troubleshooting

Validation is intended to catch integration mistakes close to where they occur:

- At startup, configuration values, configured dataset files, and strategy registrations are checked.
- Dataset parsing verifies the declared SKU and order counts, and that order SKU IDs are in range.
- Allocation results are checked for the expected dimensions, complete SKU quantities, shelf capacity, and variety limits.
- Routing checks matrix dimensions, candidate bounds, and that the returned next location is one of the candidates.
- Merge results and picker routes are checked before further processing.

When a customization violates one of these contracts, the program emits a Julia `@warn` explaining what is invalid, then raises an `ArgumentError`. Correct the reported setting, input, or strategy contract before rerunning.

If Julia reports that a package is missing, rerun the setup script for your platform. If a dataset is reported missing, verify its filename in `data_names` and place the file under `Data/`.

## Contact

[![Email](https://img.shields.io/badge/Email-Contact-blue?style=flat-square&logo=gmail&logoColor=white)](mailto:gabrielrebou@hotmail.com.br)

**Gabriel Rebouças**

Applied and Computational Mathematics

University of Campinas (UNICAMP)
