#!/bin/bash
# Pi Harness v2.0 -- Setup Script
# Run on any machine (macOS or Linux). Supports:
#   - LiteLLM proxy
#   - Anthropic direct (Claude Max plan)
#   - OpenAI direct (OpenAI Pro plan / Codex free tier)
#   - omp (oh-my-pi) for structured review output
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"

echo "=== Pi Harness v2.0 Setup ==="
echo "Source: $HARNESS_DIR"
echo ""

# 1. Install Pi and/or omp
HAS_PI=false
HAS_OMP=false

if command -v pi &>/dev/null; then
  HAS_PI=true
  echo "[1/6] Pi already installed: $(pi --version 2>/dev/null | head -1)"
else
  echo "[1/6] Installing Pi coding agent..."
  if command -v bun &>/dev/null; then
    bun install -g @mariozechner/pi-coding-agent
    HAS_PI=true
  elif command -v npm &>/dev/null; then
    npm install -g @mariozechner/pi-coding-agent
    HAS_PI=true
  else
    echo "  WARN: Need bun or npm to install Pi. Skipping."
  fi
fi

if command -v omp &>/dev/null; then
  HAS_OMP=true
  echo "[2/6] omp already installed: $(omp --version 2>/dev/null | head -1)"
else
  echo "[2/6] Installing omp (oh-my-pi) for structured reviews..."
  if command -v bun &>/dev/null; then
    bun install -g @oh-my-pi/pi-coding-agent
    HAS_OMP=true
  else
    echo "  WARN: Need bun to install omp. Skipping (Pi fallback will be used)."
  fi
fi

if ! $HAS_PI && ! $HAS_OMP; then
  echo "ERROR: Neither Pi nor omp could be installed. Need bun or npm."
  exit 1
fi

# Set up omp agents if omp was installed
if $HAS_OMP; then
  echo "  Unpacking omp bundled agents..."
  omp agents unpack 2>/dev/null || true
fi

# 3. Detect provider setup
echo "[3/6] Detecting provider setup..."
HAS_LITELLM=false
HAS_ANTHROPIC=false
HAS_OPENAI=false

if [[ -f "${HOME}/.pi/agent/models.json" ]] && grep -q '"litellm"' "${HOME}/.pi/agent/models.json" 2>/dev/null; then
  HAS_LITELLM=true
  echo "  Found: LiteLLM provider in ~/.pi/agent/models.json"
fi
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  HAS_ANTHROPIC=true
  echo "  Found: ANTHROPIC_API_KEY in environment"
fi
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  HAS_OPENAI=true
  echo "  Found: OPENAI_API_KEY in environment"
fi

if ! $HAS_LITELLM && ! $HAS_ANTHROPIC && ! $HAS_OPENAI; then
  echo ""
  echo "  No providers detected. You need at least one:"
  echo "    - ANTHROPIC_API_KEY (Claude Max plan)"
  echo "    - OPENAI_API_KEY (OpenAI Pro plan or Codex free)"
  echo "    - LiteLLM config in ~/.pi/agent/models.json"
  echo ""
  echo "  Set API keys in your shell profile, then re-run this script."
fi

# Sync models.json to omp if it uses LiteLLM
if $HAS_OMP && $HAS_LITELLM; then
  mkdir -p "${HOME}/.omp/agent"
  if [[ ! -f "${HOME}/.omp/agent/models.json" ]]; then
    cp "${HOME}/.pi/agent/models.json" "${HOME}/.omp/agent/models.json"
    echo "  Synced LiteLLM config to ~/.omp/agent/models.json"
  fi
fi

# 4. Generate harness config
echo "[4/6] Generating harness config..."
mkdir -p "${HOME}/.config/pi-harness"
CONFIG_FILE="${HOME}/.config/pi-harness/config"

if [[ -f "$CONFIG_FILE" ]]; then
  echo "  Config already exists at $CONFIG_FILE -- skipping"
  echo "  Delete it to regenerate: rm $CONFIG_FILE"
else
  if $HAS_LITELLM && $HAS_OPENAI; then
    cat > "$CONFIG_FILE" << 'CONF'
# Pi Harness config -- LiteLLM + OpenAI (Codex)
PI_HARNESS_MODEL_PRIMARY="litellm/opus-nocache"
PI_HARNESS_MODEL_SECONDARY="openai/gpt-5.5"
PI_HARNESS_MODELS="${PI_HARNESS_MODEL_PRIMARY},${PI_HARNESS_MODEL_SECONDARY}"
CONF
    echo "  Generated: LiteLLM + OpenAI config"
  elif $HAS_ANTHROPIC && $HAS_OPENAI; then
    cat > "$CONFIG_FILE" << 'CONF'
