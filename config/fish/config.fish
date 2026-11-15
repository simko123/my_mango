if status is-interactive
    # Commands to run in interactive sessions can go here
    alias psmem='ps -eo pid,comm,rss,%mem --sort=-rss'
end
