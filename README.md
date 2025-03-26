# dots ◌ ⋅ ⋯ ⦿ .̇ ⨀ ⊚ ⋮ ○ ∘ ⦾ : … ◎ <a href="https://builtwithnix.org"><img src="https://builtwithnix.org/badge.svg" alt="built with nix" height="39" align="right"/></a>

I love Nix! It has helped me further my development more than any
other tool I have used. I hope that my config is helpful for you. If you
have questions, please create an issue or privately message me by
emailing github@xav.ie <3.

You might also enjoy my [Neovim Config](https://github.com/xav-ie/xnixvim).

```mermaid
---
config:
  theme: base
  themeVariables:
    primaryColor: "#1a0020"
    primaryTextColor: "#fa99fa"
    primaryBorderColor: "#aaaafa"
    lineColor: "#888"
    fontFamily: "monospace"
---
classDiagram
    %% Unfortunately, we cannot use relative links and must specify a branch :/
    class lib["<a href='https://github.com/xav-ie/dots/tree/main/lib'>./lib</a>"]
    class darwinConfigurations["<a href='https://github.com/xav-ie/dots/tree/main/darwinConfigurations'>./darwinConfigurations</a>"]
    class home-manager["<a href='https://github.com/xav-ie/dots/tree/main/home-manager'>./home-manager</a>"]
    class nixosConfigurations["<a href='https://github.com/xav-ie/dots/tree/main/nixosConfigurations'>./nixosConfigurations</a>"]
    class overlays["<a href='https://github.com/xav-ie/dots/tree/main/overlays'>./overlays</a>"]
    class packages["<a href='https://github.com/xav-ie/dots/tree/main/packages'>./packages</a>"]

    lib: overlay setup,
    lib:  nix settings,
    lib:  utilities
    darwinConfigurations: • stella
    home-manager: hm modules and setup
    home-manager: for linux and mac
    nixosConfigurations: • praesidium
    overlays: package overrides
    packages: • cache-command
    packages: • jira-list
    packages: • record
    packages: • record-section
    packages: • ...

    lib ..> overlays
    darwinConfigurations ..> lib
    darwinConfigurations ..> home-manager
    nixosConfigurations ..> lib
    nixosConfigurations ..> home-manager
```

<div align="center">
    <em>Project Layout</em>
</div>

## Usage

I don't think you should try and directly use my dotfiles; it probably
would not work. You should instead check out my [packages](./packages) and
other bits of config.

## Things I am working on

<details>
<summary>Secrets</summary>
I want to configure secrets the "right way".

- [ ] Use `pass` or `age` to just store all my ENV variables, but
      then it is another master password to remember, so I think I would
      rather figure something out with the Bitwarden CLI, my manager of
      choice. Honestly, I don't really know the best course of action,
      because what if I want to change my manager?? I might also want to
      just completely forgo Bitwarden and just use good old encryption...
      There has to be someone else who thought of this
- [ ] Look into these secret solutions others have worked on:

  - [Secrets Management with SOPS-NIX by Vimjoyer](https://youtube.com/watch?v=G5f6GC7SnhU)
  - [NixOS Secrets Management by Emergent Mind](https://youtube.com/watch?v=G5f6GC7SnhU)
  - [Encrypted Secrets with NixOS](https://xeiaso.net/blog/nixos-encrypted-secrets-2021-01-20/)
  - [A Modern and Secure Desktop Setup](https://discourse.nixos.org/t/a-modern-and-secure-desktop-setup/41154)
  - [We should manage secrets the SystemD way!](https://youtube.com/watch?v=YFXwV0ZO9NE)
  - [Alternative way to handle secrets](https://discourse.nixos.org/t/alternative-way-to-handle-secrets/35511)
  - [Introducing Secrix](https://journal.platonic.systems/introducing-secrix)
  - [Handling Secrets in NixOS: An Overview](https://discourse.nixos.org/t/handling-secrets-in-nixos-an-overview-git-crypt-agenix-sops-and-when-to-use-them/35462)
  </details>

<details>
<summary>IOT</summary>
I have some things in my house that I want control with my computer.

- Computer lights are semi-controllable through `open-rgb -p`, but I
  need to set up more profiles.
</details>

<details>
<summary>Waybar replacement</summary>
I am not 100% happy with Waybar. It is a great tool for getting started,
but I want complete control. Also, the blur is controled through hacks.
Vimjoyer made a video on AGS: https://youtube.com/watch?v=GvpTUKaXqNk

I think this is a good idea to learn because it seems extremely
extensible to make future applications.

This should also mean I get keyboard access!

</details>

<details>
<summary>Firefox Sync</summary>

- [ ] I need to just make my Firefox configured more through Nix. A
      lot of my plugins and settings are not 100% synced properly.
- [ ] I also need to find an RSS reader that can read/sync with a filesystem. I
  am currently using FeedBro, but it does not sync between
    my desktop and laptop.
</details>

<details>
<summary>Automated Testing</summary>
You will notice that a lot of my commits are update, then fixing the
update. This is because I update depencies from my desktop or laptop,
and then update from the other. This often leads to build time errors
that only occurs on the other system due to new options/drivers/etc.

There is a person who has a twitter thread (I can't remember who >:[)
who explain how they set up automated GitHub CI to test their config.

This would be **amazing** and I want to set this up, too.

I also want it to be where it will also boot up the desktop and take a
screenshot of it open and maybe even do some actions.

</details>

<details>
<summary>Miscellaneous</summary>

- [ ] Global mute - this will require building a virtual HID device
      that is recognized by Zoom. Then, when you mute this virtual device,
      the state is reflected in Zoom as well. This opens up many
      possibilities, the most obvious being a notification tray icon you
      can use to easily see muted state
- [ ] Backgrounds repo/drive sync: I need to sync my backgrounds with
      proton drive.
- [ ] Email notifications - web browser email notifications are
      acceptable, but they do not have a "delete" nor a "mark as read
      action", which would really help me to get to inbox 0.
- [ ] PETS - I really want to modify Spamton-Linux-Shimejii repo to
      have multiple different types of Shimejii. Right now, there is just
      this really ugly one. I also want to fix the divide by zero errors
      that keep making it crash.
- [ ] Email - just set up Himalaya email client in vim.
- [ ] Reminders - I want my GCal to appear in my system and I want to
      be able to easily manage past and future reminders, a calendar. So I
      just have to set up a good and pretty system calendar
- [ ] Pomodoro - Set up system pomodoro
- [ ] Screen sharing - I would prefer some bindings and a bit more
      chrome/indicators in my bar to show that I am sharing screen. I
      dislike that I could be screen sharing and not really be aware that I
      am.
- [ ] Do Not Disturb - I would like to trigger DND when I am
      screen sharing. I really dislike that notifications come through on
      screen share. Maybe I can still allow notifications, but hide them
      from screen share entirely??? That would be really cool.
- [ ] Use nix-colors repo for coloring everything This is interesting:
      [colemickens/nixcfg/mixins/\_preferences.nix](https://github.com/colemickens/nixcfg/blob/3705032fd67f231fe83fd3bc25d4021b80394b1c/mixins/_preferences.nix)
- [ ] Create a zellij key overlay plugin
  - [ ] [awesome-zellij](https://github.com/zellij-org/awesome-zellij)
  - [ ] [zellij plugin system walk through](https://github.com/Kangaxx-0/first-zellij-plugin)
  - [ ] [Learning from Developing a Zellij Plugin](https://blog.nerd.rocks/posts/profiling-zellij-plugins/)
  - [ ] [Common Snippets for Developing Zellij Plugins](https://blog.nerd.rocks/posts/common-snippets-for-zellij-development/)
- [ ] Try out and get good at Jujutsu
  - [ ] [What if version control was AWESOME?](https://www.youtube.com/watch?v=2otjrTzRfVk)
  - [ ] [jj-init](https://v5.chriskrycho.com/essays/jj-init/)
  - [ ] [Steve's Jujutsu Tutorial](https://steveklabnik.github.io/jujutsu-tutorial)
  - [ ] [Jujutsu Tutorial](https://jj-vcs.github.io/jj/latest/tutorial/)
  </details>

## Other Nix Configs

I used these configs to help build mine:

- [Misterio77/nix-config](https://github.com/Misterio77/nix-config/blob/e360a9ecf6de7158bea813fc075f3f6228fc8fc0)
- [clemak27/linux_setup](https://github.com/clemak27/linux_setup/blob/4970745992be98b0d00fdae336b4b9ee63f3c1af)
- [CosmicHalo/AndromedaNixos](https://github.com/CosmicHalo/AndromedaNixos/blob/665668415fa72e850d322adbdacb81c1251301c0)

I definitely used a lot more, utilizing mostly GitHub search.
