# Microservice Connector Recovery

This project recovers microservice call-return connectors from TypeScript/NestJS codebases with CodeQL, then renders the recovered architecture as PlantUML.

The current connector set is:

- REST calls made through `axios`
- unary gRPC and NestJS `ClientProxy.send(...)` calls
- Redis command calls, excluding pub-sub commands

Publish-subscribe patterns are intentionally out of scope.

## Project Layout

```text
all_connectors.ql          Unified CodeQL table query.
connectors/*.qll           Protocol-specific detectors.
lib/Connector.qll          Shared connector interface.
lib/ExprResolution.qll     Symbolic string/value resolver.
lib/ServiceIdentification.qll
                            Caller/target service naming heuristics.
pipeline/                  Python parser, normalizer, and PlantUML renderer.
run_all_connectors.ps1     Query + BQRS decode helper.
benchmark.ps1              Repeated CodeQL timing helper.
tests/                     Small fixtures used while developing queries.
```

Generated query/script outputs should live in the repository-level
`../results` folder and should normally be `.bqrs` or `.csv`.

## Standard Workflow

From the repository root:

Copy only the commands inside the code blocks. Do not paste the triple
backtick fences.

```powershell
codeql query run `
  --database=dbs\nestjs-db `
  --output=results\nestjs-results.bqrs `
  --ram=16384 `
  my-research-project\all_connectors.ql
```

Decode the BQRS file to CSV:

```powershell
codeql bqrs decode `
  --format=csv `
  --output=results\nestjs-results.csv `
  results\nestjs-results.bqrs
```

Render the decoded CSV to PlantUML:

```powershell
$env:PYTHONPATH = "my-research-project"
python -B -m pipeline.converter `
  --input results\nestjs-results.csv `
  --output nestjs_communication.puml `
  --service-view
```

Why the Python command uses `pipeline.converter` instead of
`my-research-project.pipeline.converter`: Python module names cannot contain
hyphens, so `PYTHONPATH` points Python at the project folder and the importable
package is `pipeline`.

Shortcut script from `my-research-project`:

```powershell
.\run_all_connectors.ps1 -Database ..\dbs\nestjs-db
```

The shortcut writes `..\results\all-connectors.bqrs` and
`..\results\all-connectors.csv`, so render that output with:

```powershell
$env:PYTHONPATH = "my-research-project"
python -B -m pipeline.converter `
  --input results\all-connectors.csv `
  --output diagram.puml
```

## Adding A Connector

1. Add a new `connectors/<Protocol>Connector.qll` module.
2. Implement a class that extends `Connector`.
3. Import the module from `all_connectors.ql`.
4. Add the protocol token to `pipeline/models.py`.
5. Add a normalizer in `pipeline/normalizers.py` if the endpoint needs cleanup.
6. Add an edge style and label behavior in `pipeline/plantuml_renderer.py`.

Keep connector rows in this schema:

```text
protocol, callerService, operation, targetService, endpoint, configKey, location
```

## Output Policy

Use `results/` for generated artifacts:

- CodeQL query output: `.bqrs`
- decoded table output: `.csv`
- benchmark logs and temporary evaluator output: `results/evaluator-logs/`

Avoid writing fresh outputs into `tests/`; those files are fixtures.
