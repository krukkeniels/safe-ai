# Supply Chain Security

Guidance on managing package dependencies, registries, and MCP servers within safe-ai.

---

## Lock files

Always use lock files with integrity hashes. They ensure reproducible installs and detect tampering.

| Ecosystem | Lock file | Secure install command |
|-----------|-----------|----------------------|
| npm | `package-lock.json` | `npm ci` (not `npm install`) |
| Yarn | `yarn.lock` | `yarn install --frozen-lockfile` |
| pip | `requirements.txt` with hashes | `pip install --require-hashes -r requirements.txt` |
| Poetry | `poetry.lock` | `poetry install` |

`npm ci` deletes `node_modules` and installs exactly what is in the lock file. `npm install` can modify the lock file, which an agent might do silently.

## Internal mirrors

For sensitive environments, replace public registries with internal mirrors (Artifactory, Nexus, Verdaccio):

```yaml
# allowlist.yaml -- replace public registries
domains:
  - nexus.corp.example.com       # internal npm + PyPI mirror
  # registry.npmjs.org REMOVED
  # pypi.org REMOVED
  # files.pythonhosted.org REMOVED
```

Configure the package manager inside the sandbox to point to the mirror:

```bash
npm config set registry https://nexus.corp.example.com/repository/npm/
pip config set global.index-url https://nexus.corp.example.com/repository/pypi/simple/
```

## MCP servers

MCP (Model Context Protocol) server traffic is controlled by the domain allowlist. If the MCP server's domain is not in `allowlist.yaml`, the agent cannot connect to it.

Before adding an MCP server's domain to the allowlist:
- Verify the server's source code and maintainer
- Check for known vulnerabilities (1 in 5 packages in some MCP registries contained malicious code)
- Prefer self-hosted MCP servers for sensitive environments
- Audit the permissions and data access the MCP server requires

## Hallucinated packages

AI agents may suggest packages that do not exist ("slopsquatting"). Attackers monitor LLM outputs, register these names on public registries, and publish malicious packages.

Mitigations:
- Review all new dependencies before installing -- verify the package exists and is maintained
- Use `npm info <package>` or `pip index versions <package>` to confirm a package is real before adding it
- Internal mirrors with curated package lists eliminate this risk entirely
