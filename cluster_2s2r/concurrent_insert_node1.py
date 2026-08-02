#!/usr/bin/env python3
import os
import subprocess
import concurrent.futures
from datetime import datetime

CH_CLIENT = os.environ.get("CH_CLIENT", "/root/ClickHouse/build_release/programs/clickhouse-client")
HOST = os.environ.get("CH_HOST", "127.0.0.1")
PORT = int(os.environ.get("CH_PORT", "19100"))
DB = os.environ.get("CH_DB", "default")
TABLE = os.environ.get("CH_TABLE", "mem_metric_test")

JOBS = int(os.environ.get("JOBS", "8"))
ROWS_PER_JOB = int(os.environ.get("ROWS_PER_JOB", "500000"))
ROUNDS = int(os.environ.get("ROUNDS", "10"))
MIN_BLOCK_ROWS = int(os.environ.get("MIN_BLOCK_ROWS", "20000000"))
MIN_BLOCK_BYTES = int(os.environ.get("MIN_BLOCK_BYTES", "4000000000"))


def build_query(job_id: int, round_id: int) -> str:
    offset = (round_id * JOBS + job_id) * ROWS_PER_JOB
    return f"""
SET min_insert_block_size_rows = {MIN_BLOCK_ROWS};
SET min_insert_block_size_bytes = {MIN_BLOCK_BYTES};

INSERT INTO {DB}.{TABLE}
(
    d, ts, id, user_id, session_id, category, region,
    events_cnt, bytes_sum, latency_sum,
    tags, attrs, metrics, arr_vals, `nested.k`, `nested.v`, payload
)
SELECT
    toDate(now()) AS d,
    now64(3) + number AS ts,
    number + {offset} AS id,
    rand() % 100000 AS user_id,
    generateUUIDv4() AS session_id,
    arrayElement(['web', 'mobile', 'api', 'batch'], (rand() % 4) + 1) AS category,
    arrayElement(['CN', 'US', 'JP', 'DE', 'FR'], (rand() % 5) + 1) AS region,
    (rand() % 1000) + 1 AS events_cnt,
    rand() % 1000000 AS bytes_sum,
    rand() % 50000 AS latency_sum,
    ['tag1', 'tag2', 'tag3'] AS tags,
    map('k1', 'v1', 'k2', 'v2') AS attrs,
    tuple(rand() % 100, rand() % 10000, 'label') AS metrics,
    [rand(), rand(), rand(), rand(), rand()] AS arr_vals,
    ['key1', 'key2'] AS `nested.k`,
    ['val1', 'val2'] AS `nested.v`,
    randomPrintableASCII(1024) AS payload
FROM numbers({ROWS_PER_JOB});
""".strip()


def run_job(job_id: int, round_id: int):
    q = build_query(job_id, round_id)
    cmd = [
        CH_CLIENT,
        "--host", HOST,
        "--port", str(PORT),
        "--multiquery",
        "--query", q,
    ]
    start = datetime.now()
    p = subprocess.run(cmd, capture_output=True, text=True)
    elapsed = (datetime.now() - start).total_seconds()
    if p.returncode != 0:
        return round_id, job_id, False, elapsed, p.stderr.strip()
    return round_id, job_id, True, elapsed, p.stdout.strip()


def main():
    print(
        f"Start concurrent inserts: rounds={ROUNDS}, jobs={JOBS}, rows/job={ROWS_PER_JOB}, "
        f"target={HOST}:{PORT} {DB}.{TABLE}"
    )
    failures = 0
    for round_id in range(ROUNDS):
        print(f"--- round {round_id + 1}/{ROUNDS} ---")
        with concurrent.futures.ThreadPoolExecutor(max_workers=JOBS) as ex:
            futs = [ex.submit(run_job, i, round_id) for i in range(JOBS)]
            for fut in concurrent.futures.as_completed(futs):
                finished_round, job_id, ok, elapsed, msg = fut.result()
                if ok:
                    print(f"[OK] round={finished_round + 1} job={job_id} elapsed={elapsed:.2f}s")
                else:
                    failures += 1
                    print(f"[FAIL] round={finished_round + 1} job={job_id} elapsed={elapsed:.2f}s\n{msg}\n")

    if failures:
        raise SystemExit(f"Done with {failures} failed job(s).")
    print("All concurrent inserts finished successfully.")


if __name__ == "__main__":
    main()
