# ref'ju:geeks Welcome 2020 – lancache setup scripts

This repository contains setup scripts for our little LAN party's [lancache](https://lancache.net) server.

## What's here?

* `setup.sh` is meant to execute all steps to go from a bare-bones Ubuntu 20.04 server to running lancache containers.
* `teardown.sh` stops and removes the created lancache docker containers, e.g. for a config change. The lancache data
  directories remain untouched in this operation, and the containers can simply be re-created using `setup.sh`.
