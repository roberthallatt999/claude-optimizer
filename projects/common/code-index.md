<!-- BEGIN CODE INDEX (managed by ai-config; do not edit between markers) -->
## Code Index

This project has a local codegraph index (`.codegraph/`, MCP server `codegraph`). For "where
is / what calls / what breaks if I change" questions, use `codegraph_explore` before grep and
file reads — one call returns the relevant source, call flow, and blast radius. Use
grep/Read for files it doesn't index (templates, config, docs). Subagents without the MCP
server can run `codegraph explore "<question>"`.
<!-- END CODE INDEX -->
