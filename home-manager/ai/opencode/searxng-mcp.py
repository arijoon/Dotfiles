import json
import os
import urllib.error
import urllib.parse
import urllib.request

import anyio
import mcp.types as types
from mcp.server.lowlevel import Server
from mcp.server.stdio import stdio_server

TIMEOUT = 30

GUIDE = "Start a SearXNG with its JSON format enabled and set SEARXNG_URL to its address."

TOOL = types.Tool(
    name="search",
    description=(
        "Search the web through the operator's own SearXNG. "
        "Returns titles, URLs and snippets from several engines. "
        "Read a page with webfetch before relying on it. "
        'For recent events, use category "news" and a time_range.'
    ),
    inputSchema={
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "minLength": 1,
                "description": "What to search for. Add site:example.org to stay on one site. !! bangs aren't supported.",
            },
            "category": {
                "type": "string",
                "enum": ["general", "news"],
                "default": "general",
                "description": "general for the web and reference works, news for news sites.",
            },
            "time_range": {
                "type": "string",
                "enum": ["day", "week", "month", "year"],
                "description": "Only results from the last day, week, month or year.",
            },
            "page": {
                "type": "integer",
                "minimum": 1,
                "default": 1,
                "description": "Page of results, from 1.",
            },
        },
        "required": ["query"],
    },
)

server = Server("searxng")


class SearchError(Exception):
    pass


class RefuseRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *_):
        return None


opener = urllib.request.build_opener(RefuseRedirects)


def fetch(base, params):
    target = f"{base}/search?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(target, headers={"Accept": "application/json"})
    try:
        with opener.open(request, timeout=TIMEOUT) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        if 300 <= error.code < 400:
            location = error.headers.get("Location")
            raise SearchError(
                f"SearXNG at {base} redirected the query"
                + (f" to {location}" if location else "")
                + " instead of answering it, and nothing was fetched from there. "
                "SearXNG does that for a !! bang (e.g. !!w), which this tool doesn't support: "
                "search again without it."
            ) from None
        raise SearchError(
            f"SearXNG at {base} answered HTTP {error.code} {error.reason}. "
            f"Is SearXNG what listens there? {GUIDE}"
        ) from None
    except (urllib.error.URLError, OSError) as error:
        reason = getattr(error, "reason", error)
        if isinstance(reason, TimeoutError):
            raise SearchError(f"SearXNG at {base} didn't answer within {TIMEOUT} seconds. {GUIDE}") from None
        raise SearchError(f"SearXNG isn't running: nothing answered at {base} ({reason}). {GUIDE}") from None
    try:
        return json.loads(body)
    except ValueError:
        raise SearchError(
            f"SearXNG at {base} didn't answer with JSON. Is SearXNG what listens there? {GUIDE}"
        ) from None


def render(query, data):
    lines = []
    for index, result in enumerate(data.get("results") or [], 1):
        lines.append(f"{index}. {result.get('title') or result.get('url')}")
        lines.append(f"   {result.get('url')}")
        if result.get("publishedDate"):
            lines.append(f"   Published: {result['publishedDate']}")
        if result.get("content"):
            lines.append(f"   {' '.join(str(result['content']).split())}")
    for answer in data.get("answers") or []:
        text = answer.get("answer") if isinstance(answer, dict) else answer
        if text:
            url = answer.get("url") if isinstance(answer, dict) else None
            lines.append(f"Answer: {text}" + (f" ({url})" if url else ""))
    for box in data.get("infoboxes") or []:
        lines.append(f"Infobox: {box.get('infobox')}" + (f" ({box['id']})" if box.get("id") else ""))
        if box.get("content"):
            lines.append(f"   {' '.join(str(box['content']).split())}")
    if not data.get("results"):
        lines.insert(0, f'SearXNG found no results for "{query}".')
    if data.get("suggestions"):
        lines.append("Suggestions: " + "; ".join(map(str, data["suggestions"])))
    unresponsive = [
        f"{entry[0]} ({entry[1]})" for entry in data.get("unresponsive_engines") or [] if len(entry) >= 2
    ]
    if unresponsive:
        lines.append("Engines that didn't answer: " + ", ".join(unresponsive))
    return "\n".join(lines)


@server.list_tools()
async def list_tools():
    return [TOOL]


@server.call_tool()
async def call_tool(name, arguments):
    if name != TOOL.name:
        raise SearchError(f"Unknown tool {name}")
    base = os.environ.get("SEARXNG_URL", "").rstrip("/")
    if not base:
        raise SearchError(f"SEARXNG_URL isn't set. {GUIDE}")
    params = {
        "q": arguments["query"],
        "format": "json",
        "categories": arguments.get("category", "general"),
        "pageno": arguments.get("page", 1),
        "safesearch": 0,
    }
    if arguments.get("time_range"):
        params["time_range"] = arguments["time_range"]
    data = await anyio.to_thread.run_sync(fetch, base, params, abandon_on_cancel=True)
    if not isinstance(data, dict):
        raise SearchError(f"SearXNG at {base} answered JSON that isn't a search result. {GUIDE}")
    return [types.TextContent(type="text", text=render(arguments["query"], data))]


async def main():
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())


anyio.run(main)
