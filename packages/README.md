# My Package Collection 🍱

These are mostly uninteresting scripts, but I find them useful. Feel
free to pillage!

## Interesting Scripts 🤯

### [notify](./notify)

Cross platform notifier. MacOS has fun quirk of messing with your
notifications if you don't provide a title. It ignores the body you
provide it, and sets it as the title and looks awful. `notify` reaches
out to [xav-ie/generate-kaomoji](https://github.com/xav-ie/generate-kaomoji) to generate a title if you don't
provide one :).

### [searcher](./searcher)

Nixpkgs searching script with fzf. Lets you easily search and enter
shell of a package without having to look it up on nixpkgs search.

### [zellij-tab-name-update](./zellij-tab-name-update)

Automatically update the zellij tab name based on the current git
directory you are in.

You basically just run this as a `preCmd` or `PROMPT_COMMAND` script so it
has chance to run every time you change directories.

## Not-So Interesting Scripts 😴

### [cache-command](./cache-command)

Cache the output of a command based on the command and arguments passed.
Like redis but for cli commands. Current timeout is 1hr. It still needs
some work, but it is really useful for fzf scripts where the preview
takes a long time to generate.

### [ff](./ff)

fzf files on command line.

### [g](./g)

fzf powered git log. Allows you to browse git commit history with
preview of diff.

Broken: Still working on nixifying this properly.

### [is-sshed](./is-sshed)

Check if there is someone currently ssh-ed into system. Useful for
showing/not-showing certain terminal stuff.

### [jira-task-list](./jira-task-list)

List Jira tasks, but fancier?

### [move-active](./move-active)

Move active window to corner (accounting for borders, gaps, and bar) on hyprland.

### [nvim](./nvim)

I mainly have this because some programs don't respect an alias to
nvim, and look for a binary named nvim instead. This simply invokes the
nvim I have on my system. There is a number of reasons I don't want to
pair my editor config with my system:

1.  Makes system and editor builds longer.
2.  Makes the nvim config easier to discover and use for myself and
    others.
3.  They are just different projects. Including editor configuration
    would cause this to become a beast.

### [record-section](./record-section)

Records screen with preferred settings.

### [record](./record)

Records section of screen with preferred settings.

### [uair-toggle-and-notify](./uair-toggle-and-notify)

Toggle my pomodoro manager of choice, `uair`, and notify me of time
left.

[..](..)
