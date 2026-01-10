#!/usr/bin/env python3
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2026 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

import argparse
import json
import subprocess
from datetime import datetime, timedelta, timezone

argparse = argparse.ArgumentParser()
argparse.add_argument(
    "--stale-duration",
    required=True,
    help="Number of weeks after which a PR is considered stale"
)
argparse.add_argument(
    "--repo",
    required=True,
    help="Repo in which to check for stale PRs, eg. swiftlang/swift-syntax"
)
argparse.add_argument(
    "--dry-run",
    action="store_true",
    help="Repo in which to check for stale PRs, eg. swiftlang/swift-syntax"
)
args = argparse.parse_args()

stale_duration_weeks = int(args.stale_duration)
repo = str(args.repo)
dry_run = bool(args.dry_run)

stale_date = datetime.now(timezone.utc) - timedelta(weeks=stale_duration_weeks)

command = [
    "gh", "pr", "list", "-R", repo, "--search",
    f"updated:<{stale_date.isoformat()} draft:false is:pr is:open",
    "--json", "author,comments,commits,number,reviewDecision,reviewRequests,reviews,url"
]
prs = json.loads(subprocess.check_output(command, encoding="utf-8"))

distant_past = datetime.fromtimestamp(0, timezone.utc)


def user_has_write_access(user: str) -> bool:
    output = subprocess.check_output(
        ["gh", "api", f"repos/{repo}/collaborators/{user}/permission"],
        encoding="utf-8"
    )
    return json.loads(output)["permission"] in ["write", "push", "admin"]


def print_command(command: list[str]) -> None:
    print(" ".join([f"'{arg}'" if " " in arg else arg for arg in command]))


for pr in prs:
    pr_author = pr["author"]["login"]

    # Filter out reviews from users who aren't affiliated with the repository
    relevant_reviews = [
        review for review in pr["reviews"]
        if review["authorAssociation"] in ["COLLABORATOR", "MEMBER", "OWNER"]
    ]
    reviewers = [review_request["login"] for review_request in pr["reviewRequests"]]
    reviewers.extend([review["author"]["login"] for review in relevant_reviews])

    reviewer_interaction_dates: list[str] = []
    reviewer_interaction_dates.extend(
        [review["submittedAt"] for review in relevant_reviews]
    )
    reviewer_interaction_dates.extend([
        comment["createdAt"] for comment in pr["comments"]
        if comment["author"]["login"] in reviewers
        if "@swift-ci" not in comment["body"]
    ])

    author_interaction_dates: list[str] = []
    author_interaction_dates.extend(
        [commit["authoredDate"] for commit in pr["commits"]]
    )
    author_interaction_dates.extend(
        [commit["committedDate"] for commit in pr["commits"]]
    )
    author_interaction_dates.extend([
        comment["createdAt"] for comment in pr["comments"]
        if comment["author"]["login"] == pr_author
        if "@swift-ci" not in comment["body"]
    ])

    if reviewer_interaction_dates:
        last_reviewer_interaction_date = datetime.fromisoformat(
            max(reviewer_interaction_dates).replace("Z", "+00:00")
        )
    else:
        last_reviewer_interaction_date = distant_past

    if author_interaction_dates:
        last_author_interaction_date = datetime.fromisoformat(
            max(author_interaction_dates).replace("Z", "+00:00")
        )
    else:
        last_author_interaction_date = distant_past

    comment = f"This PR has not been modified for {stale_duration_weeks} weeks. "
    reviewers.sort()
    joined_reviewers = ", ".join(["@" + r for r in reviewers])
    reviewers_ping = joined_reviewers or "Code Owners of this repository"
    if pr["reviewDecision"] == "APPROVED":
        if user_has_write_access(pr_author):
            comment += (
                f"{pr_author} given this PR has an approving review, "
                "please try and merge the PR. Should the PR be no longer "
                "relevant, please close it. Should you take more time to "
                "work on it, please mark it as draft to disable these "
                "notifications.."
            )
        else:
            comment += (
                f"{reviewers_ping} given this PR has an approving review "
                "but the author does not have merge access, please help "
                "the author to make the PR pass CI checks and get it "
                "merged."
            )
    elif last_author_interaction_date < last_reviewer_interaction_date:
        comment += (
            f"@{pr_author} to help move this PR forward, please address "
            "the review feedback. Should the PR be no longer relevant, "
            "please close it. Should you take more time to work on it, "
            "please mark it as draft to disable these notifications."
        )
    else:
        comment += (
            f"{reviewers_ping} to help move this PR forward, "
            "please review it."
        )

    add_comment_command = [
        "gh", "pr",
        "-R", repo,
        "comment", str(pr["number"]),
        "--body", comment
    ]
    if dry_run:
        print_command(add_comment_command)
    else:
        subprocess.check_call(add_comment_command)
