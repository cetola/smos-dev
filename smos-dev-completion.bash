# smos-dev-completion.bash

_smos_dev_completions() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    opts="--work --profile --runtime --network --proxy --cfile --help -h"

    case "$prev" in
        --runtime)
            COMPREPLY=( $(compgen -W "docker podman auto" -- "$cur") )
            return 0
            ;;
        --network)
            COMPREPLY=( $(compgen -W "default none proxy-only" -- "$cur") )
            return 0
            ;;
        --work|--cfile)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
        --profile)
            local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/smos-dev"
            if [[ -d "$state_dir" ]]; then
                local profiles
                profiles=$(find "$state_dir" -maxdepth 1 -name "*.runtime" -printf "%f\n" | sed 's/\.runtime//' | sort -u)
                COMPREPLY=( $(compgen -W "$profiles" -- "$cur") )
            fi
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi
}

complete -F _smos_dev_completions smos-dev.sh
