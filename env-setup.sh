# env-setup.sh

_smos_dev_setup() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    if [[ ":$PATH:" != *":$script_dir:"* ]]; then
        export PATH="$script_dir:$PATH"
    fi

    if [[ -f "$script_dir/smos-dev-completion.bash" ]]; then
        source "$script_dir/smos-dev-completion.bash"
    fi
}

_smos_dev_setup
unset -f _smos_dev_setup
