# fish completion for vdl
# Install as ~/.config/fish/completions/vdl.fish

complete -c vdl -s h -l help -d 'Show help'
complete -c vdl -s V -l version -d 'Show version'

complete -c vdl -s b -l browser -x \
    -a 'vivaldi firefox brave chromium chrome edge opera safari whale none' \
    -d 'Browser to take cookies from (default: auto-detect)'
complete -c vdl -s n -l no-cookies -d 'Do not read browser cookies'

complete -c vdl -s q -l quality -x \
    -a '360 480 720 1080 1440 2160 2k 4k' \
    -d 'Max video height (default: 1080)'

complete -c vdl -s a -l audio -d 'Audio only as MP3 (320k)'

complete -c vdl -s i -l batch-file -r -F -d 'Read URLs from a .txt file'

complete -c vdl -l no-aria -d 'Do not use aria2c'
complete -c vdl -l no-impersonate -d 'Disable browser impersonation'
complete -c vdl -l referer -r -d 'Send this Referer header'
complete -c vdl -l user-agent -r -d 'Send this User-Agent header'
complete -c vdl -l proxy -r -d 'Route downloads through this proxy'

complete -c vdl -a '(__fish_complete_suffix .txt)' -d 'URL list'
