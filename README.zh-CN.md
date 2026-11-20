<div align="center">
<p><a href="README.md">English</a> | 简体中文</p>
</div>

# ohos-python

面向 OpenHarmony 的独立 CPython 发行版，定位类似于 [astral-sh/python-build-standalone](https://github.com/astral-sh/python-build-standalone)：在 Release 中提供解压即用的 Python 制品，并附带可被 uv 用作下载源的元数据。

## 下载与安装

以 CPython 3.15.0 为例：

```sh
curl -fLO https://github.com/ohos-python/ohos-python/releases/download/20261120/cpython-3.15.0%2B20261120-aarch64-unknown-linux-ohos-install_only.tar.gz
# 中国大陆用户可使用 AtomGit 镜像加速下载：
# curl -fLO https://atomgit.com/ohos-python/ohos-python/releases/download/20261120/cpython-3.15.0%2B20261120-aarch64-unknown-linux-ohos-install_only.tar.gz

tar -zxf cpython-*.tar.gz -C "$HOME"
export PATH="$HOME/python/bin:$PATH"
python3 --version
```

## 配合 uv 使用

如需使用 uv 安装和管理本项目的 CPython 解释器，请参阅 [ohos-uv](https://github.com/ohos-python/ohos-uv)。

## 自行构建

需要一台能跑[鸿蒙容器](https://github.com/hqzing/dockerharmony)的 aarch64 Linux 主机：

```sh
git clone https://github.com/ohos-python/ohos-python.git
cd ohos-python

docker run -dit --name ohos \
  -v "$PWD":/workdir -w /workdir \
  ghcr.io/hqzing/dockerharmony:latest
docker exec -it ohos sh

./build.sh                         # 四个普通版本，以及 3.14t 和 3.15t
./build.sh 3.15.0                  # 只构建 3.15 普通版
./build.sh 3.15.0+freethreaded     # 只构建 3.15 free-threaded 版
./build.sh 3.15.0 --skip-deps      # 重复构建普通版时不重新编译依赖
```

第三方依赖只编译一次到 `.deps/`，由所有 Python 版本和变体共享。产物位于 `dist/`。

## License

本项目自身编写的代码及补丁文件采用 BSD Zero Clause License。

制品内含 CPython（PSF-2.0）与各第三方库，相关许可文本见制品内 `python/licenses/`。
