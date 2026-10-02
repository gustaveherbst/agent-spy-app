#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLI="${ROOT_DIR}/.build/release/agenttask"
DAEMON="${ROOT_DIR}/.build/release/agenttaskd"

DEMO_SOCK="/tmp/agentspy_demo.sock"
DEMO_DB="/tmp/agentspy_demo.db"

export AGENTTASK_SOCKET_PATH="${DEMO_SOCK}"
export AGENTTASK_DB_PATH="${DEMO_DB}"

echo "=========================================================="
echo "    AgentSpy / Agent Task Monitor — Demo Verification Flow"
echo "=========================================================="
echo "Cleaning up any existing demo state..."
rm -f "${DEMO_SOCK}" "${DEMO_DB}" "${DEMO_DB}-wal" "${DEMO_DB}-shm"

echo "1. Starting background daemon agenttaskd (socket: ${DEMO_SOCK}, grace: 2.0s)..."
"${DAEMON}" --socket "${DEMO_SOCK}" --db "${DEMO_DB}" --polling 0.5 --grace 2.0 &
DAEMON_PID=$!

cleanup() {
    echo "Stopping background daemon (PID ${DAEMON_PID})..."
    kill -TERM "${DAEMON_PID}" 2>/dev/null || true
    rm -f "${DEMO_SOCK}" "${DEMO_DB}"
}
trap cleanup EXIT

# Wait for daemon to be ready
sleep 0.5

echo "2. Registering session 'Claude / Demo'..."
SESSION_JSON=$("${CLI}" session start --agent claude --project "$HOME/dev/demo-project" --title "Feature Implementation Run" --json)
SESSION_ID=$(echo "${SESSION_JSON}" | sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p')
echo "   -> Session ID: ${SESSION_ID}"

echo "3. Creating root task 'Implement Feature'..."
ROOT_JSON=$("${CLI}" start --session "${SESSION_ID}" --title "Implement Feature" --project "$HOME/dev/demo-project" --json)
ROOT_ID=$(echo "${ROOT_JSON}" | sed -n 's/.*"task_id":"\([^"]*\)".*/\1/p')
echo "   -> Root Task ID: ${ROOT_ID}"

echo "4. Creating children 'Build dataset', 'Train 800 steps', 'Evaluate'..."
CHILD1_JSON=$("${CLI}" start --session "${SESSION_ID}" --parent "${ROOT_ID}" --title "Build dataset" --json)
CHILD1_ID=$(echo "${CHILD1_JSON}" | sed -n 's/.*"task_id":"\([^"]*\)".*/\1/p')

CHILD2_JSON=$("${CLI}" start --session "${SESSION_ID}" --parent "${ROOT_ID}" --title "Train 800 steps" --json)
CHILD2_ID=$(echo "${CHILD2_JSON}" | sed -n 's/.*"task_id":"\([^"]*\)".*/\1/p')

CHILD3_JSON=$("${CLI}" start --session "${SESSION_ID}" --parent "${ROOT_ID}" --title "Evaluate" --json)
CHILD3_ID=$(echo "${CHILD3_JSON}" | sed -n 's/.*"task_id":"\([^"]*\)".*/\1/p')

echo "   -> Subtask 1: Build dataset (${CHILD1_ID})"
echo "   -> Subtask 2: Train 800 steps (${CHILD2_ID})"
echo "   -> Subtask 3: Evaluate (${CHILD3_ID})"

echo "5. Marking 'Build dataset' succeeded..."
"${CLI}" done "${CHILD1_ID}" --summary "Dataset generated (12,400 samples)"

echo "6. Setting 'Train 800 steps' progress to 63% (504/800 steps)..."
"${CLI}" progress "${CHILD2_ID}" --fraction 0.63 --completed 504 --total 800 --message "Training step 504/800"

echo ""
echo "--- Current Task Hierarchy & Status ---"
"${CLI}" status "${ROOT_ID}"
echo ""

echo "7. Creating task with bound background sample process (PID) to test liveness loss..."
sleep 1000 &
SAMPLE_PID=$!

BOUND_JSON=$("${CLI}" start --session "${SESSION_ID}" --title "Worker Process" --pid "${SAMPLE_PID}" --json)
BOUND_ID=$(echo "${BOUND_JSON}" | sed -n 's/.*"task_id":"\([^"]*\)".*/\1/p')
echo "   -> Worker Task ID: ${BOUND_ID} bound to PID: ${SAMPLE_PID}"

echo "8. Killing sample worker process without sending ATP completion..."
kill -9 "${SAMPLE_PID}"
echo "   -> Sample process ${SAMPLE_PID} killed."

echo "9. Waiting for daemon to detect process loss and reconcile after grace period (2.5s)..."
sleep 3.0

echo ""
echo "--- Verifying Reconciled State for Lost Process Task ---"
"${CLI}" status "${BOUND_ID}"

echo ""
echo "10. All Active and Historical Tasks in Registry:"
"${CLI}" list

echo ""
echo "=========================================================="
echo "    Verification Flow Successfully Completed!"
echo "=========================================================="
