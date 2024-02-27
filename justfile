# recipes for the `just` command runner: https://just.systems
# how to install: https://github.com/casey/just#packages

# we load all vars from .env file into the env of just commands
set dotenv-load
# and export just vars as env vars
set export

## Main configs - override these using env vars

## Configure just
# choose shell for running recipes
set shell := ["bash", "-uc"]
# support args like $1, $2, etc, and $@ for all args
set positional-arguments


#### COMMANDS ####

help:
    @echo "Just commands:"
    @just --list

compile:
    mix compile

clean:
    mix deps.clean --all
    rm -rf .hex .mix .cache

deps-get:
    mix deps.get

deps-update:
    mix deps.update --all

test:
    mix test

@release-increment version:
    sed -i -E 's/version: "(.*)",$/version: "{{version}}",/' mix.exs

release version: (release-increment version)
   git add mix.exs
   git commit -m 'Release v{{version}}'
   git tag v{{version}}

push-release version: (release version)
    git push
    git push --tags
