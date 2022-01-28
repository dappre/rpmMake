# rpmMake

Create RPM packages from spec file using Docker container

## Requirements
This project relies on Docker to handle dependencies to build and package the software from source. It also provides support for docker-composer:

- Docker (18.09.1+)
- Docker Composer (1.21.0+)

## Setup
In order to use rpmMake to package a software:
- Create a dedicated repository
- Provides valid spec and changelog files under `rpm` folder as follow:

```
rpm
  changelog
  spec.in
  subpackage.spec.in   # optional
```

- Add this repo as a submodule:

```
git submodule add --branch stable ssh://git@github.com/digital-me/rpmMake.git rpmMake
```

- Create a Makefile base on the provided [example](Makefile.example) and change at least the NAME, PACKAGER and VENDOR
- Copy (or symlink) the Docker [compose](docker-compose.yml) file
- Copy (or symlink) the [lazyDir](resources/lazyDir) folder (to provide the right Docker context to Jenkins pipeline)
- If the current user id and group id are not 1000, it is required to define them using environment variables:

```
export _UID="$(id -u)"
export _GID="$(id -g)"
```

- Build the container image:

```
docker-compose build $OS_LABEL
```

  Where OS_LABEL can take any supported value:
  - centos7

## Usage
- Start a bash sessions inside the container:

```
docker-compose --compatibility run \
--rm \
$OS_LABEL
```

- Build the rpm package by replacing the version and (optional) release in the following command:

```
make VERSION=x.x.x RELEASE=y.y
```
