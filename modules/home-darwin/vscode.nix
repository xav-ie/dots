# macOS VS Code + Garmin's Monkey C extension for Connect IQ (watch app) dev.
#
# The extension only provides the editor tooling (language server, build/run/
# debug tasks). The actual `monkeyc` compiler, device definitions, and simulator
# come from the Connect IQ SDK, installed out-of-band via SDK Manager
# (/Applications/SdkManager.app) into
# ~/Library/Application Support/Garmin/ConnectIQ. Once an SDK is downloaded, run
# "Monkey C: Verify Installation" from the command palette to confirm the setup.
#
# Extensions are managed via nix-vscode-extensions (no manual versions/shas):
# add a `publisher.name` to the list below and rebuild; bump the whole set with
# `nix flake update nix-vscode-extensions`. VS Code itself comes from the
# `nixpkgs-vscode` input (`nix flake update nixpkgs-vscode` to bump).
{
  # VS Code is unfree and darwin leaves `allowUnfree` off (see modules/common.nix).
  # home-manager runs with useGlobalPkgs, so this system-level predicate is what
  # lets the extensions/package below evaluate. Kept narrow to just vscode.
  flake.modules.darwin.macos =
    { lib, ... }:
    {
      nixpkgs.config.allowUnfreePredicate =
        pkg:
        let
          n = lib.getName pkg;
        in
        n == "vscode" || lib.hasPrefix "vscode-extension-" n;
    };

  flake.modules.homeManager.darwin =
    {
      config,
      pkgs,
      lib,
      inputs,
      fonts,
      ...
    }:
    let
      # Reuse the shared mono font (Maple Mono NF) + its stylistic sets, so the
      # editor and integrated terminal match ghostty/nvim. `calt`/`liga` turn on
      # the coding ligatures; the cv*/ss* sets are Maple's character variants.
      # `pkgs.system` is a deprecated alias (emits an eval warning); read the
      # canonical location once and reuse it below.
      system = pkgs.stdenv.hostPlatform.system;

      monoFont = fonts.name "mono";
      fontLigatures = lib.concatMapStringsSep ", " (f: "'${f}'") (
        fonts.features "mono"
        ++ [
          "calt"
          "liga"
        ]
      );

      # VS Code from a newer nixpkgs (the main lock is older) so it tracks
      # current 1.127+; and nix-vscode-extensions for the extension set, so no
      # extension needs a hand-pinned version/sha256 (auto-updated via
      # `nix flake update nix-vscode-extensions`).
      vscodePkgs = import inputs.nixpkgs-vscode {
        inherit system;
        # vscode + the unfree Copilot extensions (nix-vscode-extensions sources
        # those from nixpkgs, and their unfree check runs against the pkgs that
        # built them — so they must be allowed here, not just in the darwin
        # module's predicate).
        config.allowUnfreePredicate =
          pkg:
          let
            n = lib.getName pkg;
          in
          n == "vscode" || lib.hasPrefix "vscode-extension-" n;
      };
      ext = inputs.nix-vscode-extensions.extensions.${system}.vscode-marketplace;

      # VS Code patched to hide ONLY the macOS traffic lights (native NSWindow
      # buttons — no setting/theme for them). A main-process hook prepended to
      # out/main.js calls setWindowButtonVisibility(false) on every window. The
      # rest of the title bar stays normal. Only a JS *resource* is touched
      # (Mach-O signatures intact); nox boots amfi_get_out_of_my_way=1 so the
      # broken bundle seal isn't enforced. Drop the `package` line below to
      # revert to the stock build.
      vscodeNoTrafficLights = vscodePkgs.vscode.overrideAttrs (old: {
        # nixpkgs sets dontFixup for the prebuilt app, so hook postInstall.
        postInstall = (old.postInstall or "") + ''
          app="$out/Applications/Visual Studio Code.app"
          main="$app/Contents/Resources/app/out/main.js"
          chmod -R u+w "$app"
          cat ${./vscode-hide-traffic-lights.js} "$main" > "$main.new"
          mv -f "$main.new" "$main"
        '';
      });

      # Format-on-save formatter per language, mirroring conform.nvim's mapping.
      # Prettier drives the web languages; the rest use their dedicated LSP.
      prettierLangs = [
        "javascript"
        "javascriptreact"
        "typescript"
        "typescriptreact"
        "json"
        "jsonc"
        "css"
        "scss"
        "less"
        "html"
        "yaml"
        "graphql"
        "markdown"
        "astro"
        "vue"
        "svelte"
      ];
      languageFormatters =
        lib.listToAttrs (
          map (
            l: lib.nameValuePair "[${l}]" { "editor.defaultFormatter" = "esbenp.prettier-vscode"; }
          ) prettierLangs
        )
        // {
          "[nix]"."editor.defaultFormatter" = "jnoortheen.nix-ide";
          "[python]"."editor.defaultFormatter" = "charliermarsh.ruff";
          "[go]"."editor.defaultFormatter" = "golang.go";
          "[rust]"."editor.defaultFormatter" = "rust-lang.rust-analyzer";
        };

      # which-key menu (VSpaceCode.whichkey), mirroring the xnixvim which-key
      # groups. Pressing <leader> (Space) opens this popup instead of firing a
      # raw chord, so the leader space stays discoverable like in nvim.
      wk = key: name: command: {
        inherit key name command;
        type = "command";
      };
      wkGroup = key: name: bindings: {
        inherit key name bindings;
        type = "bindings";
      };
      whichkeyBindings = [
        (wkGroup "f" "+find" [
          # Native fuzzy finders — reliable, no terminal/PATH dependency.
          (wk "f" "Files" "workbench.action.quickOpen")
          (wk "l" "Live grep" "workbench.action.findInFiles")
          (wk "s" "Symbols (workspace)" "workbench.action.showAllSymbols")
          (wk "p" "Projects" "workbench.action.openRecent")
          (wk "b" "Buffers" "workbench.action.showAllEditors")
          (wk "k" "Keymaps" "workbench.action.openGlobalKeybindings")
          (wk "c" "Colorscheme" "workbench.action.selectTheme")
        ])
        (wkGroup "l" "+lsp" [
          (wk "d" "Definition" "editor.action.revealDefinition")
          (wk "r" "References" "editor.action.goToReferences")
          (wk "i" "Implementation" "editor.action.goToImplementation")
          (wk "t" "Type definition" "editor.action.goToTypeDefinition")
          (wk "a" "Code action" "editor.action.quickFix")
          (wk "n" "Rename" "editor.action.rename")
          (wk "f" "Format" "editor.action.formatDocument")
          (wk "g" "Diagnostics" "workbench.actions.view.problems")
          (wk "o" "Document symbols" "workbench.action.gotoSymbol")
          (wk "w" "Workspace symbols" "workbench.action.showAllSymbols")
          (wk "c" "Call hierarchy" "editor.showCallHierarchy")
        ])
        (wkGroup "h" "+git hunk" [
          (wk "s" "Stage hunk" "git.stageSelectedRanges")
          (wk "r" "Reset hunk" "git.revertSelectedRanges")
          (wk "p" "Preview hunk" "editor.action.dirtydiff.next")
          (wk "b" "Blame line" "betterGitLineBlame.toggleInlineAnnotations")
          (wk "d" "Diff this" "git.openChange")
          (wk "R" "Reset buffer" "git.clean")
          (wk "S" "Stage buffer" "git.stage")
        ])
        (wkGroup "c" "+copy path" [
          (wk "a" "Absolute path" "copyFilePath")
          (wk "r" "Relative path" "copyRelativeFilePath")
        ])
        (wkGroup "r" "+refactor" [
          (wk "r" "Refactor menu" "editor.action.refactor")
          (wk "n" "Rename" "editor.action.rename")
        ])
        (wkGroup "t" "+toggle" [
          (wk "t" "Terminal" "workbench.action.terminal.toggleTerminal")
          (wk "b" "Line blame" "betterGitLineBlame.toggleInlineAnnotations")
          (wk "w" "Word wrap" "editor.action.toggleWordWrap")
          (wk "h" "Inlay hints" "editor.action.toggleInlayHints")
        ])
        (wk "g" "Magit status" "magit.status") # neogit analog (kahole.magit)
        (wk "G" "Fugitive (:Git)" "fugitive.open") # fugitive analog (vim-idiomatic)
        (wk "x" "Close editor" "workbench.action.closeActiveEditor") # nvim <leader>x
        (wk "q" "Problems / quickfix" "workbench.actions.view.problems") # nvim <leader>q
      ];

      # VSCodeVim normal-mode maps. Leader opens which-key; the rest are the
      # non-leader maps translated 1:1 from the xnixvim keymaps.
      vimNormalMaps =
        let
          map' = keys: command: {
            before = keys;
            commands = [ command ];
          };
        in
        [
          # <Esc> clears search highlight (nnoremap <Esc> :noh)
          (map' [ "<Esc>" ] ":nohl")

          # <leader> (Space) opens the which-key menu
          (map' [ "<leader>" ] "whichkey.show")

          # `-` reveals the current file in the Explorer (nvim Oil-ish jump)
          (map' [ "-" ] "workbench.files.action.showActiveFileInExplorer")

          # Diagnostics navigation ([d / ]d)
          (map' [ "[" "d" ] "editor.action.marker.prev")
          (map' [ "]" "d" ] "editor.action.marker.next")

          # Git hunk navigation ([c / ]c ~ gitsigns next/prev hunk)
          (map' [ "[" "c" ] "workbench.action.editor.previousChange")
          (map' [ "]" "c" ] "workbench.action.editor.nextChange")

          # Tab/editor-group nav (nvim <C-t>{l,h,n,x} tab keys → editor groups)
          (map' [ "<C-t>" "l" ] "workbench.action.focusNextGroup")
          (map' [ "<C-t>" "h" ] "workbench.action.focusPreviousGroup")
          (map' [ "<C-t>" "n" ] "workbench.action.splitEditor")
          (map' [ "<C-t>" "x" ] "workbench.action.closeEditorsInGroup")

          # Hover (K)
          (map' [ "K" ] "editor.action.showHover")

          # Split navigation — vim-tmux-navigator style <C-h/j/k/l>
          (map' [ "<C-h>" ] "workbench.action.navigateLeft")
          (map' [ "<C-j>" ] "workbench.action.navigateDown")
          (map' [ "<C-k>" ] "workbench.action.navigateUp")
          (map' [ "<C-l>" ] "workbench.action.navigateRight")

          # Buffer cycle (<tab> / <S-tab> ~ bufferline next/prev)
          (map' [ "<tab>" ] "workbench.action.nextEditor")
          (map' [ "<S-tab>" ] "workbench.action.previousEditor")

          # Treesitter incremental selection → VS Code Smart Select (AST-aware
          # grow). <C-n> grows; shrink with <BS> in visual (see visual maps).
          (map' [ "<C-n>" ] "editor.action.smartSelect.expand")
        ];

      # Visual-mode maps: grow/shrink the syntax-aware selection, mirroring the
      # nvim treesitter incremental-selection keys (<C-n> grow / <BS> shrink).
      vimVisualMaps = [
        {
          before = [ "<C-n>" ];
          commands = [ "editor.action.smartSelect.expand" ];
        }
        {
          before = [ "<BS>" ];
          commands = [ "editor.action.smartSelect.shrink" ];
        }
      ];

      # Insert-mode emacs-style motion (the nvim <C-e>/<C-b>/<C-h/j/k/l> maps).
      vimInsertMaps =
        let
          imap = key: command: {
            before = [ key ];
            commands = [ command ];
          };
        in
        [
          (imap "<C-e>" "cursorLineEnd") # end of line
          (imap "<C-b>" "cursorHome") # start of line (first non-blank)
          (imap "<C-h>" "cursorLeft")
          (imap "<C-j>" "cursorDown")
          (imap "<C-k>" "cursorUp")
          (imap "<C-l>" "cursorRight")
        ];
    in
    {
      config = {
        # The SDK tools (monkeyc/monkeydo/simulator) are `java -jar` wrappers, so
        # a JDK must be on PATH — macOS only ships a stub. monkeybrains.jar targets
        # Java 8 bytecode; JDK 17 LTS runs it and is verified working. This puts
        # `java` on PATH for both the terminal and the VS Code extension.
        home.packages = [
          pkgs.jdk17
          # Backing tools for the nix-ide extension (nixd LSP + nixfmt),
          # matching the nixd/nixfmt setup used in xnixvim.
          pkgs.nixd
          pkgs.nixfmt-rfc-style
        ];

        # Let VSCodeVim repeat held keys (j/k/…) instead of popping macOS's
        # press-and-hold accent picker. Written to the *user* domain here —
        # nix-darwin's system.defaults.CustomUserPreferences runs as root and
        # writes root's domain, so it never affected the logged-in user. Read at
        # VS Code launch, so a full quit (Cmd+Q) is needed to pick it up.
        home.activation.vscodePressAndHold = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run /usr/bin/defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool false
        '';

        # Continue config for Mercury Coder — Inception's official VS Code path
        # for FIM autocomplete + Next-Edit (the cursortab/Mercury analog from
        # xnixvim). The API key is NOT here: enter INCEPTION_API_KEY once in
        # Continue's UI (Cmd+Shift+P → "Continue: Add model" / secret), stored in
        # VS Code's encrypted SecretStorage. After first run, enable Next-Edit
        # from Continue's status-bar menu ("Use Next Edit autocomplete over FIM").
        home.file.".continue/config.yaml".text = ''
          name: dots-assistant
          version: 1.0.0
          schema: v1
          models:
            - name: Mercury Coder
              provider: inception
              model: mercury-coder
              apiKey: ''${{ secrets.INCEPTION_API_KEY }}
              roles:
                - autocomplete
              capabilities:
                - next_edit
        '';

        programs.vscode = {
          enable = true;
          # Traffic lights hidden; rest of the title bar is normal (see above).
          package = vscodeNoTrafficLights;

          profiles.default = {
            # Extensions are pinned via Nix; silence VS Code's own update nagging.
            enableUpdateCheck = false;
            enableExtensionUpdateCheck = false;

            userSettings =
              {
                # Every Monkey C build is signed with this developer key. Generated
                # once (imperatively, since it's a personal secret and must stay
                # stable across app-store updates) with:
                #   mkdir -p ~/.config/garmin
                #   openssl genrsa -out /tmp/k.pem 4096
                #   openssl pkcs8 -topk8 -inform PEM -outform DER \
                #     -in /tmp/k.pem -out ~/.config/garmin/developer_key.der -nocrypt
                "monkeyC.developerKeyPath" = "${config.home.homeDirectory}/.config/garmin/developer_key.der";

                # xdusk colorscheme (generated from the shared palette in the
                # xdusk flake — the sibling of the Neovim theme in xnixvim).
                "workbench.colorTheme" = "xdusk";

                # The title bar hides in fullscreen (native or Zen fullscreen)
                # only when it has no *interactive* content. Bisected: the
                # Command Center pill and the layout-control icons each force the
                # bar to stay visible even in fullscreen, so both stay off; the
                # Copilot chat icons are fine (bar still hides with them on).
                # customTitleBarVisibility "never" is what lets it collapse.
                "window.titleBarStyle" = "custom";
                "window.customTitleBarVisibility" = "never";
                "window.commandCenter" = false;
                "workbench.layoutControl.enabled" = false;
                "chat.commandCenter.enabled" = true;

                # Keep Zen Mode from centering the editor (its default is true),
                # which was leaving the text area narrow with left/right gaps.
                "zenMode.centerLayout" = false;

                # Sidebar + activity-bar nav icons on the right edge.
                "workbench.sideBar.location" = "right";
                # Slimmer activity bar (smaller icons, tighter strip).
                "workbench.activityBar.compact" = true;

                # Don't prompt about / optimize for screen readers.
                "editor.accessibilitySupport" = "off";

                # Animate Ctrl+D / Ctrl+U (and all scrolling) instead of jumping.
                # VSCodeVim's half-page motions only ease when this is enabled.
                "editor.smoothScrolling" = true;
                "editor.cursorSmoothCaretAnimation" = "on";

                # Integrated terminal runs nushell (login shell stays zsh).
                "terminal.integrated.defaultProfile.osx" = "nushell";
                "terminal.integrated.profiles.osx".nushell.path = lib.getExe config.programs.nushell.package;
                # VS Code launched from the Dock inherits a truncated PATH, so its
                # integrated terminals (and find-it-faster's bash helper) can't see
                # the Nix-installed fzf/rg/fd/bat. Prepend the Nix profile bins.
                "terminal.integrated.env.osx".PATH = lib.concatStringsSep ":" [
                  "/etc/profiles/per-user/${config.home.username}/bin"
                  "/run/current-system/sw/bin"
                  "/nix/var/nix/profiles/default/bin"
                  "\${env:PATH}"
                ];

                # Fonts: Maple Mono NF everywhere (matches nvim guifont + ghostty).
                # Setting the terminal family to the Nerd Font is what makes
                # nushell's glyphs/icons render instead of tofu boxes.
                "editor.fontFamily" = "${monoFont}, monospace";
                "editor.fontSize" = 14;
                "editor.fontLigatures" = fontLigatures;
                "terminal.integrated.fontFamily" = "${monoFont}, monospace";
                "terminal.integrated.fontSize" = 13;

                # Drive the nix-ide extension through nixd + nixfmt (as in xnixvim).
                "nix.enableLanguageServer" = true;
                "nix.serverPath" = lib.getExe pkgs.nixd;
                # nix-ide 0.5.x made `nix.formatterPath` a name-enum (nixfmt/
                # alejandra/treefmt/...), no longer a path — nixd does the real
                # formatting via `nixd.formatting.command` (the store nixfmt).
                "nix.formatterPath" = "nixfmt";
                "nix.serverSettings".nixd.formatting.command = [ (lib.getExe pkgs.nixfmt-rfc-style) ];

                # todo-tree bundles @vscode/ripgrep (github.com/microsoft/vscode-ripgrep),
                # a prebuilt rg binary that nix-vscode-extensions strips from the build
                # — hence "Failed to find vscode-ripgrep". Point it at Nix's ripgrep.
                "todo-tree.ripgrep.ripgrep" = lib.getExe pkgs.ripgrep;

                # --- Editor options mirrored from xnixvim (config/config.nix) -----
                "editor.lineNumbers" = "on"; # absolute (relativenumber = false in nvim)
                "editor.cursorSurroundingLines" = 2; # scrolloff = 2
                "editor.tabSize" = 2; # shiftwidth/tabstop = 2
                "editor.insertSpaces" = true; # expandtab
                "editor.wordWrap" = "on"; # linebreak wrap
                "editor.wrappingIndent" = "same";
                "search.smartCase" = true; # smartcase (+ ignorecase)
                "editor.bracketPairColorization.enabled" = true; # blink.pairs rainbow

                # More xnixvim parity — editor feel:
                "editor.stickyScroll.enabled" = true; # treesitter-context: scope pinned to top
                "editor.stickyScroll.maxLineCount" = 5;
                "editor.guides.bracketPairs" = "active"; # rainbow bracket guides (blink.pairs)
                "editor.guides.highlightActiveIndentation" = true; # indent-blankline scope line
                "editor.semanticHighlighting.enabled" = true; # LSP semantic tokens (xdusk theme)
                "editor.inlayHints.enabled" = "on"; # LSP inlay hints (<leader>th toggles in nvim)
                "editor.linkedEditing" = true; # rename paired HTML/JSX tags (nvim-ts-autotag)
                "editor.cursorBlinking" = "solid"; # ghostty cursor-style-blink = false
                "editor.minimap.enabled" = false; # nvim uses a thin scrollbar, not a minimap
                # Scroll past EOF so the last line can be centered (nvim fills
                # below EOF with `~`, giving the same "extra scroll" room).
                "editor.scrollBeyondLastLine" = true;
                # Inline line blame comes from Better Git Line Blame instead of
                # GitLens (leaner, and its toggle is on <leader>tb/hb). Text-only
                # to match gitsigns; GitLens stays for hovers/history but both its
                # inline AND status-bar blame are off so only BGLB's inline shows.
                "gitlens.currentLine.enabled" = false;
                "gitlens.statusBar.enabled" = false;
                "betterGitLineBlame.showInlineAnnotations" = true;
                "betterGitLineBlame.showStatusBarItem" = false;
                "betterGitLineBlame.showAuthorAvatar" = false;

                # nvim-feel workbench defaults:
                "workbench.editor.enablePreview" = false; # open files as real buffers, not italic previews
                "workbench.startupEditor" = "none"; # no welcome tab (nvim has no dashboard)
                "workbench.list.smoothScrolling" = true;
                "terminal.integrated.smoothScrolling" = true;
                "editor.emptySelectionClipboard" = false; # yank/copy only what's selected (vim-like)
                "editor.hover.delay" = 300; # CursorHold-ish diagnostic/hover popup
                "editor.occurrencesHighlight" = "singleFile"; # vim-illuminate: highlight symbol under cursor

                # Spell check prose only, mirroring the nvim proseSpell autocmd
                # (code stays unchecked; nvim only spells markdown/gitcommit/text).
                "cSpell.enabledFileTypes" = {
                  "*" = false;
                  markdown = true;
                  plaintext = true;
                  git-commit = true;
                  latex = true;
                  tex = true;
                  restructuredtext = true;
                };

                # conform.nvim trims trailing whitespace / blank lines on save.
                "files.trimTrailingWhitespace" = true;
                "files.insertFinalNewline" = true;
                "files.trimFinalNewlines" = true;
                # …except markdown, where trailing spaces are meaningful line breaks.
                "[markdown]"."files.trimTrailingWhitespace" = false;

                # --- VSCodeVim: emulate the nvim plugin ergonomics ----------------
                "vim.leader" = "<space>"; # mapleader = Space
                "vim.hlsearch" = true;
                "vim.ignorecase" = true;
                "vim.smartcase" = true;
                "vim.surround" = true; # nvim-surround (ys/cs/ds)
                "vim.easymotion" = true; # closest analog to flash.nvim `s`
                "vim.highlightedyank.enable" = true; # flash yanked text (tiny-glimmer)
                "vim.highlightedyank.duration" = 200;
                "vim.highlightedyank.color" = "#FFD24255"; # xdusk yellow, translucent
                "vim.foldfix" = true;
                "vim.normalModeKeyBindingsNonRecursive" = vimNormalMaps;
                "vim.visualModeKeyBindingsNonRecursive" = vimVisualMaps;
                "vim.insertModeKeyBindingsNonRecursive" = vimInsertMaps;

                # which-key popup menu (VSpaceCode.whichkey), opened by <leader>.
                "whichkey.bindings" = whichkeyBindings;
                "whichkey.sortOrder" = "alphabetically";
                "whichkey.delay" = 0;

                # --- Format on save (conform.nvim format_on_save) -----------------
                "editor.formatOnSave" = true;
                "editor.codeActionsOnSave"."source.fixAll.eslint" = "explicit";
              }
              # recursiveUpdate (not //) so per-language keys like "[markdown]"
              # deep-merge with the trim/format settings above instead of clobbering.
              |> lib.recursiveUpdate languageFormatters;

            keybindings = [
              {
                # Magit binds `k` to discard-at-point (Emacs convention, and
                # destructive). Free it so VSCodeVim's `k` moves up by line, like
                # neogit. Section jumps stay on Ctrl+j / Ctrl+k; discard is still
                # available from the Magit menu / Command Palette.
                key = "k";
                command = "-magit.discard-at-point";
              }
              {
                # `-` toggles the explorer like nvim Oil: from the editor it
                # reveals the file (VSCodeVim map), and from inside the explorer
                # it closes the sidebar. `!inputFocus` so `-` still types while
                # renaming a file.
                key = "-";
                command = "workbench.action.toggleSidebarVisibility";
                when = "filesExplorerFocus && !inputFocus";
              }
              # `>` / `<` expand/collapse the hunk/section under the cursor in
              # Magit (Tab natively) and Fugitive (`)` natively), matching the
              # quicker.nvim `>`/`<` muscle memory. Both keys toggle.
              {
                key = "shift+.";
                command = "magit.toggle-fold";
                when = "editorTextFocus && editorLangId == 'magit'";
              }
              {
                key = "shift+,";
                command = "magit.toggle-fold";
                when = "editorTextFocus && editorLangId == 'magit'";
              }
              {
                key = "shift+.";
                command = "fugitive.toggleInlineDiff";
                when = "editorTextFocus && resourceScheme == fugitive";
              }
              {
                key = "shift+,";
                command = "fugitive.toggleInlineDiff";
                when = "editorTextFocus && resourceScheme == fugitive";
              }
            ];

            extensions = [
              # Locally-built xdusk color theme (not a marketplace extension).
              inputs.xdusk.packages.${system}.vscode
              # Unfree extensions (Copilot Chat, Remote-SSH, Claude Code) — sourced
              # from nixpkgs via vscodePkgs so the unfree allowance applies
              # (nix-vscode-extensions' own pkgs config would reject them).
              vscodePkgs.vscode-extensions.github.copilot-chat
              vscodePkgs.vscode-extensions.ms-vscode-remote.remote-ssh
              vscodePkgs.vscode-extensions.ms-vscode-remote.remote-ssh-edit
              vscodePkgs.vscode-extensions.anthropic.claude-code
            ]
            # Everything else via nix-vscode-extensions (auto version + sha).
            ++ (with ext; [
              # Editor / vim / AI
              vscodevim.vim
              vspacecode.whichkey
              continue.continue
              # Garmin Connect IQ (see file header for SDK setup)
              garmin.monkey-c
              # LSPs / formatters / linters
              jnoortheen.nix-ide
              esbenp.prettier-vscode
              charliermarsh.ruff
              ms-python.python
              dbaeumer.vscode-eslint
              rust-lang.rust-analyzer
              golang.go
              # Editor quality-of-life
              usernamehw.errorlens
              gruntfuggly.todo-tree
              christian-kohler.path-intellisense
              formulahendry.auto-rename-tag
              naumovs.color-highlight
              streetsidesoftware.code-spell-checker
              # Data / schema languages
              redhat.vscode-yaml
              tamasfe.even-better-toml
              graphql.vscode-graphql
              graphql.vscode-graphql-syntax
              # Web frameworks + niche languages
              astro-build.astro-vscode
              svelte.svelte-vscode
              vue.volar
              swiftlang.swift-vscode
              llvm-vs-code-extensions.lldb-dap
              ziglang.vscode-zig
              slevesque.shader
              # Env / git
              mkhl.direnv
              eamodio.gitlens
              mk12.better-git-line-blame
              kahole.magit
              hnrk-str.vscode-fugitive
              # (Remote-SSH is unfree/nixpkgs-sourced → in the vscodePkgs list above)
              # Containers / web debugging + testing
              ms-azuretools.vscode-containers
              ms-edgedevtools.vscode-edge-devtools
              firefox-devtools.vscode-firefox-debug
              ms-playwright.playwright
              davidanson.vscode-markdownlint
              # TS/web ergonomics + project tooling
              yoavbls.pretty-ts-errors
              wix.vscode-import-cost
              editorconfig.editorconfig
              github.vscode-pull-request-github
              aaron-bond.better-comments
              # Notes / fun
              foam.foam-vscode
              tonybaloney.vscode-pets
            ]);
          };
        };
      };
    };
}