# Pi Harness config -- Anthropic direct + OpenAI direct
PI_HARNESS_MODEL_PRIMARY="anthropic/claude-opus-4-6"
PI_HARNESS_MODEL_SECONDARY="openai/gpt-5.5"
PI_HARNESS_MODELS="${PI_HARNESS_MODEL_PRIMARY},${PI_HARNESS_MODEL_SECONDARY}"
CONF
    echo "  Generated: Anthropic + OpenAI config"
  elif $HAS_ANTHROPIC; then
    cat > "$CONFIG_FILE" << 'CONF'
# Pi Harness config -- Anthropic direct only
PI_HARNESS_MODEL_PRIMARY="anthropic/claude-opus-4-6"
PI_HARNESS_MODEL_SECONDARY="anthropic/claude-sonnet-4-6"
PI_HARNESS_MODELS="${PI_HARNESS_MODEL_PRIMARY},${PI_HARNESS_MODEL_SECONDARY}"
CONF
    echo "  Generated: Anthropic-only config"
  elif $HAS_OPENAI; then
    cat > "$CONFIG_FILE" << 'CONF'
# Pi Harness config -- OpenAI direct only
PI_HARNESS_MODEL_PRIMARY="openai/gpt-5.5"
PI_HARNESS_MODEL_SECONDARY="openai/gpt-5.3-codex"
PI_HARNESS_MODELS="${PI_HARNESS_MODEL_PRIMARY},${PI_HARNESS_MODEL_SECONDARY}"
CONF
    echo "  Generated: OpenAI-only config"
  elif $HAS_LITELLM; then
    cat > "$CONFIG_FILE" << 'CONF'
# Pi Harness config -- LiteLLM only
PI_HARNESS_MODEL_PRIMARY="litellm/opus-nocache"
PI_HARNESS_MODEL_SECONDARY="litellm/pro-nocache"
PI_HARNESS_MODELS="${PI_HARNESS_MODEL_PRIMARY},${PI_HARNESS_MODEL_SECONDARY}"
CONF
    echo "  Generated: LiteLLM-only config"
  else
    echo "  Skipped -- no providers detected. Configure manually."
  fi
fi

# 5. Link scripts to PATH
echo "[5/6] Linking harness scripts..."
mkdir -p ~/.local/bin

# Handle both repo layout (pi-review/pi-review) and bundle layout (scripts/pi-review)
for script in pi-review pi-verify pi-swarm; do
  SCRIPT_PATH=""
  if [[ -f "$HARNESS_DIR/scripts/$script" ]]; then
    SCRIPT_PATH="$HARNESS_DIR/scripts/$script"
  elif [[ -f "$HARNESS_DIR/$script/$script" ]]; then
    SCRIPT_PATH="$HARNESS_DIR/$script/$script"
  fi
  if [[ -n "$SCRIPT_PATH" ]]; then
    chmod +x "$SCRIPT_PATH"
    ln -sf "$SCRIPT_PATH" ~/.local/bin/$script
    echo "  linked: $script -> $SCRIPT_PATH"
  else
    echo "  WARN: $script not found in $HARNESS_DIR"
  fi
done

# 6. Verify
echo "[6/6] Verifying..."
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo "  WARNING: ~/.local/bin not in PATH. Add to your shell profile:"
  echo '  export PATH="$HOME/.local/bin:$PATH"'
fi

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE" 2>/dev/null || true
  echo "  Primary model:   ${PI_HARNESS_MODEL_PRIMARY:-not set}"
  echo "  Secondary model: ${PI_HARNESS_MODEL_SECONDARY:-not set}"
fi

echo "  Review engine:   $($HAS_OMP && echo "omp (structured P0-P3)" || echo "pi (fallback prompts)")"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Quick test:"
if $HAS_OMP; then
  echo "  omp -p 'hello' --model opus --no-tools --no-session"
elif $HAS_ANTHROPIC; then
  echo "  pi -p 'hello' --provider anthropic --model claude-sonnet-4-6 --no-tools"
elif $HAS_LITELLM; then
  echo "  pi -p 'hello' --provider litellm --model sonnet-nocache --no-tools"
elif $HAS_OPENAI; then
  echo "  pi -p 'hello' --provider openai --model gpt-5.5 --no-tools"
fi
echo ""
echo "Commands:"
echo "  pi-review [persona]            # Cross-model review (2 models in parallel)"
echo "  pi-verify                      # Independent post-build verification"
echo "  pi-swarm                       # Full 4-persona x 2-model parallel swarm"
echo "  pi-swarm --quick               # Fast 2-persona x 2-model review"
echo "  pi-swarm --branch              # Review full branch vs default branch"
echo "  pi-swarm --files 'src/*.ts'    # Full-file review (not diff-based)"
echo ""
echo "Config: $CONFIG_FILE"
echo "Edit to change models: PI_HARNESS_MODEL_PRIMARY, PI_HARNESS_MODEL_SECONDARY"
