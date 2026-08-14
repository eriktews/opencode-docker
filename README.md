# Opencode Docker container

This repository provides a Dockerfile for an Opencode Docker container mainly for Rust development and with support for docker-in-docker without bind-mounting the host Docker daemon socket.

Feel free to adopt it and use it at your own risk and feel free to provide feedback.

## Build

To build the opencode image, just run:

```bash
docker build -t opencode .
```

When you want to build it again and mare sure it picks up the latest version of Opencode, run:

```bash
docker build --no-cache-filter opencode -t opencode .
```

## Run

Once after system start, load the apparmour profile:

```bash
sudo apparmor_parser -r -W podman-nested.apparmor
```

Then to start coding, run:

```bash
docker run --rm -it   --workdir /workspace   --volume "$HOME/path-to-your-project:/workspace"   --volume "$HOME/.config/opencode:/home/op/.config/opencode"  --volume "$HOME/.local/share/opencode:/home/op/.local/share/opencode" --volume "$HOME/.local/state/opencode:/home/op/.local/state/opencode" --volume "$HOME/.gitconfig:/home/op/.gitconfig:ro" --security-opt seccomp=$HOME/path-to-this-repository/seccomp-profile.json  --security-opt apparmor=podman-nested   --name opencode-test --cap-add SETUID --cap-add SETGID --cap-add SYS_ADMIN --device /dev/net/tun --net=host opencode  opencode
```