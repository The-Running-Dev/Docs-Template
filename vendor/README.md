# vendor/

`subzerodev-data-json-0.1.0.tgz` is a temporary vendored build of
[`subzerodev-data-json`](https://github.com/The-Running-Dev/SubZeroDev.Data.Json), packed from
its source tree after the npm-published `0.1.0` was found to predate that package's own J13
slice (`readSourceMap`/`parseSourceMap`, used by `scripts/pre-build.ts` — see J6.9 in that
package's `design/30-slices.md`).

Remove this directory and switch `package.json`'s `subzerodev-data-json` dependency back to a
normal registry version once a real npm release includes J13 (i.e. once
`npm view subzerodev-data-json version` is no longer `0.1.0`, or a later semver is published
carrying the same exports).

To regenerate this tarball from an updated checkout of that repo:

```bash
cd path/to/SubZeroDev.Data.Json
npm run build
npm pack --pack-destination /path/to/Docusaurus-Template/vendor
```
