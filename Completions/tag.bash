_tag_finder_tags_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local opts='--list --export --restore --add --append --prepend --remove --set --copy --match --usage --find --move --at --before --after --sorted-tags --sort-tags --reverse --case-sensitive --color --filename --no-filename --name --no-name --tags --no-tags --one-per-line --comma-separated --garrulous --no-garrulous --space-indent --slash --null --nul --absolute --file-info --separator --jsonl --ndjson --tagged-only --stdin --stdin0 --files-from-stdin --files0-from-stdin --all --enter --recursive --descend --no-follow-symlinks --follow-symlinks --dry-run --dryrun --root --backup --no-backup --sync-backup --help --version'
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    else
        COMPREPLY=( $(compgen -f -- "$cur") )
    fi
}
complete -F _tag_finder_tags_complete tag
