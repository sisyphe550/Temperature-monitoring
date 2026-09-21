#!/usr/bin/env node
/**
 * Trusted-default-branch gate. Enumerates open issues and writes a uniquely
 * named check to every open PR's latest head. Never executes pull-request code.
 */

import { fileURLToPath } from "node:url";

export const CHECK_NAME = "blocking-issues";
export const BLOCKING_LABEL = "blocking";
const PER_PAGE = 100;
const PAGE_LIMIT = 100;

export function isBlockingIssue(issue) {
  if (!issue || issue.pull_request) {
    return false;
  }
  if (issue.state !== "open") {
    return false;
  }
  const labels = Array.isArray(issue.labels) ? issue.labels : [];
  return labels.some((label) => {
    const name = typeof label === "string" ? label : label?.name;
    return name === BLOCKING_LABEL;
  });
}

export async function collectAllPages(fetchPage) {
  const items = [];
  for (let page = 1; page <= PAGE_LIMIT; page += 1) {
    const batch = await fetchPage(page);
    if (!Array.isArray(batch)) {
      throw new Error("GitHub API page is not an array");
    }
    items.push(...batch);
    if (batch.length < PER_PAGE) {
      return items;
    }
  }
  throw new Error("GitHub API pagination exceeded safety limit");
}

export function blockingConclusion(issues) {
  const blockers = issues.filter(isBlockingIssue);
  return {
    blockers,
    conclusion: blockers.length === 0 ? "success" : "failure",
  };
}

export async function latestPullHeads(listPullPage, getPull) {
  const pulls = await collectAllPages(listPullPage);
  const heads = [];
  for (const pull of pulls) {
    if (!pull || pull.state && pull.state !== "open") {
      continue;
    }
    const number = pull.number;
    const fresh = await getPull(number);
    const sha = fresh?.head?.sha;
    if (typeof sha !== "string" || sha.length === 0) {
      throw new Error(`missing head sha for PR #${number}`);
    }
    heads.push({ number, sha });
  }
  return heads;
}

export function checkOutput(conclusion, blockers) {
  if (conclusion === "success") {
    return {
      title: "No blocking issues",
      summary: "No open issues with the blocking label.",
    };
  }
  const list = blockers.map((issue) => `#${issue.number} ${issue.title ?? ""}`.trim()).join("\n");
  return {
    title: "Blocking issues open",
    summary: `Open blocking issues must be resolved before merge:\n${list}`,
  };
}

export async function writeChecks(createCheckRun, heads, conclusion, blockers) {
  const output = checkOutput(conclusion, blockers);
  for (const head of heads) {
    await createCheckRun({
      name: CHECK_NAME,
      head_sha: head.sha,
      status: "completed",
      conclusion,
      output,
    });
  }
}

export async function runGate(api) {
  let heads = [];
  try {
    heads = await latestPullHeads(api.listPullPage, api.getPull);
    const issues = await collectAllPages(api.listIssuePage);
    const { blockers, conclusion } = blockingConclusion(issues);
    await writeChecks(api.createCheckRun, heads, conclusion, blockers);
    return { conclusion, heads, blockers };
  } catch (error) {
    if (heads.length > 0) {
      try {
        await writeChecks(api.createCheckRun, heads, "failure", [
          { number: 0, title: `API error: ${error.message}` },
        ]);
      } catch {
        // Preserve the original API failure if status write also fails.
      }
    }
    throw error;
  }
}

export function githubApi({ token, repository, fetchImpl = fetch }) {
  if (!token) {
    throw new Error("GITHUB_TOKEN is required");
  }
  if (!repository || !repository.includes("/")) {
    throw new Error("GITHUB_REPOSITORY must be owner/repo");
  }
  const [owner, repo] = repository.split("/");

  async function gh(path, init = {}) {
    const response = await fetchImpl(`https://api.github.com${path}`, {
      ...init,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
        ...(init.headers ?? {}),
      },
    });
    if (!response.ok) {
      const body = await response.text();
      throw new Error(`GitHub API ${init.method ?? "GET"} ${path} ${response.status}: ${body.slice(0, 300)}`);
    }
    if (response.status === 204) {
      return null;
    }
    return response.json();
  }

  return {
    listIssuePage(page) {
      return gh(`/repos/${owner}/${repo}/issues?state=open&per_page=${PER_PAGE}&page=${page}`);
    },
    listPullPage(page) {
      return gh(`/repos/${owner}/${repo}/pulls?state=open&per_page=${PER_PAGE}&page=${page}`);
    },
    getPull(number) {
      return gh(`/repos/${owner}/${repo}/pulls/${number}`);
    },
    createCheckRun(body) {
      return gh(`/repos/${owner}/${repo}/check-runs`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
    },
  };
}

export async function main(env = process.env) {
  const api = githubApi({
    token: env.GITHUB_TOKEN,
    repository: env.GITHUB_REPOSITORY,
  });
  const result = await runGate(api);
  if (result.conclusion !== "success") {
    console.error(checkOutput(result.conclusion, result.blockers).summary);
    process.exitCode = 1;
    return result;
  }
  console.log(`blocking-issues success for ${result.heads.length} pull request head(s)`);
  return result;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
