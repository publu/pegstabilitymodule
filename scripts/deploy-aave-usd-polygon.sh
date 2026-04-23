#!/usr/bin/env bash
# Deploy AaveUSDPSMV1 on Polygon (chain 137).
#
# Usage:
#   ./scripts/deploy-aave-usd-polygon.sh              # simulates only (no --broadcast)
#   ./scripts/deploy-aave-usd-polygon.sh --broadcast  # simulates + broadcasts + verifies
#
# Env requirements:
#   POLYGON_RPC           — RPC URL for Polygon mainnet (https://...).
#                           drpc.org's public endpoint has been flaky in auth;
#                           prefer Alchemy / 1rpc.io / your own node.
#   ETHERSCAN_API_KEY     — Etherscan V2 unified key (covers Polygon via chainid=137).
#   DEPLOYER_ACCOUNT      — Foundry keystore name (default: deployer).
#                           Must exist — check with `cast wallet list`.
#                           The script will prompt for the keystore password.
#
# The preflight library inside DeployAaveUSDPolygon.s.sol runs before
# vm.startBroadcast, so a bad aToken / pool / MAI wiring aborts on the
# simulation pass without touching the chain.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." &>/dev/null && pwd)
cd "$REPO_ROOT"

# --- flags ---------------------------------------------------------------
BROADCAST=0
for arg in "$@"; do
  case "$arg" in
    --broadcast) BROADCAST=1 ;;
    -h|--help) sed -n '3,22p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# --- color helpers -------------------------------------------------------
if [[ -t 1 ]]; then
  red='\033[0;31m'; green='\033[0;32m'; yellow='\033[0;33m'; dim='\033[0;2m'; rst='\033[0m'
else
  red=''; green=''; yellow=''; dim=''; rst=''
fi
ok()   { printf "${green}✓${rst} %s\n" "$1"; }
warn() { printf "${yellow}!${rst} %s\n" "$1"; }
die()  { printf "${red}✗${rst} %s\n" "$1" >&2; exit 1; }

# --- env check -----------------------------------------------------------
echo "Checking environment..."

: "${POLYGON_RPC:?POLYGON_RPC is required — set it to a working Polygon mainnet RPC}"
: "${ETHERSCAN_API_KEY:?ETHERSCAN_API_KEY is required — set it to your Etherscan V2 unified key}"
DEPLOYER_ACCOUNT="${DEPLOYER_ACCOUNT:-deployer}"

ok "POLYGON_RPC           set (${POLYGON_RPC%%\?*})"
ok "ETHERSCAN_API_KEY     set (length ${#ETHERSCAN_API_KEY})"
ok "DEPLOYER_ACCOUNT      = ${DEPLOYER_ACCOUNT}"

# --- tool check ----------------------------------------------------------
command -v forge >/dev/null || die "forge not on PATH (install Foundry)"
command -v cast  >/dev/null || die "cast not on PATH (install Foundry)"
command -v jq    >/dev/null || warn "jq not on PATH — deploy JSON summary will be skipped"

# `cast wallet list` prints display names with a leading "0x" (e.g., "0xdeployer (Local)"),
# but `--account` requires the name WITHOUT the prefix. Normalize both sides before matching,
# and normalize DEPLOYER_ACCOUNT in case the user pasted the display form.
DEPLOYER_ACCOUNT="${DEPLOYER_ACCOUNT#0x}"
if ! cast wallet list 2>/dev/null | awk '{print $1}' | sed 's/^0x//' | grep -qxF "${DEPLOYER_ACCOUNT}"; then
  die "keystore account '${DEPLOYER_ACCOUNT}' not found. Run: cast wallet import ${DEPLOYER_ACCOUNT} --interactive"
fi
ok "keystore account      exists (will pass as --account ${DEPLOYER_ACCOUNT})"

# --- chain-id sanity check ----------------------------------------------
echo "Probing RPC chain ID..."
CHAIN_ID=$(cast chain-id --rpc-url "$POLYGON_RPC" 2>/dev/null || echo "")
if [[ "$CHAIN_ID" != "137" ]]; then
  die "RPC returned chain id '$CHAIN_ID' — expected 137 (Polygon mainnet). Aborting."
fi
ok "RPC chain id          = 137 (Polygon)"

# --- deploy --------------------------------------------------------------
SCRIPT_PATH="solidity/scripts/DeployAaveUSDPolygon.s.sol"
CONTRACT_NAME="DeployAaveUSDPolygon"
VERIFIER_URL="https://api.etherscan.io/v2/api?chainid=137"

common_args=(
  "$SCRIPT_PATH:$CONTRACT_NAME"
  --rpc-url      "$POLYGON_RPC"
  --account      "$DEPLOYER_ACCOUNT"
  --chain-id     137
  --slow
)

echo
if [[ "$BROADCAST" -eq 0 ]]; then
  printf "${dim}# Simulation only (dry run — pass --broadcast to deploy for real)${rst}\n"
  forge script "${common_args[@]}"
  echo
  ok "Simulation succeeded. Re-run with --broadcast to deploy + verify."
else
  printf "${yellow}! BROADCAST mode — this will deploy to Polygon mainnet and burn gas.${rst}\n"
  read -r -p "Type 'deploy' to continue: " confirm
  [[ "$confirm" == "deploy" ]] || die "Aborted by user."

  forge script "${common_args[@]}" \
    --broadcast \
    --verify \
    --etherscan-api-key "$ETHERSCAN_API_KEY" \
    --verifier-url       "$VERIFIER_URL"

  echo
  ok "Deploy + verify completed."
  BROADCAST_JSON="broadcast/DeployAaveUSDPolygon.s.sol/137/run-latest.json"
  if [[ -f "$BROADCAST_JSON" ]] && command -v jq >/dev/null; then
    PSM_ADDR=$(jq -r '[.transactions[] | select(.transactionType == "CREATE") | .contractAddress] | .[0] // empty' "$BROADCAST_JSON")
    if [[ -n "$PSM_ADDR" ]]; then
      ok "Deployed AaveUSDPSMV1 at: $PSM_ADDR"
      printf "${dim}Fill this into solidity/contracts/AaveUSDPSM/DEPLOYMENTS.md and the SDK constant.${rst}\n"
    fi
  fi
fi
