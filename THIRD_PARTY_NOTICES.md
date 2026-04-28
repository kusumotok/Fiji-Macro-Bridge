# Third-Party Notices

This project is distributed under the MIT License. See [LICENSE](./LICENSE).

Released artifacts may contain the following third-party components:

## Included in `Fiji_Macro_Bridge.jar`

### `org.json:json:20231013`

- Project: JSON in Java
- Upstream: https://github.com/stleary/JSON-java
- License: Public Domain
- Notes: This dependency is shaded into the plugin JAR.

## Used at build time or runtime, but not bundled in the plugin JAR

### `net.imagej:ij:1.54p`

- Project: ImageJ
- Upstream: https://github.com/imagej/ImageJ
- License: Public Domain
- Notes: Declared with Maven scope `provided`. The code runs against the ImageJ classes already shipped with Fiji and is not redistributed inside the plugin JAR.

### `mcp` Python package

- Project: Model Context Protocol Python SDK
- Upstream: https://github.com/modelcontextprotocol/python-sdk
- License: See the upstream project for the exact version shipped in any packaged executable.
- Notes: Used by the MCP server implementation. If a standalone executable is distributed, its bundled dependencies should be treated as part of that executable distribution.
