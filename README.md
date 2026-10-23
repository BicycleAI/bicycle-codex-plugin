# Bicycle AI

Bicycle AI connects your assistant to your Bicycle account and adds two analyst
skills for answering business questions through Bicycle Studio's query tools.

- **bicycle-explore** finds accessible domains, metric definitions, fields and valid
  breakdowns.
- **bicycle-query** writes and checks queries for totals, rankings, trends, shares,
  period comparisons and row drill-downs, then explains the results and warnings.

## Requirements

Use a Bicycle account with access to an onboarded domain and a client that supports
plugins and remote MCP authentication. The installation instructions below are for
Claude Code and Codex. While the GitHub repositories are private, installation
requires access to the corresponding repository.

## Install

Each client has its own repository, with the package at the root of `main`.

### Claude Code

```sh
git clone --single-branch --branch main \
  https://github.com/BicycleAI/bicycle-claude-plugin.git bicycle-ai-claude
claude plugin marketplace add ./bicycle-ai-claude
claude plugin install bicycle-ai@bicycle-ai
```

### Codex

```sh
git clone --single-branch --branch main \
  https://github.com/BicycleAI/bicycle-codex-plugin.git bicycle-ai-codex
codex plugin marketplace add ./bicycle-ai-codex
codex plugin add bicycle-ai@bicycle-ai
```

Start a new session after installation so the client loads the plugin.

## Connect your Bicycle account

The package declares the remote **bicycle-ai** MCP server at
`https://app.bicycle.ai/mcp`. Complete sign-in through your client's MCP OAuth
authentication flow and select the Bicycle account you intend to use. Never paste
tokens or passwords into a conversation or edit them into the package.

For Claude chat or Cowork, connect **Bicycle AI** through its
[connector directory entry](https://claude.ai/directory/bicycle-ai). The connector
and these packages use the same MCP endpoint.

If tools are unavailable, check that the plugin is enabled and its MCP connection
is authenticated. If a domain is missing, confirm your account has access to it
with your Bicycle administrator.

## Ask a question

Try “What metrics can I query?”, “Show revenue by region over the last 28 days”,
or “Compare this week's orders with last week's.” Name a domain when you have
several, or select one when asked. Supplying a date range makes your intended
reporting period explicit.

The skills discover metric and field definitions through Bicycle's `query_*`
tools, follow the model's advertised Studio SQL or semantic SQL language, and use
`query_explain`, `query_compile` or `query_run`
as appropriate. They report the selected date range, returned warnings,
truncation and empty results. When Bicycle requests consent for warehouse
execution or stale cached data, the skills present that request and any estimated
price, and resubmit with consent only after you agree.
Studio SQL queries stay cache-only; a cache miss is reported without starting a
warehouse read. Where the server advertises pattern and insight tools, exploration
can also read existing findings and preserve partial-result warnings.

## Data and account access

Your client sends MCP tool requests, including query text and parameters, to
Bicycle through the declared endpoint under your authenticated account. Tool
responses return to the client for use in the conversation. The connector also
provides Bicycle application tools; these analyst skills focus on its `query_*`
tools. The package contains instructions and connection metadata, with no hooks,
local MCP server code or embedded credentials.

## Support

Contact your Bicycle administrator for account, onboarding or domain-access
issues. For package issues, report the client version, package version, affected
skill and error code to the
[Claude plugin maintainers](https://github.com/BicycleAI/bicycle-claude-plugin/issues)
or [Codex plugin maintainers](https://github.com/BicycleAI/bicycle-codex-plugin/issues).
Keep credentials and private query results out of issue reports.
