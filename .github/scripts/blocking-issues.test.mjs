import assert from "node:assert/strict";
import test from "node:test";
import {
  blockingConclusion,
  collectAllPages,
  isBlockingIssue,
  latestPullHeads,
  runGate,
} from "./blocking-issues.mjs";

function issue(overrides = {}) {
  return {
    number: 1,
    state: "open",
    title: "example",
    labels: [],
    ...overrides,
  };
}

function makePager(pages) {
  return async (page) => {
    if (page < 1 || page > pages.length) {
      return [];
    }
    return pages[page - 1];
  };
}

test("zero issues is success", () => {
  const result = blockingConclusion([]);
  assert.equal(result.conclusion, "success");
  assert.equal(result.blockers.length, 0);
});

test("ordinary issues are not blocking", () => {
  const result = blockingConclusion([
    issue({ number: 2, labels: [{ name: "bug" }] }),
    issue({ number: 3, pull_request: { url: "https://example.test/pr/3" }, labels: [{ name: "blocking" }] }),
  ]);
  assert.equal(result.conclusion, "success");
});

test("open blocking issue fails", () => {
  const result = blockingConclusion([issue({ labels: ["blocking"] })]);
  assert.equal(result.conclusion, "failure");
  assert.equal(result.blockers[0].number, 1);
});

test("closed blocking issue is ignored", () => {
  const result = blockingConclusion([issue({ state: "closed", labels: [{ name: "blocking" }] })]);
  assert.equal(result.conclusion, "success");
});

test("isBlockingIssue rejects pull requests even with the label", () => {
  assert.equal(
    isBlockingIssue(issue({ pull_request: { url: "x" }, labels: [{ name: "blocking" }] })),
    false,
  );
});

test("second page blocking issue fails", async () => {
  const first = Array.from({ length: 100 }, (_, index) => issue({ number: index + 1, labels: [{ name: "bug" }] }));
  const issues = await collectAllPages(makePager([first, [issue({ number: 101, labels: [{ name: "blocking" }] })]]));
  const result = blockingConclusion(issues);
  assert.equal(issues.length, 101);
  assert.equal(result.conclusion, "failure");
  assert.equal(result.blockers[0].number, 101);
});

test("incomplete page type is an API failure", async () => {
  await assert.rejects(() => collectAllPages(async () => ({ items: [] })), /not an array/);
});

test("reopened blocking issue fails after a closed snapshot succeeded", () => {
  const closed = blockingConclusion([issue({ state: "closed", labels: [{ name: "blocking" }] })]);
  const reopened = blockingConclusion([issue({ state: "open", labels: [{ name: "blocking" }] })]);
  assert.equal(closed.conclusion, "success");
  assert.equal(reopened.conclusion, "failure");
});

test("latest heads ignore cached event sha", async () => {
  const heads = await latestPullHeads(
    async () => [{ number: 9, state: "open", head: { sha: "cached-old" } }],
    async (number) => {
      assert.equal(number, 9);
      return { number: 9, head: { sha: "fresh-new" } };
    },
  );
  assert.deepEqual(heads, [{ number: 9, sha: "fresh-new" }]);
});

test("new push writes only the latest head", async () => {
  const written = [];
  const result = await runGate({
    listPullPage: async () => [{ number: 4, state: "open", head: { sha: "old-head" } }],
    getPull: async () => ({ number: 4, head: { sha: "latest-head" } }),
    listIssuePage: async () => [],
    createCheckRun: async (body) => {
      written.push(body);
      return body;
    },
  });
  assert.equal(result.conclusion, "success");
  assert.deepEqual(
    written.map((body) => body.head_sha),
    ["latest-head"],
  );
  assert.equal(written[0].name, "blocking-issues");
});

test("API error fails and does not treat missing data as zero issues", async () => {
  const written = [];
  await assert.rejects(
    () =>
      runGate({
        listPullPage: async () => [{ number: 8, state: "open", head: { sha: "event-old" } }],
        getPull: async () => ({ number: 8, head: { sha: "head-after-error" } }),
        listIssuePage: async () => {
          throw new Error("GitHub API 500");
        },
        createCheckRun: async (body) => {
          written.push(body);
          return body;
        },
      }),
    /GitHub API 500/,
  );
  assert.equal(written.length, 1);
  assert.equal(written[0].head_sha, "head-after-error");
  assert.equal(written[0].conclusion, "failure");
});

test("blocking issue writes failure to every open pull head", async () => {
  const written = [];
  const result = await runGate({
    listPullPage: async () => [
      { number: 10, state: "open" },
      { number: 11, state: "open" },
    ],
    getPull: async (number) => ({ number, head: { sha: `sha-${number}` } }),
    listIssuePage: async () => [issue({ number: 77, labels: [{ name: "blocking" }], title: "blocker" })],
    createCheckRun: async (body) => {
      written.push(body);
      return body;
    },
  });
  assert.equal(result.conclusion, "failure");
  assert.deepEqual(
    written.map((body) => body.head_sha).sort(),
    ["sha-10", "sha-11"],
  );
  assert.equal(written.every((body) => body.conclusion === "failure"), true);
});
