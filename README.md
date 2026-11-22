<div align="center">
<p>English | <a href="README.zh-CN.md">简体中文</a></p>
</div>

# ohos-python

Standalone CPython builds for OpenHarmony, similar in spirit to [astral-sh/python-build-standalone](https://github.com/astral-sh/python-build-standalone). Releases contain ready-to-extract Python installations and metadata that uv can use as a download catalog.

## Download and install

For example, CPython 3.15.0:

```sh
curl -fLO https://github.com/ohos-python/ohos-python/releases/download/20261123/cpython-3.15.0%2B20261123-aarch64-unknown-linux-ohos-install_only.tar.gz
# Users in mainland China can use the AtomGit mirror for faster downloads:
# curl -fLO https://atomgit.com/ohos-python/ohos-python/releases/download/20261123/cpython-3.15.0%2B20261123-aarch64-unknown-linux-ohos-install_only.tar.gz

tar -zxf cpython-*.tar.gz -C "$HOME"
export PATH="$HOME/python/bin:$PATH"
python3 --version
```

## Use with uv

To install and manage these CPython builds with uv, see [ohos-uv](https://github.com/ohos-python/ohos-uv).

## Build locally

An aarch64 Linux host capable of running [DockerHarmony](https://github.com/hqzing/dockerharmony) is required:

```sh
git clone https://github.com/ohos-python/ohos-python.git
cd ohos-python

docker run -dit --name ohos \
  -v "$PWD":/workdir -w /workdir \
  ghcr.io/hqzing/dockerharmony:latest
docker exec -it ohos sh

./build.sh                         # all four regular versions plus 3.14t and 3.15t
./build.sh 3.15.0                  # only the regular 3.15 build
./build.sh 3.15.0+freethreaded     # only the free-threaded 3.15 build
./build.sh 3.15.0 --skip-deps      # repeat a regular build without rebuilding dependencies
```

Third-party dependencies are built once into `.deps/` and shared by every version and variant. Artifacts are written to `dist/`.

## License

The project's original code and patch files are licensed under the BSD Zero Clause License.

Distributed archives contain CPython (PSF-2.0) and third-party libraries. See `python/licenses/` in each archive for their license texts.
