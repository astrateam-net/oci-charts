# OCI Helm Charts Mirror

This is our stop-gap mirror of OCI Helm Charts that can be used until maintainers of upstream charts publish them.

> [!CAUTION]
> **Subscribe to the upstream issues or PRs tracking OCI support.** If you use these charts it is **your responsibility to switch to the official OCI chart as soon as one exists**, because the mirror entry will be deprecated here. We bear **no responsibility** for you **not paying close attention to this repository and the changes herein**. Once there is support upstream the OCI charts will remain published here for 6 months, after which they will be pruned.

## Usage

Charts are published to `oci://ghcr.io/astrateam-net/oci-charts/<chart>`. The OCI tag is the **upstream chart version, verbatim** — including a leading `v` when upstream uses one (for example `cert-manager:v1.21.1`).

> [!NOTE]
> A chart is published under its `artifactName`, which can differ from the directory name in `apps/`. Currently: `apps/mongodb-community-operator` → `community-operator`, `apps/onepassword-connect` → `connect`.

### CLI

```sh
helm install ${RELEASE_NAME} --namespace ${NAMESPACE} oci://ghcr.io/astrateam-net/oci-charts/${CHART_NAME} --version ${CHART_VERSION}
```

### Verifying a signature

Every published chart is signed with cosign in keyless mode:

```sh
cosign verify ghcr.io/astrateam-net/oci-charts/${CHART_NAME}:${CHART_VERSION} \
  --certificate-identity-regexp '^https://github.com/astrateam-net/oci-charts.*$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Flux

> [!WARNING]
> Even though these charts are signed via cosign it will not prevent malicious code pushed upstream from ending up in a release here. For example if cert-manager's Helm chart is compromised, there is nothing stopping that release from being mirrored here.

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: ${CHART_NAME}
  namespace: ${NAMESPACE}
spec:
  interval: 1h
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: ${CHART_VERSION}
  url: oci://ghcr.io/astrateam-net/oci-charts/${CHART_NAME}
  verify:
    provider: cosign
    matchOIDCIdentity:
      - issuer: ^https://token.actions.githubusercontent.com$
        subject: ^https://github.com/astrateam-net/oci-charts.*$
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ${RELEASE_NAME}
  namespace: ${NAMESPACE}
spec:
  interval: 1h
  chartRef:
    kind: OCIRepository
    name: ${CHART_NAME}
    namespace: ${NAMESPACE}
  values:
...
```

## How it works

- Each mirrored chart is one directory under `apps/` containing a single `metadata.yaml`.
- Renovate watches the upstream source declared in `metadata.yaml` and opens an auto-merging PR whenever a new version appears.
- Merging to `main` triggers `.github/workflows/release.yaml`, which fans out over the changed charts and calls the reusable `app-builder.yaml` workflow: fetch from upstream → push to GHCR → sign with cosign.
- Pull requests run the same build without pushing, plus workflow and metadata linting, so a broken entry fails before it reaches the registry.
- The first time a chart is published, a GitHub Release is cut announcing it.
- Local tooling is pinned in `.mise/config.toml` / `.mise/mise.lock`; run `mise install` to get the same versions CI uses.

## Contributing

To add a new chart to this repository:

1. **Check for an existing OCI Helm Chart**

   Confirm that the application you want to add does **not** already provide an official OCI Helm Chart:

   ```sh
   helm show chart oci://<registry>/<path>/<chart> --version <version>
   ```

2. **Create a chart directory**

   Make a new directory under `apps/` named after the chart.

3. **Add chart metadata**

   Inside the new directory, create a `metadata.yaml` file. The `source:` block tells the builder where to fetch the chart from — set exactly one of `helm` or `git`.

   **Helm-sourced** (the upstream publishes a traditional Helm repository):

   ```yaml
   ---
   artifactName: <name of the published chart>
   source:
     helm:
       registry: <upstream Helm repository URL>
       version: <upstream chart version>
       # chart: <upstream chart name>   # optional, defaults to artifactName
   ```

   **Git-sourced** (the upstream ships chart manifests in a git repository but does not publish a Helm chart):

   ```yaml
   ---
   artifactName: <name of the published chart>
   source:
     git:
       repository: <upstream git repository URL>
       path: <path to the chart directory within the repository>
       tag: <git tag to clone>
   ```

   The chart is published to GHCR under `artifactName`, tagged with `source.helm.version` (or `source.git.tag`) verbatim.

4. **Request upstream OCI support**

   If the upstream project does not yet publish OCI Helm Charts (or any Helm chart at all, for git-sourced entries), open an issue in their application or chart repository requesting OCI Helm Chart support.

5. **Submit a pull request**

   Open a PR in this repository:
   - Include the link to the upstream issue (from step 4) in the PR description.
   - Ensure your PR only adds the new chart directory and metadata.

## Deprecating a chart

When upstream starts publishing an official OCI chart, retire the mirror entry by running the **Deprecate Chart** workflow (`.github/workflows/deprecate-app.yaml`) from the Actions tab. It opens a PR removing `apps/<name>`, optionally merges it, and cuts a release announcing the deprecation.

Already-published GHCR tags stay in place for 6 months so existing consumers can migrate; only new versions stop being mirrored.
