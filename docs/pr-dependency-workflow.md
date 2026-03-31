# PR Dependency Workflow Documentation

## Overview

The [`github_actions_dependencies.yml`](.github/workflows/github_actions_dependencies.yml) workflow uses [a third party GitHub action](https://github.com/marketplace/actions/pr-dependency-check) to enforce PR dependencies.

At the time of writing, the GitHub action supported the following styles, for both issues and PRs.:

- Quick Link: `#5`
- Partial Link: `gregsdennis/dependencies-action#5`
- Partial URL: `gregsdennis/dependencies-action/pull/5`
- Full URL: `https://github.com/gregsdennis/dependencies-action/pull/5`
- Markdown: `[markdown link](https://github.com/gregsdennis/dependencies-action/pull/5)`

## Usage

Add the following to a `.yaml` file in your `.github/workflows` directory:

```
name: Check for GitHub Actions Dependencies in PR

on:
  pull_request_target:
    types: [opened, edited, reopened, labeled, unlabeled, synchronize]

permissions:
  issues: read
  pull-requests: read

jobs:
  check_dependencies:
     uses: swiftlang/github-workflows/.github/workflows/github_actions_dependencies.yml.yml@<to-be-updated>
```
